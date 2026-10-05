import '../core/sse.dart';

class Conversation {
  Conversation(this.json);
  final Map<String, dynamic> json;
  String get id => json['id'] as String;
  String get title => json['title'] as String? ?? '';
  int get revision => (json['revision'] as num?)?.toInt() ?? 0;
  List<Map<String, dynamic>> get messages =>
      (json['messages'] as List? ?? []).cast<Map<String, dynamic>>();
  Map<String, dynamic>? get run => json['run'] as Map<String, dynamic>?;
  String get status => run?['status'] as String? ?? '';
  bool get active => [
    'running',
    'queued',
    'waiting_tool',
    'waiting_inference',
  ].contains(status);
  bool get needsDevice =>
      ['waiting_tool', 'waiting_inference'].contains(status);
  String get preview => run?['preview'] as String? ?? '';

  Conversation apply(ServerEvent event) {
    if (event.data['id'] != id) return this;
    final revision = (event.data['revision'] as num?)?.toInt() ?? -1;
    if (revision < this.revision) return this;
    if (event.type == 'snapshot') return Conversation(event.data);
    if (event.type == 'progress') return Conversation({...json, ...event.data});
    return this;
  }
}
