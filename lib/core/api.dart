import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'environment.dart';
import 'session.dart';
import 'sse.dart';

class ApiError implements Exception {
  const ApiError(this.code, [this.status = 0]);
  final String code;
  final int status;
  @override
  String toString() => code;
}

class EventConnection {
  EventConnection(this.client, this.events);
  final http.Client client;
  final Stream<ServerEvent> events;
  void close() => client.close();
}

class TypefluxApi {
  static final _sessionWrites = Expando<Map<String, Future<void>>>();
  TypefluxApi({
    required this.origin,
    required this.vault,
    http.Client? client,
    http.Client Function()? streamClientFactory,
  }) : _client = client ?? http.Client(),
       _streamClientFactory = streamClientFactory ?? http.Client.new {
    validateOrigin(origin);
  }

  static void validateOrigin(Uri origin) =>
      ApiOriginPolicy.fromBuild.validate(origin);

  final Uri origin;
  final Vault vault;
  final http.Client _client;
  final http.Client Function() _streamClientFactory;
  Session? session;
  Future<void>? _refreshing;
  int _generation = 0;
  String get sessionKey => 'session:${origin.origin}';
  bool get signedIn => session != null;

  Future<void> restore() async {
    final saved = await vault.read(sessionKey);
    if (saved == null) return;
    try {
      session = Session.fromJson(jsonDecode(saved) as Map<String, dynamic>);
    } on FormatException {
      await vault.delete(sessionKey);
    } on TypeError {
      await vault.delete(sessionKey);
    }
  }

  Future<void> login(String email, String password) async {
    final generation = ++_generation;
    final data = await request(
      'POST',
      '/auth/login',
      body: {'email': email, 'password': password},
      authenticated: false,
    );
    final next = Session.fromJson(data as Map<String, dynamic>);
    await _storeSession(next, generation);
  }

  Future<void> loginWithApple(String idToken) async {
    final generation = ++_generation;
    final data = await request(
      'POST',
      '/auth/oauth/apple',
      body: {'id_token': idToken},
      authenticated: false,
    );
    await _storeSession(
      Session.fromJson(data as Map<String, dynamic>),
      generation,
    );
  }

  Future<void> changePassword({
    String? oldPassword,
    required String newPassword,
  }) async {
    await request(
      'POST',
      '/auth/change-password',
      body: {'old_password': ?oldPassword, 'new_password': newPassword},
    );
  }

  Future<void> logout() async {
    final old = session;
    _generation++;
    session = null;
    await _sessionTransaction(() => vault.delete(sessionKey));
    if (old != null) {
      try {
        await request(
          'POST',
          '/auth/logout',
          body: {'refresh_token': old.refresh},
          authenticated: false,
        ).timeout(const Duration(seconds: 5));
      } catch (_) {
        /* Local credentials are already removed. */
      }
    }
  }

  /// Abandons only this instance's credentials without revoking another login.
  /// Unlike logout, this rollback does not send a remote logout request.
  Future<void> discardSession() async {
    final old = session;
    _generation++;
    session = null;
    if (old == null) return;
    await _sessionTransaction(() async {
      if (await vault.read(sessionKey) == old.encode()) {
        await vault.delete(sessionKey);
      }
    });
  }

  Future<void> refresh() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  Future<void> _refresh() async {
    final old = session;
    final generation = _generation;
    if (old == null) throw const ApiError('AUTH_REQUIRED', 401);
    try {
      final data = await request(
        'POST',
        '/auth/refresh',
        body: {'refresh_token': old.refresh},
        authenticated: false,
      );
      if (_generation != generation) {
        throw const ApiError('SESSION_CHANGED', 401);
      }
      final next = Session.fromJson(data as Map<String, dynamic>);
      await _storeSession(next, generation);
    } on ApiError catch (error) {
      if ((error.status == 401 || error.status == 403) &&
          _generation == generation) {
        session = null;
        await _sessionTransaction(() async {
          if (await vault.read(sessionKey) == old.encode()) {
            await vault.delete(sessionKey);
          }
        });
      }
      rethrow;
    }
  }

  Future<void> _sessionTransaction(Future<void> Function() action) {
    final writes = _sessionWrites[vault] ??= <String, Future<void>>{};
    final previous = writes[sessionKey] ?? Future<void>.value();
    final result = previous.then((_) => action());
    writes[sessionKey] = result.catchError((Object _) {});
    return result;
  }

  Future<void> _storeSession(Session next, int generation) =>
      _sessionTransaction(() async {
        if (_generation != generation) {
          throw const ApiError('SESSION_CHANGED', 401);
        }
        await vault.write(sessionKey, next.encode());
        if (_generation != generation) {
          // Serialized across API instances sharing this vault and origin.
          await vault.delete(sessionKey);
          throw const ApiError('SESSION_CHANGED', 401);
        }
        session = next;
      });

  Uri uri(String path) => origin.resolve('/api/v1$path');
  Map<String, String> headers([String? token]) => {
    'Content-Type': 'application/json',
    'X-Typeflux-Model-Catalog': '1',
    'X-Scenario': 'ask-anything',
    if (token != null) 'Authorization': 'Bearer $token',
  };
  Future<String> token() async {
    if (session == null) throw const ApiError('AUTH_REQUIRED', 401);
    if (session!.expiresAt <=
        DateTime.now().millisecondsSinceEpoch ~/ 1000 + 30) {
      await refresh();
    }
    return session!.access;
  }

  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
    String scenario = 'ask-anything',
  }) async {
    final used = authenticated ? await token() : null;
    Future<http.Response> send(String? access) async {
      final req = http.Request(method, uri(path))
        ..headers.addAll({...headers(access), 'X-Scenario': scenario});
      if (body != null) req.body = jsonEncode(body);
      return http.Response.fromStream(await _client.send(req));
    }

    var response = await send(used).timeout(const Duration(seconds: 210));
    if (response.statusCode == 401 &&
        authenticated &&
        _expiredToken(response)) {
      if (session?.access == used) await refresh();
      response = await send(await token())
          .timeout(const Duration(seconds: 210));
    }
    return decodeResponse(response);
  }

  static bool _expiredToken(http.Response response) {
    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return data is Map &&
          [
            'UNAUTHORIZED',
            'AUTH_REQUIRED',
            'AUTH_INVALID_TOKEN',
          ].contains(data['code']);
    } catch (_) {
      return false;
    }
  }

  static dynamic decodeResponse(http.Response response) {
    Map<String, dynamic> envelope;
    try {
      envelope =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiError('INVALID_RESPONSE', response.statusCode);
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        envelope['code'] != 'OK') {
      throw ApiError(
        envelope['code'] as String? ?? 'REQUEST_FAILED',
        response.statusCode,
      );
    }
    return envelope['data'];
  }

  Future<EventConnection> events(String id) async {
    final client = _streamClientFactory();
    try {
      var used = await token();
      Future<http.StreamedResponse> send() => client.send(
        http.Request('GET', uri('/ask/conversations/$id/events'))
          ..headers.addAll({...headers(used), 'Accept': 'text/event-stream'}),
      );
      var response = await send().timeout(const Duration(seconds: 15));
      if (response.statusCode == 401) {
        await response.stream.drain<void>();
        if (session?.access == used) await refresh();
        used = await token();
        response = await send().timeout(const Duration(seconds: 15));
      }
      if (response.statusCode != 200) {
        decodeResponse(await http.Response.fromStream(response));
        throw ApiError('STREAM_UNAVAILABLE', response.statusCode);
      }
      if (!(response.headers['content-type'] ?? '').contains(
        'text/event-stream',
      )) {
        throw const ApiError('INVALID_STREAM');
      }
      return EventConnection(
        client,
        decodeEvents(response.stream.timeout(const Duration(seconds: 40))),
      );
    } catch (_) {
      client.close();
      rethrow;
    }
  }

  void close() {
    _generation++;
    _client.close();
  }
}
