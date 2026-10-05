import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

Map<String, dynamic> prepareAttachment(Map<String, dynamic> input) {
  final bytes = input['bytes'] as Uint8List;
  final name = input['name'] as String;
  if (bytes.length > 20 * 1024 * 1024 || utf8.encode(name).length > 255) {
    throw const FormatException('ATTACHMENT_TOO_LARGE');
  }
  final extension = name.split('.').last.toLowerCase();
  final result = <String, dynamic>{
    'id': const Uuid().v4(),
    'name': name,
    'byte_size': bytes.length,
  };
  if (['jpg', 'jpeg', 'png', 'webp'].contains(extension)) {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      throw const FormatException('INVALID_IMAGE');
    }
    if (decoded == null || decoded.width * decoded.height > 40000000) {
      throw const FormatException('INVALID_IMAGE');
    }
    decoded = img.bakeOrientation(decoded);
    if (decoded.width > 1600 || decoded.height > 1600) {
      decoded = img.copyResize(
        decoded,
        width: decoded.width >= decoded.height ? 1600 : null,
        height: decoded.height > decoded.width ? 1600 : null,
      );
    }
    // Rebuild pixels to remove source metadata before uploading.
    final clean = img.Image(
      width: decoded.width,
      height: decoded.height,
      numChannels: 3,
    );
    img.compositeImage(clean, decoded);
    final encoded =
        'data:image/jpeg;base64,${base64Encode(img.encodeJpg(clean, quality: 78))}';
    if (encoded.length > 1500000) {
      throw const FormatException('ATTACHMENT_TOO_LARGE');
    }
    return {...result, 'kind': 'image', 'image': encoded};
  }
  if (!['txt', 'md', 'csv', 'json', 'log'].contains(extension) ||
      bytes.length > 200000) {
    throw const FormatException('ATTACHMENT_TOO_LARGE');
  }
  return {...result, 'kind': 'file', 'text': utf8.decode(bytes)};
}
