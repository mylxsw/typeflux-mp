import 'package:typeflux_app/core/session.dart';
import 'package:typeflux_app/chat/cache.dart';

class MemoryVault implements Vault {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class MemoryCache implements ChatCache {
  final values = <String, Map<String, dynamic>>{};
  @override
  Future<Map<String, dynamic>?> read(String scope) async => values[scope];
  @override
  Future<void> write(String scope, Map<String, dynamic> value) async {
    values[scope] = value;
  }

  @override
  Future<void> clear(String scope) async {
    values.remove(scope);
  }
}
