import 'dart:convert';

class ServerEvent {
  const ServerEvent(this.type, this.data);
  final String type;
  final Map<String, dynamic> data;
}

/// Framing survives split UTF-8, CRLF, comments and multi-line SSE data.
Stream<ServerEvent> decodeEvents(Stream<List<int>> bytes) async* {
  var type = 'message';
  var data = <String>[];
  var size = 0;
  await for (final line
      in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (data.isNotEmpty) {
        final value = jsonDecode(data.join('\n'));
        if (value is! Map<String, dynamic>) {
          throw const FormatException('Invalid event');
        }
        yield ServerEvent(type, value);
      }
      type = 'message';
      data = [];
      size = 0;
    } else if (line.startsWith('event:')) {
      type = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      final value = line.substring(5);
      data.add(value.startsWith(' ') ? value.substring(1) : value);
      size += value.length;
      if (size > 12 * 1024 * 1024) {
        throw const FormatException('Event too large');
      }
    }
  }
  // An unterminated frame is not a committed update.
}
