import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:typeflux_app/chat/chat_controller.dart';
import 'package:typeflux_app/chat/conversation.dart';
import 'package:typeflux_app/core/api.dart';
import 'package:typeflux_app/core/session.dart';

import 'support/fakes.dart';

http.Response ok(Object? data) =>
    http.Response(jsonEncode({'code': 'OK', 'data': data}), 200);
TypefluxApi makeApi(Future<http.Response> Function(http.Request) handler) =>
    TypefluxApi(
      origin: Uri.parse('https://example.com'),
      vault: MemoryVault(),
      client: MockClient(handler),
      streamClientFactory: () =>
          MockClient((_) async => http.Response('{"code":"NOT_FOUND"}', 404)),
    )..session = const Session('access', 'refresh', 9999999999);

class FailingCache extends MemoryCache {
  @override
  Future<void> write(String scope, Map<String, dynamic> value) async =>
      throw StateError('disk full');
}

void main() {
  final reasoningCatalog = <Map<String, dynamic>>[
    {
      'id': 'default',
      'name': 'Default model',
      'capabilities': {'reasoning': true},
      'reasoning_efforts': ['low', 'medium', 'high', 'xhigh', 'max'],
    },
    {
      'id': 'limited',
      'name': 'Limited model',
      'capabilities': {'reasoning': true},
      'reasoning_efforts': ['low', 'high'],
    },
    {'id': 'fast', 'name': 'Fast model'},
  ];
  test('changing models preserves automatic or selects nearest effort', () {
    final api = makeApi((_) async => ok({}));
    final chat = ChatController(api, MemoryCache())..models = reasoningCatalog;
    chat.newConversation();
    expect(chat.selectedModel!.isDefault, true);
    chat.setReasoningEffort('max');
    expect(chat.reasoningEffort, 'max');
    expect(chat.changeModel('cloud:limited'), true);
    expect(chat.reasoningEffort, 'high');
    expect(chat.changeModel('custom:local'), false);
    expect(chat.modelRef, 'cloud:limited');
    chat.setReasoningEffort('');
    chat.changeModel('cloud:default');
    expect(chat.reasoningEffort, '');
    chat.setReasoningEffort('high');
    chat.changeModel('cloud:fast');
    expect(chat.reasoningEffort, '');
    chat.current = Conversation({
      'id': 'active',
      'run': {'status': 'running'},
    });
    expect(chat.changeModel('cloud:default'), false);
    chat.dispose();
    api.close();
  });

  test(
    'send retries preserve exact reasoning choice with durable ID',
    () async {
      final requests = <Map<String, dynamic>>[];
      late final ChatController chat;
      final api = makeApi((request) async {
        if (request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          requests.add(body);
          if (requests.length == 1) throw http.ClientException('offline');
          return ok({'id': chat.current!.id, 'revision': 1, 'messages': []});
        }
        return http.Response('{"code":"ASK_NOT_FOUND"}', 404);
      });
      chat = ChatController(api, MemoryCache())
        ..models = reasoningCatalog
        ..accountId = 'owner'
        ..deviceId = 'device';
      chat.newConversation();
      chat.setReasoningEffort('max');
      await chat.send('question', []);
      chat.setReasoningEffort('low');
      expect(chat.reasoningEffort, 'max');
      expect(chat.changeModel('cloud:limited'), false);
      await chat.retryPending();
      expect(requests, hasLength(2));
      expect(requests[0], requests[1]);
      expect(requests[1]['reasoning_effort'], 'max');
      chat.dispose();
      api.close();
    },
  );

  test('history selection restores and normalizes stored run choice', () async {
    final api = makeApi(
      (request) async => ok({
        'id': 'history',
        'model_ref': 'cloud:limited',
        'revision': 1,
        'messages': [],
        'run': {'id': 'run', 'status': 'completed', 'reasoning_effort': 'max'},
      }),
    );
    final chat = ChatController(api, MemoryCache())
      ..accountId = 'owner'
      ..models = reasoningCatalog;
    await chat.select('history');
    expect(chat.modelRef, 'cloud:limited');
    expect(chat.reasoningEffort, 'high');
    chat.newConversation();
    expect(chat.modelRef, '');
    expect(chat.reasoningEffort, '');
    chat.dispose();
    api.close();
  });

  test('regenerate follows server original-effort contract', () async {
    Map<String, dynamic>? sent;
    final api = makeApi((request) async {
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return ok({
        'id': 'history',
        'model_ref': 'cloud:limited',
        'revision': 2,
        'messages': [],
        'run': {
          'id': 'new-run',
          'status': 'running',
          'reasoning_effort': 'low',
        },
      });
    });
    final chat = ChatController(api, MemoryCache())
      ..accountId = 'owner'
      ..models = reasoningCatalog
      ..modelRef = 'cloud:limited'
      ..reasoningEffort = 'high'
      ..current = Conversation({
        'id': 'history',
        'revision': 1,
        'messages': [
          {'id': 'prompt', 'role': 'user', 'reasoning_effort': 'low'},
          {'id': 'answer', 'role': 'assistant'},
        ],
        'run': {'id': 'run', 'status': 'completed'},
      });
    await chat.runAction('regenerate');
    expect(sent!['message_id'], 'answer');
    expect(sent!['model_ref'], 'cloud:limited');
    expect(sent, isNot(contains('reasoning_effort')));
    expect(chat.reasoningEffort, 'low');
    chat.dispose();
    api.close();
  });

  test('profile is read from me and cleared on logout', () async {
    final api = makeApi((request) async {
      if (request.url.path.endsWith('/me')) {
        return ok({
          'id': 'owner',
          'name': ' Example ',
          'email': 'user@example.com',
        });
      }
      if (request.url.path.endsWith('/models')) return ok(reasoningCatalog);
      if (request.url.path.endsWith('/logout')) return ok({});
      return ok([]);
    });
    final chat = ChatController(api, MemoryCache());
    await chat.initialize();
    expect(chat.accountName, 'Example');
    expect(chat.accountEmail, 'user@example.com');
    await chat.logout();
    expect(chat.accountName, isNull);
    expect(chat.accountEmail, isNull);
    chat.dispose();
    api.close();
  });

  test(
    'password change notifies listeners when refresh invalidates the session',
    () async {
      final requests = <String>[];
      final api = makeApi((request) async {
        requests.add(request.url.path);
        return http.Response('{"code":"AUTH_REFRESH_TOKEN_INVALID"}', 401);
      })..session = const Session('expired-access', 'revoked-refresh', 1);
      await api.vault.write(api.sessionKey, api.session!.encode());
      final chat = ChatController(api, MemoryCache());
      addTearDown(chat.dispose);
      addTearDown(api.close);
      final signedInStates = <bool>[];
      chat.addListener(() => signedInStates.add(api.signedIn));

      await expectLater(
        chat.changePassword(oldPassword: 'OldPass1', newPassword: 'NewPass2'),
        throwsA(
          isA<ApiError>().having(
            (error) => error.code,
            'code',
            'AUTH_REFRESH_TOKEN_INVALID',
          ),
        ),
      );

      expect(requests, ['/api/v1/auth/refresh']);
      expect(api.signedIn, false);
      expect(await api.vault.read(api.sessionKey), isNull);
      expect(signedInStates, [false]);
    },
  );

  test(
    'recovering an automatic draft never inherits earlier turn settings',
    () async {
      final api = makeApi((request) async {
        if (request.url.path.endsWith('/me')) return ok({'id': 'owner'});
        if (request.url.path.endsWith('/models')) return ok(reasoningCatalog);
        if (request.url.path.endsWith('/conversations')) return ok([]);
        return http.Response('{"code":"ASK_NOT_FOUND"}', 404);
      });
      final cache = MemoryCache();
      final chat = ChatController(api, cache)..accountId = 'owner';
      await cache.write(chat.scope!, {
        'list': [],
        'conversation': {
          'id': 'history',
          'revision': 1,
          'model_ref': 'cloud:limited',
          'messages': [],
          'run': {
            'id': 'old-run',
            'status': 'completed',
            'reasoning_effort': 'high',
          },
        },
        'pending': {
          'conversation_id': 'history',
          'request': {
            'id': 'pending-id',
            'device_id': 'device',
            'text': 'question',
          },
        },
      });
      await chat.initialize();
      expect(chat.pending!['request']['id'], 'pending-id');
      expect(chat.modelRef, '');
      expect(chat.reasoningEffort, '');
      chat.dispose();
      api.close();
    },
  );

  test('failed draft persistence prevents a billable send', () async {
    var calls = 0;
    final api = makeApi((request) async {
      calls++;
      return ok({});
    });
    final chat = ChatController(api, FailingCache())
      ..accountId = 'owner'
      ..deviceId = 'device';
    chat.newConversation();
    expect(await chat.send('important draft', []), false);
    expect(calls, 0);
    expect(chat.busy, false);
    expect(chat.error, 'CACHE_FAILED');
    chat.dispose();
    api.close();
  });
  test(
    'ambiguous send retries reuse durable ID and advertise no local tools',
    () async {
      final ids = <String>[];
      late final ChatController chat;
      final api = makeApi((request) async {
        if (request.method == 'POST' &&
            request.url.path.endsWith('/messages')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          ids.add(body['id']);
          expect(body['tools'], isEmpty);
          expect(body, isNot(contains('reasoning_effort')));
          if (ids.length == 1) throw http.ClientException('offline');
          return ok({
            'id': chat.current!.id,
            'revision': 2,
            'messages': [
              {'id': body['id'], 'role': 'user', 'text': body['text']},
            ],
          });
        }
        return http.Response('{"code":"ASK_NOT_FOUND"}', 404);
      });
      chat = ChatController(api, MemoryCache())
        ..accountId = 'owner'
        ..deviceId = 'device';
      chat.newConversation();
      await chat.send('hello', []);
      expect(chat.pending, isNotNull);
      await chat.retryPending();
      expect(ids.length, 2);
      expect(ids[0], ids[1]);
      expect(chat.pending, isNull);
      chat.dispose();
      api.close();
    },
  );
  test('backgrounding during send does not strand busy state', () async {
    final gate = Completer<void>();
    late final ChatController chat;
    final api = makeApi((request) async {
      await gate.future;
      return ok({'id': chat.current!.id, 'revision': 2, 'messages': []});
    });
    chat = ChatController(api, MemoryCache())
      ..accountId = 'owner'
      ..deviceId = 'device';
    chat.newConversation();
    final sending = chat.send('hello', []);
    await Future<void>.delayed(Duration.zero);
    chat.setForeground(false);
    gate.complete();
    await sending;
    expect(chat.busy, false);
    expect(chat.pending, isNull);
    chat.dispose();
    api.close();
  });
  test('late selection response cannot overwrite newer selection', () async {
    final gate = Completer<void>();
    final api = makeApi((request) async {
      final id = request.url.pathSegments.last;
      if (id == 'old') await gate.future;
      return ok({'id': id, 'revision': 1, 'messages': []});
    });
    final chat = ChatController(api, MemoryCache())..accountId = 'owner';
    final old = chat.select('old');
    await chat.select('new');
    gate.complete();
    await old;
    expect(chat.current!.id, 'new');
    chat.dispose();
    api.close();
  });
  test(
    'new conversation clears loading while an old selection is pending',
    () async {
      final gate = Completer<void>();
      final api = makeApi((request) async {
        await gate.future;
        return ok({'id': 'old', 'revision': 1, 'messages': []});
      });
      final chat = ChatController(api, MemoryCache())..accountId = 'owner';
      final selection = chat.select('old');
      expect(chat.loading, true);
      chat.newConversation();
      final newId = chat.current!.id;
      expect(newId, isNot('old'));
      expect(chat.loading, false);
      gate.complete();
      await selection;
      expect(chat.current!.id, newId);
      expect(chat.loading, false);
      chat.dispose();
      api.close();
    },
  );
  test('logout discards in-flight response and clears account cache', () async {
    final gate = Completer<void>();
    final cache = MemoryCache();
    final api = makeApi((request) async {
      if (request.url.path.endsWith('/logout')) return ok({});
      await gate.future;
      return ok({'id': 'old', 'revision': 9, 'messages': []});
    });
    final chat = ChatController(api, cache)..accountId = 'owner';
    await cache.write(chat.scope!, {'private': 'fixture'});
    final selecting = chat.select('old');
    await chat.logout();
    gate.complete();
    await selecting;
    expect(chat.current, isNull);
    expect(cache.values, isEmpty);
    chat.dispose();
    api.close();
  });
}
