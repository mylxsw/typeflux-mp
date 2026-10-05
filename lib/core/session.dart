import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class Vault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureVault implements Vault {
  const SecureVault();
  static const _storage = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class Session {
  const Session(this.access, this.refresh, this.expiresAt);
  final String access, refresh;
  final int expiresAt;
  factory Session.fromJson(Map<String, dynamic> json) => Session(
    json['access_token'] as String,
    json['refresh_token'] as String,
    (json['expires_at'] as num).toInt(),
  );
  Map<String, dynamic> toJson() => {
    'access_token': access,
    'refresh_token': refresh,
    'expires_at': expiresAt,
  };
  String encode() => jsonEncode(toJson());
}
