import '../chat/conversation.dart';

/// Read-only transcript projections. Tool calls never authorize device actions.
List<Map<String, dynamic>> messageMaps(dynamic value) =>
    value is List ? value.whereType<Map<String, dynamic>>().toList() : const [];

String messageString(dynamic value) => value is String ? value : '';

class TranscriptEntry {
  TranscriptEntry.message(this.message) : activity = const [];
  TranscriptEntry.activity(this.activity) : message = null;

  final Map<String, dynamic>? message;
  final List<Map<String, dynamic>> activity;
  bool get isActivity => activity.isNotEmpty;
}

List<TranscriptEntry> transcriptEntries(
  Conversation conversation, {
  List<Map<String, dynamic>> queued = const [],
}) {
  final messages = [...conversation.messages];
  final run = conversation.run;
  if (conversation.active && run != null) {
    final assistantId = messageString(run['assistant_id']);
    final previewTools = messageMaps(run['preview_tools']);
    final hasPreview =
        conversation.preview.isNotEmpty ||
        messageString(run['reasoning']).isNotEmpty ||
        previewTools.isNotEmpty;
    if (hasPreview &&
        (assistantId.isEmpty || !messages.any((m) => m['id'] == assistantId))) {
      messages.add({
        'id': assistantId.isEmpty ? 'preview-${run['id']}' : assistantId,
        'role': 'assistant',
        'run_id': run['id'],
        'text': conversation.preview,
        'reasoning': run['reasoning'],
        'reasoning_milliseconds': run['reasoning_milliseconds'],
        'tool_calls': previewTools,
        'preview': true,
      });
    }
  }
  final seen = messages.map((message) => message['id']).toSet();
  for (final message in queued) {
    if (message['id'] is String && seen.add(message['id'])) {
      messages.add({...message, 'role': 'user', 'queued': true});
    }
  }
  final entries = <TranscriptEntry>[];
  var activity = <Map<String, dynamic>>[];
  void flush() {
    if (activity.isEmpty) return;
    entries.add(TranscriptEntry.activity(activity));
    activity = [];
  }

  for (final message in messages) {
    if (message['role'] == 'tool') continue;
    if (message['role'] != 'user' && message['role'] != 'assistant') continue;
    if (message['role'] == 'assistant' &&
        messageMaps(message['tool_calls']).isNotEmpty) {
      if (activity.isNotEmpty && activity.last['run_id'] != message['run_id']) {
        flush();
      }
      final streamingAnswer =
          message['preview'] == true &&
          messageString(message['text']).isNotEmpty;
      activity.add(
        streamingAnswer ? {...message, 'text': '', 'reasoning': ''} : message,
      );
      if (streamingAnswer) {
        flush();
        entries.add(
          TranscriptEntry.message({
            ...message,
            'tool_calls': <Map<String, dynamic>>[],
          }),
        );
      }
    } else {
      flush();
      entries.add(TranscriptEntry.message(message));
    }
  }
  flush();
  return entries;
}

String? answerModelLabel(
  Map<String, dynamic> message,
  Conversation conversation,
  List<Map<String, dynamic>> models,
) {
  var ref = messageString(message['model_ref']);
  if (ref.isEmpty && message['run_id'] == conversation.run?['id']) {
    ref = messageString(conversation.run?['model_ref']);
  }
  if (ref.isEmpty || ref == 'cloud:default') return null;
  for (final model in models) {
    if ('cloud:${model['id']}' == ref || model['id'] == ref) {
      final name = messageString(model['name']);
      if (name.isNotEmpty) return name;
    }
  }
  // An old message may refer to a retired model. Do not label it with the
  // composer's currently selected model or an implementation identifier.
  return null;
}

String? answerCredits(Map<String, dynamic> message, Conversation conversation) {
  final runId = messageString(message['run_id']);
  if (runId.isEmpty) return null;
  final answers = conversation.messages.where(
    (m) =>
        m['role'] == 'assistant' &&
        m['run_id'] == runId &&
        messageMaps(m['tool_calls']).isEmpty,
  );
  if (answers.isEmpty || answers.last['id'] != message['id']) return null;
  final usage = conversation.json['usage'];
  final runs = usage is Map ? usage['runs'] : null;
  final totals = runs is Map ? runs[runId] : null;
  if (totals is! Map ||
      totals['microcredits'] is! num ||
      totals['calls'] is! num ||
      (totals['calls'] as num) <= 0) {
    return null;
  }
  // An incomplete or external receipt is not a confirmed price.
  for (final key in ['pending', 'missing', 'estimated', 'external']) {
    if (totals[key] is! num || (totals[key] as num) != 0) return null;
  }
  final microcredits = totals['microcredits'] as num;
  if (microcredits < 0) return null;
  if (microcredits > 0 && microcredits < 10000) return '<0.01';
  return (microcredits / 1000000)
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'\.?0+$'), '');
}
