import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:typeflux_app/core/api.dart';
import 'package:typeflux_app/core/environment.dart';
import 'package:typeflux_app/core/session.dart';
import 'package:typeflux_app/main.dart';
import 'package:typeflux_app/ui/login_page.dart';

import 'support/fakes.dart';

class _RecordingVault extends MemoryVault {
  final reads = <String>[];
  bool failServerRead = false;
  @override
  Future<String?> read(String key) async {
    reads.add(key);
    if (key == 'server' && failServerRead) throw StateError('unreadable');
    return super.read(key);
  }
}

Future<void> _restore(WidgetTester tester, TypefluxApp app) async {
  await tester.pumpWidget(app);
  // The welcome orb is continuously animated; pump only restoration frames.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  test(
    'explicit build origin wins saved server, and ordinary launches restore it',
    () {
      const dev = AppEnvironment(apiUrl: ' https://dev.example.com ');
      expect(
        dev.resolveOrigin(savedOrigin: 'https://api.typeflux.app'),
        'https://dev.example.com',
      );
      const normal = AppEnvironment(apiUrl: '');
      expect(
        normal.resolveOrigin(savedOrigin: 'https://custom.example.com'),
        'https://custom.example.com',
      );
      expect(
        normal.resolveOrigin(savedOrigin: '  '),
        AppEnvironment.productionOrigin,
      );
      expect(normal.resolveOrigin(), AppEnvironment.productionOrigin);
    },
  );

  test('HTTP needs both debug mode and explicit opt-in, even on loopback', () {
    final local = Uri.parse('http://127.0.0.1:8080');
    for (final policy in [
      const ApiOriginPolicy(debugBuild: true, insecureHttpRequested: false),
      const ApiOriginPolicy(debugBuild: false, insecureHttpRequested: true),
      const ApiOriginPolicy(debugBuild: false, insecureHttpRequested: false),
    ]) {
      expect(() => policy.validate(local), throwsFormatException);
      expect(
        () => policy.validate(Uri.parse('https://api.typeflux.app')),
        returnsNormally,
      );
    }
  });

  test(
    'debug opt-in accepts local network addresses and rejects public HTTP',
    () {
      const policy = ApiOriginPolicy(
        debugBuild: true,
        insecureHttpRequested: true,
      );
      for (final host in [
        'localhost',
        '127.0.0.1',
        '10.0.2.2',
        '10.20.30.40',
        '172.16.0.1',
        '172.31.255.254',
        '192.168.1.5',
        '169.254.10.5',
        'nas-server.local',
        '[::1]',
        '[fd12::1]',
        '[fe80::1]',
      ]) {
        expect(
          () => policy.validate(Uri.parse('http://$host:8080')),
          returnsNormally,
          reason: host,
        );
      }
      for (final host in [
        'example.com',
        'nas-server.local.example.com',
        'localhost.example.com',
        '172.15.1.1',
        '172.32.1.1',
        '192.169.1.1',
        '8.8.8.8',
        '[2001:4860:4860::8888]',
      ]) {
        expect(
          () => policy.validate(Uri.parse('http://$host:8080')),
          throwsFormatException,
          reason: host,
        );
      }
    },
  );

  test(
    'development HTTP never permits credentials paths queries or invalid ports',
    () {
      const policy = ApiOriginPolicy(
        debugBuild: true,
        insecureHttpRequested: true,
      );
      for (final value in [
        'http://user:password@nas-server.local:8080',
        'http://127.0.0.1:8080/api',
        'http://localhost:8080?token=fixture',
        'http://localhost:8080#fragment',
        'http://localhost:0',
        'http://localhost:65536',
        'ftp://localhost:8080',
      ]) {
        expect(
          () => policy.validate(Uri.parse(value)),
          throwsFormatException,
          reason: value,
        );
      }
    },
  );

  test('API construction uses the compile-time policy', () {
    final uri = Uri.parse('http://127.0.0.1:8080');
    if (ApiOriginPolicy.fromBuild.allowsLocalHttp) {
      final api = TypefluxApi(origin: uri, vault: MemoryVault());
      expect(api.origin, uri);
      api.close();
    } else {
      expect(
        () => TypefluxApi(origin: uri, vault: MemoryVault()),
        throwsFormatException,
      );
    }
    expect(
      () => TypefluxApi(
        origin: Uri.parse('http://example.com'),
        vault: MemoryVault(),
      ),
      throwsFormatException,
    );
  });

  testWidgets(
    'explicit launch bypasses saved production server and its session',
    (tester) async {
      final vault = _RecordingVault()
        ..values['server'] = 'https://api.typeflux.app'
        ..values['session:https://api.typeflux.app'] = const Session(
          'production',
          'production-refresh',
          9999999999,
        ).encode()
        ..failServerRead = true;
      final requested = <Uri>[];
      await _restore(
        tester,
        TypefluxApp(
          vault: vault,
          environment: const AppEnvironment(apiUrl: 'https://dev.example.com'),
          apiFactory: (origin, store) {
            requested.add(origin);
            return TypefluxApi(
              origin: origin,
              vault: store,
              client: MockClient(
                (_) async => throw StateError(
                  'No request expected without a dev session',
                ),
              ),
            );
          },
        ),
      );
      expect(requested.single.origin, 'https://dev.example.com');
      expect(vault.reads, contains('session:https://dev.example.com'));
      expect(vault.reads, isNot(contains('server')));
      expect(vault.reads, isNot(contains('session:https://api.typeflux.app')));
      expect(
        tester.widget<LoginPage>(find.byType(LoginPage)).initialOrigin,
        'https://dev.example.com',
      );
      expect(
        jsonDecode(
          vault.values['session:https://api.typeflux.app']!,
        )['access_token'],
        'production',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'invalid explicit origin remains on sign-in instead of silently using production',
    (tester) async {
      final vault = _RecordingVault()
        ..values['server'] = 'https://api.typeflux.app';
      await _restore(
        tester,
        TypefluxApp(
          vault: vault,
          environment: const AppEnvironment(
            apiUrl: 'http://public.example.com',
          ),
          apiFactory: (origin, store) => TypefluxApi(
            origin: origin,
            vault: store,
            client: MockClient(
              (_) async => http.Response('{"code":"UNEXPECTED"}', 500),
            ),
          ),
        ),
      );
      expect(find.byType(LoginPage), findsOneWidget);
      expect(
        tester.widget<LoginPage>(find.byType(LoginPage)).initialOrigin,
        'http://public.example.com',
      );
      expect(vault.reads, isNot(contains('session:https://api.typeflux.app')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'launch without an explicit origin restores the saved custom server',
    (tester) async {
      final vault = _RecordingVault()
        ..values['server'] = 'https://custom.example.com';
      await _restore(
        tester,
        TypefluxApp(
          vault: vault,
          environment: const AppEnvironment(apiUrl: ''),
        ),
      );
      expect(
        tester.widget<LoginPage>(find.byType(LoginPage)).initialOrigin,
        'https://custom.example.com',
      );
      expect(vault.reads, contains('session:https://custom.example.com'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
