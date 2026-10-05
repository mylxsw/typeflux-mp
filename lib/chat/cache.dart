import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

abstract interface class ChatCache {
  Future<Map<String, dynamic>?> read(String scope);
  Future<void> write(String scope, Map<String, dynamic> value);
  Future<void> clear(String scope);
}

/// Application-private cache, partitioned by server and authenticated account.
/// Never stores access tokens. Writes are serialized with logout deletion.
class FileChatCache implements ChatCache {
  Future<void> _tail = Future.value();
  Future<File> _file(String scope) async {
    final directory = await getApplicationSupportDirectory();
    final name = base64Url.encode(utf8.encode(scope));
    return File('${directory.path}/typeflux-cache/$name.json');
  }

  Future<T> _serial<T>(Future<T> Function() work) {
    final result = _tail.then((_) => work());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<Map<String, dynamic>?> read(String scope) => _serial(() async {
    final file = await _file(scope);
    if (!await file.exists()) return null;
    try {
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } on FormatException {
      return null;
    }
  });
  @override
  Future<void> write(String scope, Map<String, dynamic> value) =>
      _serial(() async {
        final file = await _file(scope);
        await file.parent.create(recursive: true);
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsString(jsonEncode(value), flush: true);
        if (Platform.isWindows && await file.exists()) await file.delete();
        await temporary.rename(file.path);
      });
  @override
  Future<void> clear(String scope) => _serial(() async {
    final file = await _file(scope);
    if (await file.exists()) await file.delete();
    final temporary = File('${file.path}.tmp');
    if (await temporary.exists()) await temporary.delete();
  });
}
