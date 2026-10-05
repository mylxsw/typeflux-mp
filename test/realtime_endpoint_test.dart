import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:typeflux_app/core/environment.dart';
import 'package:typeflux_app/voice/realtime_endpoint.dart';

void main() {
  const development = ApiOriginPolicy(
    debugBuild: true,
    insecureHttpRequested: true,
  );

  test('Mac realtime origins become local WebSocket endpoints', () {
    for (final host in ['mac-pro.local', 'mac-mini.local']) {
      expect(
        realtimeWebSocketUri(
          'http://$host:8081',
          policy: development,
        ).toString(),
        'ws://$host:8081/api/v1/asr/ws/default',
      );
    }
  });

  test('HTTPS realtime stays encrypted without a development flag', () {
    expect(
      realtimeWebSocketUri('https://asr.example.com:8443/').toString(),
      'wss://asr.example.com:8443/api/v1/asr/ws/default',
    );
  });

  test('local realtime HTTP needs both Debug mode and explicit opt-in', () {
    for (final policy in [
      const ApiOriginPolicy(debugBuild: true, insecureHttpRequested: false),
      const ApiOriginPolicy(debugBuild: false, insecureHttpRequested: true),
      const ApiOriginPolicy(debugBuild: false, insecureHttpRequested: false),
    ]) {
      expect(
        () =>
            realtimeWebSocketUri('http://mac-mini.local:8081', policy: policy),
        throwsFormatException,
      );
    }
  });

  test('development realtime rejects public HTTP and malformed origins', () {
    for (final origin in [
      'http://asr.example.com:8081',
      'http://mac-pro.local.example.com:8081',
      'http://user:password@mac-pro.local:8081',
      'http://mac-pro.local:8081/api',
      'http://mac-pro.local:8081?token=fixture',
      'http://mac-pro.local:8081#fragment',
      'http://mac-pro.local:0',
      'http://mac-pro.local:65536',
      'ws://mac-pro.local:8081',
      'https://',
    ]) {
      expect(
        () => realtimeWebSocketUri(origin, policy: development),
        throwsFormatException,
        reason: origin,
      );
    }
  });

  test('default realtime policy follows the actual build flags', () {
    final origin = 'http://mac-pro.local:8081';
    if (ApiOriginPolicy.fromBuild.allowsLocalHttp) {
      expect(realtimeWebSocketUri(origin).scheme, 'ws');
    } else {
      expect(() => realtimeWebSocketUri(origin), throwsFormatException);
    }
  });

  test(
    'local WebSocket handshake uses the ASR path and token header',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final endpoint = realtimeWebSocketUri(
        'http://127.0.0.1:${server.port}',
        policy: development,
      );
      final connecting = WebSocket.connect(
        endpoint.toString(),
        headers: {'Authorization': 'Bearer fixture-token'},
      );
      final request = await server.first;
      expect(request.uri.path, '/api/v1/asr/ws/default');
      expect(request.headers.value('Authorization'), 'Bearer fixture-token');
      final peer = await WebSocketTransformer.upgrade(request);
      final client = await connecting;
      peer.add('fixture-ready');
      expect(await client.first, 'fixture-ready');
      await Future.wait([client.close(), peer.close()]);
    },
  );
}
