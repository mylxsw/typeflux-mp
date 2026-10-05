import 'dart:io';

import 'package:flutter/foundation.dart';

/// Build-selected environments take precedence over the last signed-in server.
/// An empty define means the normal app may restore a user-selected server.
class AppEnvironment {
  const AppEnvironment({
    this.apiUrl = const String.fromEnvironment('TYPEFLUX_API_URL'),
  });

  static const productionOrigin = 'https://api.typeflux.app';
  static const current = AppEnvironment();
  final String apiUrl;

  bool get hasApiOverride => apiUrl.trim().isNotEmpty;

  String resolveOrigin({String? savedOrigin}) {
    if (hasApiOverride) return apiUrl.trim();
    final saved = savedOrigin?.trim();
    return saved?.isNotEmpty == true ? saved! : productionOrigin;
  }
}

/// Native debug transport exceptions cannot protect Dart-owned sockets, so all
/// API origins are checked here as well. Never inject a different policy into a
/// production API client; the client always uses [fromBuild].
class ApiOriginPolicy {
  const ApiOriginPolicy({
    required this.debugBuild,
    required this.insecureHttpRequested,
  });

  static const fromBuild = ApiOriginPolicy(
    debugBuild: kDebugMode,
    insecureHttpRequested: bool.fromEnvironment('TYPEFLUX_ALLOW_INSECURE_HTTP'),
  );

  final bool debugBuild, insecureHttpRequested;

  bool get allowsLocalHttp => debugBuild && insecureHttpRequested;

  void validate(Uri origin) {
    final localHttp =
        origin.scheme == 'http' &&
        allowsLocalHttp &&
        isLocalDevelopmentHost(origin.host);
    if (origin.host.isEmpty ||
        (origin.scheme != 'https' && !localHttp) ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        (origin.path.isNotEmpty && origin.path != '/') ||
        (origin.hasPort && (origin.port < 1 || origin.port > 65535))) {
      throw const FormatException('Use an HTTPS origin without a path');
    }
  }

  static bool isLocalDevelopmentHost(String host) {
    final name = host.toLowerCase();
    if (name == 'localhost' || (name.endsWith('.local') && name.length > 6)) {
      return true;
    }
    final address = InternetAddress.tryParse(name);
    if (address == null) return false;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return bytes[0] == 127 ||
          bytes[0] == 10 ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 192 && bytes[1] == 168) ||
          (bytes[0] == 169 && bytes[1] == 254);
    }
    return address.isLoopback ||
        (bytes[0] & 0xfe) == 0xfc ||
        (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80);
  }
}
