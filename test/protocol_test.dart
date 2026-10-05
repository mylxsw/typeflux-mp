import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:typeflux_app/core/sse.dart';
import 'package:typeflux_app/chat/conversation.dart';
import 'package:typeflux_app/voice/transcript.dart';

void main() {
  test(
    'SSE survives byte-split Chinese, comments, CRLF and multiline JSON',
    () async {
      final input = utf8.encode(
        ': ping\r\nevent: snapshot\r\ndata: {"id":"a",\r\ndata: "text":"你好"}\r\n\r\nevent: progress\ndata: {"id":"a"}\n\n',
      );
      final events = await decodeEvents(
        Stream.fromIterable(input.map((b) => [b])),
      ).toList();
      expect(events.map((e) => e.type), ['snapshot', 'progress']);
      expect(events.first.data['text'], '你好');
    },
  );
  test('unterminated SSE does not become a completed update', () async {
    expect(
      await decodeEvents(
        Stream.value(utf8.encode('event: snapshot\ndata: {"id":"x"}')),
      ).toList(),
      isEmpty,
    );
  });
  test(
    'progress preserves history, rejects stale revision and other conversation',
    () {
      final conversation = Conversation({
        'id': 'a',
        'revision': 5,
        'messages': [
          {'text': 'keep'},
        ],
      });
      final progress = conversation.apply(
        const ServerEvent('progress', {
          'id': 'a',
          'revision': 6,
          'run': {'preview': 'hello'},
        }),
      );
      expect(progress.messages.single['text'], 'keep');
      expect(progress.preview, 'hello');
      expect(
        progress.apply(
          const ServerEvent('snapshot', {'id': 'a', 'revision': 4}),
        ),
        same(progress),
      );
      expect(
        progress.apply(
          const ServerEvent('snapshot', {'id': 'b', 'revision': 9}),
        ),
        same(progress),
      );
    },
  );
  test('same revision snapshot still carries late usage updates', () {
    final conversation = Conversation({'id': 'a', 'revision': 5});
    final changed = conversation.apply(
      const ServerEvent('snapshot', {
        'id': 'a',
        'revision': 5,
        'usage': {'version': 2},
      }),
    );
    expect(changed.json['usage']['version'], 2);
  });
  test('sentence finals accumulate and authoritative final replaces', () {
    final transcript = Transcript();
    transcript.accept({'type': 'partial', 'text': '你'});
    expect(transcript.hasFinal, false);
    transcript.accept({'type': 'final', 'text': '你好。'});
    transcript.accept({'type': 'partial', 'text': '测试'});
    expect(transcript.text, '你好。测试');
    transcript.accept({'type': 'final', 'text': '测试。'});
    expect(transcript.text, '你好。测试。');
    transcript.accept({
      'type': 'final',
      'text': '完整结果',
      'meta': {'authoritative': true},
    });
    expect(transcript.text, '完整结果');
  });
}
