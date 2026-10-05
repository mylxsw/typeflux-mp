import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:typeflux_app/chat/attachments.dart';

void main() {
  test('PNG becomes JPEG with bounded dimensions and preserved filename', () {
    final source = img.Image(width: 2000, height: 1000);
    final result = prepareAttachment({
      'name': 'diagram.png',
      'bytes': Uint8List.fromList(img.encodePng(source)),
    });
    expect(result['kind'], 'image');
    expect(result['name'], 'diagram.png');
    final jpeg = img.decodeJpg(
      base64Decode((result['image'] as String).split(',').last),
    );
    expect(jpeg!.width, 1600);
    expect(jpeg.height, 800);
    expect(jpeg.exif.isEmpty, true);
  });
  test('UTF-8 Chinese text matches server file contract', () {
    final result = prepareAttachment({
      'name': 'note.md',
      'bytes': Uint8List.fromList(utf8.encode('你好，世界。')),
    });
    expect(result['kind'], 'file');
    expect(result['text'], '你好，世界。');
    expect(result.containsKey('path'), false);
  });
  test('oversized text and unsupported files fail before upload', () {
    expect(
      () =>
          prepareAttachment({'name': 'large.txt', 'bytes': Uint8List(200001)}),
      throwsFormatException,
    );
    expect(
      () => prepareAttachment({'name': 'unsafe.exe', 'bytes': Uint8List(1)}),
      throwsFormatException,
    );
    expect(
      () => prepareAttachment({'name': 'invalid.png', 'bytes': Uint8List(1)}),
      throwsFormatException,
    );
  });
}
