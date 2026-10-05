/// Aliyun emits sentence finals; Doubao may emit an authoritative whole result.
class Transcript {
  String committed = '', partial = '';
  bool hasFinal = false;
  String get text => committed + partial;
  void accept(Map<String, dynamic> event) {
    final text = event['text'] as String? ?? '';
    if (event['type'] == 'final' || event['is_final'] == true) {
      final meta = event['meta'] as Map<String, dynamic>?;
      committed = meta?['authoritative'] == true ? text : committed + text;
      partial = '';
      hasFinal = true;
    } else if (event['type'] == 'partial') {
      partial = text;
    }
  }
}
