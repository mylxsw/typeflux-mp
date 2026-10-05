import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/api.dart';
import '../account/account_summary.dart';
import '../core/sse.dart';
import 'cache.dart';
import 'conversation.dart';
import 'model_options.dart';

class ChatController extends ChangeNotifier {
  ChatController(this.api, this.cache);
  final TypefluxApi api;
  final ChatCache cache;
  final _uuid = const Uuid();
  List<Map<String, dynamic>> conversations = [], models = [];
  Conversation? current;
  Map<String, dynamic>? pending;
  final Map<String, List<Map<String, dynamic>>> _queued = {};
  String? error, accountId, accountName, accountEmail;
  bool? accountHasPassword;
  AccountSummary? accountSummary;
  bool accountSummaryLoading = false, historyRefreshing = false;
  String? accountSummaryError;
  String deviceId = '', modelRef = '', reasoningEffort = '';
  bool busy = false, loading = false, reconnecting = false, hasMore = true;
  bool _disposed = false, _foreground = true;
  int _epoch = 0, _accountEpoch = 0, _attempt = 0;
  EventConnection? _connection;
  StreamSubscription<ServerEvent>? _subscription;
  Timer? _retry;
  String? get scope =>
      accountId == null ? null : '${api.origin.origin}:$accountId';
  List<ModelOption> get modelOptions => models
      .where((model) => model['id'] is String && model['id'] != '')
      .map(ModelOption.fromJson)
      .toList();
  ModelOption? get selectedModel {
    final reference = modelRef.isEmpty ? 'cloud:default' : modelRef;
    return modelOptions.where((m) => m.reference == reference).firstOrNull;
  }

  /// Steering and recovered drafts stay available until the transcript confirms them.
  /// Starting another run clears the server's old queue, so keep a local copy.
  List<Map<String, dynamic>> get queuedMessages {
    final item = current;
    if (item == null) return const [];
    final delivered = item.messages.map((message) => message['id']).toSet();
    final waiting = <String, Map<String, dynamic>>{};
    for (final message in [
      ...?_queued[item.id],
      ...(item.json['steering'] as List? ?? const [])
          .whereType<Map<String, dynamic>>(),
    ]) {
      final id = message['id'];
      if (id is String && !delivered.contains(id)) waiting[id] = message;
    }
    return waiting.values.toList();
  }

  Map<String, dynamic> _cacheSnapshot() {
    final item = current;
    if (item != null) {
      final waiting = queuedMessages;
      if (waiting.isEmpty) {
        _queued.remove(item.id);
      } else {
        _queued[item.id] = waiting;
      }
    }
    return {
      'list': conversations,
      'conversation': current?.json,
      'pending': pending,
      'queued': {
        for (final entry in _queued.entries) entry.key: List.of(entry.value),
      },
    };
  }

  Future<void> _persistPending() async {
    final key = scope;
    if (key == null) throw const ApiError('AUTH_REQUIRED', 401);
    await cache.write(key, _cacheSnapshot());
  }

  bool changeModel(String reference) {
    if (busy || loading || current?.active == true || pending != null) {
      return false;
    }
    final normalized = reference.isEmpty ? 'cloud:default' : reference;
    final model = modelOptions
        .where((item) => item.reference == normalized)
        .firstOrNull;
    if (model == null) return false;
    modelRef = model.reference;
    reasoningEffort = nearestReasoningEffort(
      reasoningEffort,
      model.reasoningEfforts,
    );
    notifyListeners();
    return true;
  }

  void setReasoningEffort(String value) {
    if (busy || loading || current?.active == true || pending != null) return;
    reasoningEffort = nearestReasoningEffort(
      value,
      selectedModel?.reasoningEfforts ?? const [],
    );
    notifyListeners();
  }

  void _restoreSelection({Map<String, dynamic>? request}) {
    final item = current;
    final previousModel =
        (request != null
                ? request['model_ref']
                : item?.json['model_ref'] ?? item?.run?['model_ref'])
            as String? ??
        '';
    modelRef = previousModel.startsWith('cloud:') ? previousModel : '';
    final lastPrompt = item?.messages
        .where((message) => message['role'] == 'user')
        .lastOrNull;
    final previousEffort =
        (request != null
                ? request['reasoning_effort']
                : item?.run?['reasoning_effort'] ??
                      lastPrompt?['reasoning_effort'])
            as String? ??
        '';
    reasoningEffort = nearestReasoningEffort(
      previousEffort,
      selectedModel?.reasoningEfforts ?? const [],
    );
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<void> initialize() async {
    final generation = ++_accountEpoch;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final me = await api.request('GET', '/me') as Map<String, dynamic>;
      if (_disposed || generation != _accountEpoch) return;
      accountId = me['id'] as String;
      accountName = (me['name'] as String?)?.trim();
      accountEmail = (me['email'] as String?)?.trim();
      final providers = me['providers'];
      accountHasPassword = me['provider'] == 'password'
          ? true
          : providers is List && providers.isNotEmpty
          ? providers.contains('password')
          : null;
      deviceId = await api.vault.read('device-id') ?? _uuid.v4();
      await api.vault.write('device-id', deviceId);
      final saved = await cache.read(scope!);
      if (_disposed || generation != _accountEpoch) return;
      _queued.clear();
      if (saved != null) {
        final savedQueue = saved['queued'];
        if (savedQueue is Map) {
          for (final entry in savedQueue.entries) {
            if (entry.key is String && entry.value is List) {
              _queued[entry.key as String] = (entry.value as List)
                  .whereType<Map<String, dynamic>>()
                  .toList();
            }
          }
        }
        conversations = (saved['list'] as List? ?? [])
            .cast<Map<String, dynamic>>();
        if (saved['conversation'] is Map<String, dynamic>) {
          current = Conversation(saved['conversation']);
        }
        pending = saved['pending'] as Map<String, dynamic>?;
        notifyListeners();
      }
      final results = await Future.wait([
        api.request('GET', '/ask/conversations'),
        api.request('GET', '/ask/conversations/models'),
      ]);
      if (_disposed || generation != _accountEpoch) return;
      conversations = (results[0] as List? ?? []).cast<Map<String, dynamic>>();
      models = (results[1] as List? ?? []).cast<Map<String, dynamic>>();
      hasMore = conversations.length == 50;
      if (pending != null) {
        current = current?.id == pending!['conversation_id']
            ? current
            : Conversation({
                'id': pending!['conversation_id'],
                'title': '',
                'revision': 0,
                'messages': [],
              });
        _restoreSelection(
          request: pending!['fallback_request'] ?? pending!['request'],
        );
        await _recoverPending();
      } else if (current != null &&
          conversations.any((c) => c['id'] == current!.id)) {
        await select(current!.id);
      } else {
        newConversation();
      }
    } catch (e) {
      if (generation == _accountEpoch) error = errorCode(e);
    } finally {
      if (generation == _accountEpoch) {
        loading = false;
        notifyListeners();
      }
    }
  }

  static String errorCode(Object e) => e is ApiError ? e.code : 'NETWORK_ERROR';
  Future<void> _save() async {
    final key = scope;
    if (key == null) return;
    try {
      await cache.write(key, _cacheSnapshot());
    } catch (_) {
      error = 'CACHE_FAILED';
      notifyListeners();
    }
  }

  void _stopObserving() {
    _epoch++;
    _retry?.cancel();
    _retry = null;
    _connection?.close();
    _connection = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  void newConversation() {
    if (busy || pending != null) return;
    _stopObserving();
    // The old selection's finally block is now stale and cannot clear this.
    loading = false;
    current = Conversation({
      'id': _uuid.v4(),
      'title': '',
      'revision': 0,
      'messages': [],
    });
    error = null;
    reconnecting = false;
    modelRef = '';
    reasoningEffort = '';
    notifyListeners();
  }

  Future<void> select(String id) async {
    if (busy || pending != null) return;
    _stopObserving();
    final epoch = _epoch;
    loading = true;
    error = null;
    reconnecting = false;
    notifyListeners();
    try {
      final result = await api.request('GET', '/ask/conversations/$id');
      if (_disposed || epoch != _epoch) return;
      current = Conversation(result as Map<String, dynamic>);
      _restoreSelection();
      await _save();
      if (epoch == _epoch) unawaited(_observe(epoch));
    } catch (e) {
      if (epoch == _epoch) error = errorCode(e);
    } finally {
      if (epoch == _epoch) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore() async {
    if (loading || historyRefreshing || !hasMore) return;
    final generation = _accountEpoch;
    loading = true;
    notifyListeners();
    try {
      final data =
          await api.request(
            'GET',
            '/ask/conversations?offset=${conversations.length}',
          ) as List? ??
          [];
      if (generation != _accountEpoch || _disposed) return;
      hasMore = data.length == 50;
      final ids = conversations.map((e) => e['id']).toSet();
      conversations.addAll(
        data.cast<Map<String, dynamic>>().where((e) => ids.add(e['id'])),
      );
    } catch (e) {
      error = errorCode(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refreshAccountSummary() async {
    if (accountSummaryLoading || accountId == null || _disposed) return;
    final generation = _accountEpoch;
    accountSummaryLoading = true;
    accountSummaryError = null;
    notifyListeners();
    try {
      final values = await Future.wait([
        api.request('GET', '/billing/subscription'),
        api.request('GET', '/usage/current-period/stats'),
      ]);
      if (_disposed || generation != _accountEpoch) return;
      accountSummary = AccountSummary.fromJson(
        Map<String, dynamic>.from(values[0] as Map),
        Map<String, dynamic>.from(values[1] as Map),
      );
    } catch (e) {
      if (!_disposed && generation == _accountEpoch) {
        accountSummaryError = errorCode(e);
      }
    } finally {
      if (!_disposed && generation == _accountEpoch) {
        accountSummaryLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshHistory() async {
    if (historyRefreshing || loading || busy || _disposed) return;
    final generation = _accountEpoch;
    historyRefreshing = true;
    notifyListeners();
    try {
      final result = await api.request('GET', '/ask/conversations') as List;
      if (_disposed || generation != _accountEpoch) return;
      conversations = result.cast<Map<String, dynamic>>();
      hasMore = conversations.length == 50;
      error = null;
      await _save();
    } catch (e) {
      if (!_disposed && generation == _accountEpoch) error = errorCode(e);
    } finally {
      if (!_disposed && generation == _accountEpoch) {
        historyRefreshing = false;
        notifyListeners();
      }
    }
  }

  Future<bool> deleteConversation(String id) async {
    if (busy ||
        loading ||
        historyRefreshing ||
        pending != null ||
        _disposed ||
        (current?.id == id && current?.active == true)) {
      return false;
    }
    final generation = _accountEpoch;
    busy = true;
    notifyListeners();
    try {
      await api.request('DELETE', '/ask/conversations/$id');
      if (_disposed || generation != _accountEpoch) return false;
      conversations.removeWhere((item) => item['id'] == id);
      _queued.remove(id);
      busy = false;
      if (current?.id == id) newConversation();
      error = null;
      await _save();
      return true;
    } catch (e) {
      if (!_disposed && generation == _accountEpoch) error = errorCode(e);
      return false;
    } finally {
      if (!_disposed && generation == _accountEpoch) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<bool> send(String text, List<Map<String, dynamic>> attachments) async {
    if (busy ||
        loading ||
        pending != null ||
        (text.trim().isEmpty && attachments.isEmpty)) {
      return false;
    }
    if (current?.active != true &&
        queuedMessages.any((message) => message['local_only'] != true)) {
      error = 'QUEUED_MESSAGE_NEEDS_RETRY';
      notifyListeners();
      return false;
    }
    current ??= Conversation({
      'id': _uuid.v4(),
      'title': '',
      'revision': 0,
      'messages': [],
    });
    final requestedEffort = nearestReasoningEffort(
      reasoningEffort,
      selectedModel?.reasoningEfforts ?? const [],
    );
    final active = current!.active;
    final messageId = _uuid.v4();
    final request = <String, dynamic>{
      'id': messageId,
      'device_id': deviceId,
      'text': text.trim(),
      'tools': <dynamic>[],
      'locale': PlatformDispatcher.instance.locale.toLanguageTag(),
      if (modelRef.isNotEmpty) 'model_ref': modelRef,
      if (requestedEffort.isNotEmpty) 'reasoning_effort': requestedEffort,
      if (attachments.isNotEmpty) 'attachments': attachments,
    };
    if (active) {
      final activeModel =
          current!.run?['model_ref'] ?? current!.json['model_ref'];
      final activeEffort = current!.run?['reasoning_effort'];
      request.remove('model_ref');
      request.remove('reasoning_effort');
      if (activeModel is String && activeModel.isNotEmpty) {
        request['model_ref'] = activeModel;
      }
      if (activeEffort is String && activeEffort.isNotEmpty) {
        request['reasoning_effort'] = activeEffort;
      }
    }
    pending = {
      'conversation_id': current!.id,
      if (active) 'action': 'steer',
      if (active) 'fallback_request': request,
      'request': active
          ? {
              'id': messageId,
              'run_id': current!.run!['id'],
              'device_id': deviceId,
              'text': text.trim(),
              if (attachments.isNotEmpty) 'attachments': attachments,
            }
          : request,
    };
    // Persist the message ID before attempting a potentially billable request.
    busy = true;
    notifyListeners();
    try {
      await _persistPending();
    } catch (_) {
      pending = null;
      busy = false;
      error = 'CACHE_FAILED';
      notifyListeners();
      return false;
    }
    busy = false;
    await retryPending();
    return true;
  }

  Future<void> retryQueuedMessage(String id) async {
    if (busy || loading || pending != null || current?.active == true) return;
    final message = queuedMessages.where((m) => m['id'] == id).firstOrNull;
    if (message == null) return;
    final ref = message['model_ref'] as String? ?? '';
    if (ref.isNotEmpty && !ref.startsWith('cloud:')) {
      error = 'QUEUED_MESSAGE_NEEDS_DEVICE';
      notifyListeners();
      return;
    }
    pending = {
      'conversation_id': current!.id,
      'request': {
        'id': id,
        'device_id': deviceId,
        'text': message['text'] as String? ?? '',
        'tools': <dynamic>[],
        'locale': PlatformDispatcher.instance.locale.toLanguageTag(),
        for (final field in [
          'model_ref',
          'reasoning_effort',
          'selection',
          'source',
          'image',
          'references',
          'attachments',
          'skills',
          'mcp_servers',
        ])
          if (message[field] != null) field: message[field],
      },
    };
    busy = true;
    notifyListeners();
    try {
      await _persistPending();
    } catch (_) {
      pending = null;
      error = 'CACHE_FAILED';
      busy = false;
      notifyListeners();
      return;
    }
    busy = false;
    await retryPending();
  }

  Future<void> retryPending() async {
    if (pending == null || busy) return;
    _stopObserving();
    final epoch = _epoch;
    var draft = pending!;
    busy = true;
    error = null;
    notifyListeners();
    try {
      try {
        await _persistPending();
      } catch (_) {
        error = 'CACHE_FAILED';
        return;
      }
      if (_disposed || epoch != _epoch) return;
      while (true) {
        final steering = draft['action'] == 'steer';
        try {
          final response = await api.request(
            'POST',
            '/ask/conversations/${draft['conversation_id']}/${steering ? 'steer' : 'messages'}',
            body: draft['request'],
          );
          if (_disposed || epoch != _epoch) return;
          current = Conversation(response as Map<String, dynamic>);
          _restoreSelection();
          pending = null;
          _upsert();
          await _save();
          if (epoch == _epoch) unawaited(_observe(epoch));
          break;
        } catch (e) {
          if (_disposed || epoch != _epoch) return;
          error = errorCode(e);
          // Both delivered messages and accepted-but-unread steering are receipts.
          final refreshed = await _recoverPending();
          if (_disposed || epoch != _epoch) return;
          if (steering &&
              e is ApiError &&
              e.status == 409 &&
              refreshed &&
              pending != null &&
              current?.active != true &&
              draft['fallback_request'] is Map<String, dynamic>) {
            final fallback = draft['fallback_request'] as Map<String, dynamic>;
            final reference = fallback['model_ref'] as String? ?? '';
            if (reference.isNotEmpty && !reference.startsWith('cloud:')) {
              // This client cannot execute the original Mac's local model. Save
              // the rejected draft locally rather than creating a stranded run.
              // There is no server API for synchronizing an unsubmitted draft.
              final id = draft['conversation_id'] as String;
              final previousQueue = _queued[id];
              _queued[id] = [
                ...queuedMessages.where((item) => item['id'] != fallback['id']),
                {...fallback, 'role': 'user', 'local_only': true},
              ];
              pending = null;
              _upsert();
              try {
                await _persistPending();
              } catch (_) {
                if (_disposed || epoch != _epoch) return;
                pending = draft;
                if (previousQueue == null) {
                  _queued.remove(id);
                } else {
                  _queued[id] = previousQueue;
                }
                error = 'CACHE_FAILED';
                break;
              }
              if (_disposed || epoch != _epoch) return;
              error = 'QUEUED_MESSAGE_NEEDS_DEVICE';
              break;
            }
            // The run ended before acceptance. Persist the route change before
            // sending the same durable ID as a normal turn; never invent a new ID.
            draft = {
              'conversation_id': draft['conversation_id'],
              'request': draft['fallback_request'],
            };
            pending = draft;
            try {
              await _persistPending();
            } catch (_) {
              error = 'CACHE_FAILED';
              break;
            }
            error = null;
            continue;
          }
          break;
        }
      }
    } finally {
      if (epoch == _epoch) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<bool> _recoverPending() async {
    final draft = pending;
    if (draft == null) return true;
    final epoch = _epoch;
    try {
      final response = await api.request(
        'GET',
        '/ask/conversations/${draft['conversation_id']}',
      );
      if (_disposed || epoch != _epoch) return false;
      current = Conversation(response as Map<String, dynamic>);
      final receipts = [
        ...current!.messages,
        if (draft['action'] == 'steer')
          ...(current!.json['steering'] as List? ?? const [])
              .whereType<Map<String, dynamic>>(),
      ];
      if (receipts.any((m) => m['id'] == draft['request']['id'])) {
        pending = null;
        error = null;
        _upsert();
        await _save();
        if (epoch == _epoch) unawaited(_observe(epoch));
      }
      return true;
    } catch (_) {
      /* Keep the original ID and editable text for explicit retry. */
      return false;
    }
  }

  void _upsert() {
    final item = current;
    if (item == null) return;
    conversations.removeWhere((c) => c['id'] == item.id);
    conversations.insert(0, {
      'id': item.id,
      'title': item.title,
      'updated_at': item.json['updated_at'],
    });
  }

  Future<void> _observe(int epoch) async {
    if (_disposed || !_foreground || epoch != _epoch || current == null) return;
    try {
      final connection = await api.events(current!.id);
      if (_disposed || !_foreground || epoch != _epoch) {
        connection.close();
        return;
      }
      _connection = connection;
      reconnecting = false;
      _attempt = 0;
      notifyListeners();
      _subscription = connection.events.listen(
        (event) {
          if (epoch != _epoch || _disposed) return;
          if (event.type == 'unavailable') {
            error = 'CONVERSATION_UNAVAILABLE';
            _stopObserving();
            notifyListeners();
            return;
          }
          current = current!.apply(event);
          if (event.type == 'snapshot') {
            _upsert();
            unawaited(_save());
          }
          notifyListeners();
        },
        onError: (Object e) {
          if (epoch != _epoch) return;
          error = errorCode(e);
          _schedule(epoch);
        },
        onDone: () {
          if (epoch == _epoch) _schedule(epoch);
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (epoch != _epoch) return;
      error = errorCode(e);
      if (e is ApiError && [401, 403, 404].contains(e.status)) {
        notifyListeners();
        return;
      }
      _schedule(epoch);
    }
  }

  void _schedule(int epoch) {
    if (_disposed || !_foreground || epoch != _epoch) return;
    _connection?.close();
    _connection = null;
    reconnecting = true;
    notifyListeners();
    _retry?.cancel();
    _retry = Timer(
      Duration(seconds: 1 << (_attempt++).clamp(0, 4)),
      () => _observe(epoch),
    );
  }

  void setForeground(bool value) {
    _foreground = value;
    if (busy || loading) return;
    _stopObserving();
    if (value && current != null && current!.revision > 0) {
      unawaited(_observe(_epoch));
    }
  }

  Future<void> runAction(String action) async {
    final item = current;
    if (item?.run == null || busy || pending != null) return;
    final epoch = _epoch;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final body = <String, dynamic>{'run_id': item!.run!['id']};
      if (action != 'cancel') {
        body['device_id'] = deviceId;
        body['tools'] = <dynamic>[];
      }
      if (action == 'regenerate') {
        final message = item.messages.lastWhere(
          (m) => m['role'] == 'assistant',
          orElse: () => {},
        );
        if (message.isEmpty) return;
        body['message_id'] = message['id'];
        body['model_ref'] = modelRef.isEmpty ? 'cloud:default' : modelRef;
      }
      final result = await api.request(
        'POST',
        '/ask/conversations/${item.id}/$action',
        body: body,
      );
      if (epoch != _epoch || _disposed) return;
      current = current!.apply(ServerEvent('snapshot', result));
      if (action == 'regenerate') _restoreSelection();
      await _save();
    } catch (e) {
      if (epoch == _epoch) error = errorCode(e);
    } finally {
      if (epoch == _epoch) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> deleteCurrent() async {
    final item = current;
    if (item == null || item.active || busy || pending != null) return;
    busy = true;
    notifyListeners();
    final epoch = _epoch;
    try {
      await api.request('DELETE', '/ask/conversations/${item.id}');
      if (epoch != _epoch || _disposed) return;
      conversations.removeWhere((c) => c['id'] == item.id);
      _queued.remove(item.id);
      busy = false;
      newConversation();
      await _save();
    } catch (e) {
      error = errorCode(e);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Account mutations can invalidate the session outside the chat request paths.
  Future<void> changePassword({
    String? oldPassword,
    required String newPassword,
  }) async {
    try {
      await api.changePassword(
        oldPassword: oldPassword,
        newPassword: newPassword,
      );
    } finally {
      notifyListeners();
    }
  }

  Future<void> logout() async {
    final key = scope;
    _accountEpoch++;
    _stopObserving();
    accountId = null;
    accountName = null;
    accountEmail = null;
    accountHasPassword = null;
    accountSummary = null;
    accountSummaryError = null;
    accountSummaryLoading = false;
    historyRefreshing = false;
    modelRef = '';
    reasoningEffort = '';
    current = null;
    pending = null;
    conversations = [];
    models = [];
    _queued.clear();
    busy = false;
    loading = false;
    notifyListeners();
    final revoke = api.logout();
    try {
      if (key != null) await cache.clear(key);
    } finally {
      await revoke;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _accountEpoch++;
    _stopObserving();
    super.dispose();
  }
}
