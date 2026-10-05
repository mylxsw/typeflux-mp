import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:typeflux_app/chat/chat_controller.dart';
import 'package:typeflux_app/chat/conversation.dart';
import 'package:typeflux_app/core/api.dart';
import 'package:typeflux_app/core/session.dart';

import 'support/fakes.dart';

http.Response reply(Object? data) =>
    http.Response(jsonEncode({'code': 'OK', 'data': data}), 200);
http.Response conflict() => http.Response('{"code":"ASK_CONFLICT"}', 409);
const catalog = <Map<String, dynamic>>[
  {
    'id': 'default',
    'name': 'Fixture model',
    'capabilities': {'reasoning': true},
    'reasoning_efforts': ['low', 'high'],
  },
];

Map<String, dynamic> snapshot({
  bool active = true,
  List<Map<String, dynamic>> messages = const [],
  List<Map<String, dynamic>> queued = const [],
}) => {
  'id': 'conversation',
  'revision': 2,
  'title': 'Fixture conversation',
  'model_ref': 'cloud:default',
  'messages': messages,
  'steering': queued,
  'run': {
    'id': 'run',
    'status': active ? 'running' : 'completed',
    'model_ref': 'cloud:default',
    'reasoning_effort': 'high',
  },
};

Map<String, dynamic> queuedMessage(String id, [String text = 'follow up']) => {
  'id': id,
  'role': 'user',
  'text': text,
  'steered': true,
  'model_ref': 'cloud:default',
  'reasoning_effort': 'high',
};

class FailingTransitionCache extends MemoryCache {
  int writes = 0;
  @override
  Future<void> write(String scope, Map<String, dynamic> value) async {
    if (++writes > 2) throw StateError('disk full');
    await super.write(scope, value);
  }
}

ChatController controller(
  Future<http.Response> Function(http.Request) handle, {
  MemoryCache? cache,
}) {
  final api = TypefluxApi(
    origin: Uri.parse('https://example.com'),
    vault: MemoryVault(),
    client: MockClient(handle),
    streamClientFactory: () =>
        MockClient((_) async => http.Response('{"code":"NOT_FOUND"}', 404)),
  )..session = const Session('access', 'refresh', 9999999999);
  final chat = ChatController(api, cache ?? MemoryCache())
    ..accountId = 'owner'
    ..deviceId = 'device'
    ..models = catalog
    ..current = Conversation(snapshot());
  addTearDown(() {
    chat.dispose();
    api.close();
  });
  return chat;
}

void main() {
  test(
    'active send uses steer and persists its accepted queue receipt',
    () async {
      final cache = MemoryCache();
      Map<String, dynamic>? body;
      final chat = controller((request) async {
        expect(request.url.path.endsWith('/steer'), true);
        body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body!['run_id'], 'run');
        expect(body!['device_id'], 'device');
        expect(body, isNot(contains('tools')));
        expect(body, isNot(contains('model_ref')));
        expect(body, isNot(contains('reasoning_effort')));
        return reply(snapshot(queued: [queuedMessage(body!['id'])]));
      }, cache: cache);
      expect(await chat.send('follow up', []), true);
      expect(chat.pending, isNull);
      expect(chat.queuedMessages.single['id'], body!['id']);
      final saved = cache.values[chat.scope!]!;
      expect(saved['queued']['conversation'][0]['id'], body!['id']);
      expect(saved['pending'], isNull);
    },
  );

  test('ambiguous steer receipt is recovered from the server queue', () async {
    var calls = 0;
    String? id;
    final chat = controller((request) async {
      if (request.method == 'POST') {
        calls++;
        id = (jsonDecode(request.body) as Map)['id'];
        throw http.ClientException('connection lost after acceptance');
      }
      return reply(snapshot(queued: [queuedMessage(id!)]));
    });
    await chat.send('follow up', []);
    expect(calls, 1);
    expect(chat.pending, isNull);
    expect(chat.queuedMessages.single['id'], id);
    await chat.retryPending();
    expect(calls, 1);
  });

  test(
    'explicit ended-run conflict becomes a normal send with the same ID',
    () async {
      final cache = MemoryCache();
      final requests = <Map<String, dynamic>>[];
      final routes = <String>[];
      late final ChatController chat;
      chat = controller((request) async {
        if (request.method == 'GET') return reply(snapshot(active: false));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add(body);
        routes.add(request.url.pathSegments.last);
        if (routes.last == 'steer') return conflict();
        expect(cache.values[chat.scope!]!['pending']['request'], body);
        expect(body['model_ref'], 'cloud:default');
        expect(body['reasoning_effort'], 'high');
        expect(body['tools'], isEmpty);
        return reply(snapshot(messages: [queuedMessage(body['id'])]));
      }, cache: cache);
      await chat.send('follow up', []);
      expect(routes, ['steer', 'messages']);
      expect(requests[0]['id'], requests[1]['id']);
      expect(chat.pending, isNull);
      expect(chat.queuedMessages, isEmpty);
    },
  );

  test(
    'an accepted steer is never resent as a new turn after conflict',
    () async {
      var posts = 0;
      String? id;
      final chat = controller((request) async {
        if (request.method == 'POST') {
          posts++;
          id = (jsonDecode(request.body) as Map)['id'];
          return conflict();
        }
        return reply(snapshot(active: false, queued: [queuedMessage(id!)]));
      });
      await chat.send('follow up', []);
      expect(posts, 1);
      expect(chat.pending, isNull);
      expect(chat.queuedMessages.single['id'], id);
    },
  );

  test(
    'failed conflict refresh keeps the original steer for explicit retry',
    () async {
      var posts = 0;
      final chat = controller((request) async {
        if (request.method == 'POST') {
          posts++;
          return conflict();
        }
        throw http.ClientException('offline');
      });
      await chat.send('follow up', []);
      expect(posts, 1);
      expect(chat.pending!['action'], 'steer');
      expect(chat.pending!['request']['run_id'], 'run');
      expect(chat.busy, false);
    },
  );

  test(
    'recovering queued turns retains other items cleared by server',
    () async {
      final cache = MemoryCache();
      var posts = 0;
      final chat = controller((request) async {
        if (request.method == 'GET') {
          return reply(
            snapshot(
              active: false,
              queued: [queuedMessage('one'), queuedMessage('two')],
            ),
          );
        }
        posts++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['id'], 'one');
        return reply(snapshot(messages: [queuedMessage('one')]));
      }, cache: cache);
      await chat.select('conversation');
      expect(chat.queuedMessages.map((m) => m['id']), ['one', 'two']);
      expect(await chat.send('new unrelated draft', []), false);
      expect(chat.error, 'QUEUED_MESSAGE_NEEDS_RETRY');
      expect(posts, 0);
      await chat.retryQueuedMessage('one');
      expect(posts, 1);
      expect(chat.queuedMessages.map((m) => m['id']), ['two']);
      expect(
        cache.values[chat.scope!]!['queued']['conversation'][0]['id'],
        'two',
      );

      // A process restart must retain the second item even though the server
      // cleared the original steering queue while starting the first turn.
      final restored = controller((request) async {
        if (request.url.path.endsWith('/me')) return reply({'id': 'owner'});
        if (request.url.path.endsWith('/models')) return reply(catalog);
        if (request.url.path.endsWith('/conversations')) {
          return reply([
            {'id': 'conversation', 'title': 'Fixture conversation'},
          ]);
        }
        return reply(snapshot(messages: [queuedMessage('one')]));
      }, cache: cache);
      await restored.initialize();
      expect(restored.queuedMessages.map((m) => m['id']), ['two']);
    },
  );

  test(
    'failed persistence of fallback blocks billing on repeated retries',
    () async {
      var posts = 0;
      final chat = controller((request) async {
        if (request.method == 'GET') return reply(snapshot(active: false));
        posts++;
        expect(request.url.path.endsWith('/steer'), true);
        return conflict();
      }, cache: FailingTransitionCache());
      await chat.send('follow up', []);
      expect(posts, 1);
      expect(chat.error, 'CACHE_FAILED');
      expect(chat.pending, isNotNull);
      await chat.retryPending();
      expect(posts, 1);
      expect(chat.error, 'CACHE_FAILED');
      expect(chat.busy, false);
    },
  );

  test(
    'ended local-model steer is archived without starting a mobile run',
    () async {
      final cache = MemoryCache();
      final localSnapshot = snapshot(active: false)
        ..['model_ref'] = 'custom:original-mac';
      (localSnapshot['run'] as Map)['model_ref'] = 'custom:original-mac';
      final routes = <String>[];
      final chat = controller((request) async {
        if (request.method == 'GET') return reply(localSnapshot);
        routes.add(request.url.pathSegments.last);
        if (request.url.path.endsWith('/messages')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['text'], 'a new cloud question');
          expect(body['model_ref'], 'cloud:default');
          return reply(
            snapshot(
              messages: [
                {'role': 'user', ...body},
              ],
            ),
          );
        }
        return conflict();
      }, cache: cache);
      chat.current = Conversation({
        ...localSnapshot,
        'run': <String, dynamic>{
          ...localSnapshot['run'] as Map<String, dynamic>,
          'status': 'running',
        },
      });
      final attachment = {
        'kind': 'text',
        'name': 'note.txt',
        'text': 'saved file',
      };
      expect(await chat.send('keep this draft', [attachment]), true);
      expect(routes, ['steer']);
      expect(chat.error, 'QUEUED_MESSAGE_NEEDS_DEVICE');
      expect(chat.pending, isNull);
      expect(chat.busy, false);
      final recovered = chat.queuedMessages.single;
      expect(recovered['model_ref'], 'custom:original-mac');
      expect(recovered['text'], 'keep this draft');
      expect(recovered['attachments'], [attachment]);
      expect(recovered['local_only'], true);
      final saved = cache.values[chat.scope!]!;
      expect(saved['pending'], isNull);
      expect(saved['queued']['conversation'][0]['id'], recovered['id']);
      await chat.retryQueuedMessage(recovered['id']);
      expect(routes, ['steer']);
      expect(chat.error, 'QUEUED_MESSAGE_NEEDS_DEVICE');
      expect(chat.changeModel('cloud:default'), true);
      expect(await chat.send('a new cloud question', []), true);
      expect(routes, ['steer', 'messages']);
      expect(chat.queuedMessages.single['id'], recovered['id']);
      chat.newConversation();
      expect(chat.current!.id, isNot('conversation'));
      expect(chat.loading, false);

      final restored = controller((request) async {
        if (request.url.path.endsWith('/me')) return reply({'id': 'owner'});
        if (request.url.path.endsWith('/models')) return reply(catalog);
        if (request.url.path.endsWith('/conversations')) {
          return reply([
            {'id': 'conversation', 'title': 'Fixture conversation'},
          ]);
        }
        return reply(localSnapshot);
      }, cache: cache);
      await restored.initialize();
      expect(restored.queuedMessages.single['id'], recovered['id']);
      expect(restored.pending, isNull);
    },
  );

  test(
    'failed local-model draft archive retains its durable pending request',
    () async {
      final localSnapshot = snapshot(active: false);
      (localSnapshot['run'] as Map)['model_ref'] = 'custom:original-mac';
      final routes = <String>[];
      final chat = controller((request) async {
        if (request.method == 'GET') return reply(localSnapshot);
        routes.add(request.url.pathSegments.last);
        return conflict();
      }, cache: FailingTransitionCache());
      chat.current = Conversation({
        ...localSnapshot,
        'run': <String, dynamic>{
          ...localSnapshot['run'] as Map<String, dynamic>,
          'status': 'running',
        },
      });
      await chat.send('keep this draft', []);
      expect(routes, ['steer']);
      expect(chat.error, 'CACHE_FAILED');
      expect(chat.pending!['action'], 'steer');
      expect(chat.pending!['request']['text'], 'keep this draft');
      expect(chat.busy, false);
    },
  );
}
