import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:typeflux_app/core/api.dart';
import 'package:typeflux_app/core/session.dart';
import 'package:typeflux_app/ui/login_page.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typeflux_app/core/preferences.dart';
import 'package:typeflux_app/main.dart';

import 'support/fakes.dart';

class _FailingVault extends MemoryVault {
  bool fail = true;
  @override
  Future<void> write(String key, String value) async {
    if (fail) throw StateError('storage unavailable');
    await super.write(key, value);
  }
}

void main() {
  test(
    'serial preferences survive restart without overwriting one another',
    () async {
      final vault = MemoryVault();
      final prefs = AppPreferences(vault);
      await Future.wait([
        prefs.setThemeMode(ThemeMode.dark),
        prefs.setLocale(const Locale('zh')),
        prefs.setThemeMode(ThemeMode.light),
      ]);
      final restored = AppPreferences(vault);
      await restored.load();
      expect(restored.themeMode, ThemeMode.light);
      expect(restored.locale, const Locale('zh'));
      await restored.setLocale(null);
      expect(
        jsonDecode(vault.values[AppPreferences.storageKey]!)['language'],
        'system',
      );
      prefs.dispose();
      restored.dispose();
    },
  );

  test(
    'a failed save rolls back and allows a later successful update',
    () async {
      final vault = _FailingVault();
      final prefs = AppPreferences(vault);
      await expectLater(prefs.setThemeMode(ThemeMode.dark), throwsStateError);
      expect(prefs.themeMode, ThemeMode.system);
      vault.fail = false;
      await prefs.setLocale(const Locale('en'));
      expect(prefs.locale, const Locale('en'));
      expect(
        jsonDecode(vault.values[AppPreferences.storageKey]!)['theme'],
        'system',
      );
      prefs.dispose();
    },
  );

  test('unsupported and corrupt preferences use the device defaults', () async {
    for (final value in ['broken', '[]', '{"theme":"other","language":"fr"}']) {
      final vault = MemoryVault()..values[AppPreferences.storageKey] = value;
      final prefs = AppPreferences(vault);
      await prefs.load();
      expect(prefs.themeMode, ThemeMode.system);
      expect(prefs.locale, isNull);
      prefs.dispose();
    }
  });

  testWidgets(
    'expired saved session returns to sign-in when refresh is revoked',
    (tester) async {
      final vault = MemoryVault()
        ..values['server'] = 'https://example.com'
        ..values['session:https://example.com'] = const Session(
          'old',
          'revoked',
          0,
        ).encode();
      await tester.pumpWidget(
        TypefluxApp(
          vault: vault,
          apiFactory: (origin, vault) => TypefluxApi(
            origin: origin,
            vault: vault,
            client: MockClient(
              (request) async =>
                  http.Response('{"code":"AUTH_REFRESH_TOKEN_INVALID"}', 401),
            ),
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(LoginPage), findsOneWidget);
      expect(vault.values['session:https://example.com'], isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'app restores theme and locale and applies changes across routes',
    (tester) async {
      final vault = MemoryVault()
        ..values[AppPreferences.storageKey] =
            '{"theme":"dark","language":"zh"}';
      await tester.pumpWidget(TypefluxApp(vault: vault));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      var app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);
      expect(app.locale, const Locale('zh'));
      final scope = tester.widget<PreferencesScope>(
        find.byType(PreferencesScope),
      );
      await scope.notifier!.setLocale(const Locale('en'));
      await scope.notifier!.setThemeMode(ThemeMode.light);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.light);
      expect(app.locale, const Locale('en'));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
