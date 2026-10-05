import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:typeflux_app/core/api.dart';
import 'package:typeflux_app/core/session.dart';

import 'support/fakes.dart';

http.Response ok(Object? data) => http.Response(
  jsonEncode({'code': 'OK', 'data': data}),
  200,
  headers: {'content-type': 'application/json'},
);

class PausedReadVault extends MemoryVault {
  final readStarted = Completer<void>();
  final releaseRead = Completer<void>();
  bool pauseNextRead = true;

  @override
  Future<String?> read(String key) async {
    final snapshot = await super.read(key);
    if (pauseNextRead) {
      pauseNextRead = false;
      readStarted.complete();
      await releaseRead.future;
    }
    return snapshot;
  }
}

void main() {
  test('discarding an old API never removes a newer stored login', () async {
    final vault = MemoryVault();
    var oldRequests = 0;
    final old = TypefluxApi(
      origin: Uri.parse('https://example.com'),
      vault: vault,
      client: MockClient((_) async {
        oldRequests++;
        return ok({});
      }),
    )..session = const Session('old', 'old-refresh', 9999999999);
    final next = TypefluxApi(
      origin: old.origin,
      vault: vault,
      client: MockClient(
        (_) async => ok({
          'access_token': 'new',
          'refresh_token': 'new-refresh',
          'expires_at': 9999999999,
        }),
      ),
    );
    addTearDown(old.close);
    addTearDown(next.close);
    await vault.write(old.sessionKey, old.session!.encode());
    await next.login('new@example.com', 'New12345');
    await old.discardSession();
    expect(old.signedIn, isFalse);
    expect(next.signedIn, isTrue);
    expect(jsonDecode(vault.values[next.sessionKey]!)['access_token'], 'new');
    expect(oldRequests, 0);
  });

  test(
    'discard compare and delete are serialized with another login write',
    () async {
      final vault = PausedReadVault();
      final old = TypefluxApi(
        origin: Uri.parse('https://example.com'),
        vault: vault,
      )..session = const Session('old', 'old-refresh', 9999999999);
      final next = TypefluxApi(
        origin: old.origin,
        vault: vault,
        client: MockClient(
          (_) async => ok({
            'access_token': 'new',
            'refresh_token': 'new-refresh',
            'expires_at': 9999999999,
          }),
        ),
      );
      addTearDown(old.close);
      addTearDown(next.close);
      await vault.write(old.sessionKey, old.session!.encode());
      final discarding = old.discardSession();
      await vault.readStarted.future;
      final login = next.login('new@example.com', 'New12345');
      await Future<void>.delayed(Duration.zero);
      // The old read is deliberately paused after it captured the old token.
      // A new token must not be written until the compare/delete finishes.
      expect(next.signedIn, isFalse);
      expect(jsonDecode(vault.values[next.sessionKey]!)['access_token'], 'old');
      vault.releaseRead.complete();
      await Future.wait([discarding, login]);
      expect(old.signedIn, isFalse);
      expect(next.signedIn, isTrue);
      expect(jsonDecode(vault.values[next.sessionKey]!)['access_token'], 'new');
    },
  );

  test(
    'a cancelled login cannot persist credentials after another login',
    () async {
      final vault = MemoryVault();
      final gate = Completer<http.Response>();
      final old = TypefluxApi(
        origin: Uri.parse('https://example.com'),
        vault: vault,
        client: MockClient((_) => gate.future),
      );
      final attempt = old.login('old@example.com', 'Old12345');
      final expectation = expectLater(
        attempt,
        throwsA(
          isA<ApiError>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      old.close();
      final next = TypefluxApi(
        origin: Uri.parse('https://example.com'),
        vault: vault,
        client: MockClient(
          (_) async => ok({
            'access_token': 'new',
            'refresh_token': 'new-refresh',
            'expires_at': 9999999999,
          }),
        ),
      );
      await next.login('new@example.com', 'New12345');
      gate.complete(
        ok({
          'access_token': 'old',
          'refresh_token': 'old-refresh',
          'expires_at': 9999999999,
        }),
      );
      await expectation;
      expect(jsonDecode(vault.values[next.sessionKey]!)['access_token'], 'new');
      expect(next.signedIn, isTrue);
      next.close();
    },
  );
  test(
    'wrong current password is not replayed or treated as an expired session',
    () async {
      var requests = 0;
      final api = TypefluxApi(
        origin: Uri.parse('https://example.com'),
        vault: MemoryVault(),
        client: MockClient((request) async {
          requests++;
          expect(request.url.path, '/api/v1/auth/change-password');
          expect(jsonDecode(request.body), {
            'old_password': 'Wrong123',
            'new_password': 'Changed123',
          });
          return http.Response('{"code":"AUTH_INVALID_CREDENTIALS"}', 401);
        }),
      )..session = const Session('access', 'refresh', 9999999999);
      await expectLater(
        api.changePassword(oldPassword: 'Wrong123', newPassword: 'Changed123'),
        throwsA(
          isA<ApiError>().having(
            (e) => e.code,
            'code',
            'AUTH_INVALID_CREDENTIALS',
          ),
        ),
      );
      expect(requests, 1);
      expect(api.signedIn, isTrue);
      api.close();
    },
  );
  test(
    'requires TLS outside local development and rejects credential-bearing URL',
    () {
      for (final origin in [
        'http://example.com',
        'https://user:password@example.com',
        'https://example.com/path',
      ]) {
        expect(
          () => TypefluxApi(origin: Uri.parse(origin), vault: MemoryVault()),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'concurrent requests serialize token refresh and attach required headers',
    () async {
      var refreshes = 0;
      final gate = Completer<void>();
      final api = TypefluxApi(
        origin: Uri.parse('https://example.com'),
        vault: MemoryVault(),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/refresh')) {
            refreshes++;
            await gate.future;
            return ok({
              'access_token': 'new',
              'refresh_token': 'next',
              'expires_at': 9999999999,
            });
          }
          expect(request.headers['Authorization'], 'Bearer new');
          expect(request.headers['X-Typeflux-Model-Catalog'], '1');
          return ok([]);
        }),
      )..session = const Session('old', 'refresh', 0);
      final a = api.request('GET', '/ask/conversations');
      final b = api.request('GET', '/ask/conversations/models');
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await Future.wait([a, b]);
      expect(refreshes, 1);
      api.close();
    },
  );
  test(
    'a 401 refreshes once and reuses the original message identifier',
    () async {
      final ids = <String>[];
      final api = TypefluxApi(
        origin: Uri.parse('https://example.com'),
        vault: MemoryVault(),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/refresh')) {
            return ok({
              'access_token': 'new',
              'refresh_token': 'next',
              'expires_at': 9999999999,
            });
          }
          ids.add(jsonDecode(request.body)['id']);
          return request.headers['Authorization'] == 'Bearer old'
              ? http.Response('{"code":"AUTH_INVALID_TOKEN"}', 401)
              : ok({'id': 'conversation'});
        }),
      )..session = const Session('old', 'refresh', 9999999999);
      await api.request(
        'POST',
        '/ask/conversations/a/messages',
        body: {'id': 'same-id'},
      );
      expect(ids, ['same-id', 'same-id']);
      api.close();
    },
  );
  test('logout during refresh cannot restore credentials', () async {
    final gate = Completer<void>();
    final vault = MemoryVault();
    final api = TypefluxApi(
      origin: Uri.parse('https://example.com'),
      vault: vault,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/logout')) return ok({});
        await gate.future;
        return ok({
          'access_token': 'new',
          'refresh_token': 'next',
          'expires_at': 9999999999,
        });
      }),
    )..session = const Session('old', 'refresh', 0);
    final refresh = api.refresh();
    final expectation = expectLater(refresh, throwsA(isA<ApiError>()));
    await api.logout();
    gate.complete();
    await expectation;
    expect(api.session, isNull);
    expect(await vault.read(api.sessionKey), isNull);
    api.close();
  });
  test('HTML gateway errors become safe structured failures', () {
    expect(
      () => TypefluxApi.decodeResponse(
        http.Response('<html>bad gateway</html>', 502),
      ),
      throwsA(
        isA<ApiError>().having((e) => e.code, 'code', 'INVALID_RESPONSE'),
      ),
    );
  });
}
