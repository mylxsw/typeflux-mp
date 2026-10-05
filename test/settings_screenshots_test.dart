import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:typeflux_app/chat/chat_controller.dart';
import 'package:typeflux_app/core/api.dart';
import 'package:typeflux_app/core/session.dart';
import 'package:typeflux_app/core/preferences.dart';
import 'package:typeflux_app/ui/advanced_server_page.dart';
import 'package:typeflux_app/ui/change_password_page.dart';
import 'package:typeflux_app/ui/settings_page.dart';
import 'package:typeflux_app/ui/theme.dart';

import 'support/fakes.dart';

// Render actual account settings with synthetic data, without calling a service.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final output = Platform.environment['TYPEFLUX_RENDER_DIR'];
  for (final scene in [
    (name: 'settings-appearance', target: 'appearance', dark: false),
    (name: 'settings-language', target: 'language', dark: false),
    (name: 'change-password-light', target: 'password', dark: false),
    (name: 'change-password-dark', target: 'password', dark: true),
    (name: 'signed-in-server-settings', target: 'advanced', dark: false),
  ]) {
    testWidgets('approved settings screenshot ${scene.name}', (tester) async {
      tester.view.physicalSize = const Size(392, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previousShadows = debugDisableShadows;
      if (output != null) {
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = previousShadows);
        await tester.runAsync(() async {
          await (FontLoader('PreviewLatin')..addFont(
                File('/System/Library/Fonts/SFNS.ttf')
                    .readAsBytes()
                    .then(ByteData.sublistView),
              ))
              .load();
          await (FontLoader('PreviewFont')..addFont(
                File(
                  Platform.environment['TYPEFLUX_PREVIEW_FONT'] ??
                      '/System/Library/Fonts/STHeiti Light.ttc',
                ).readAsBytes().then(ByteData.sublistView),
              ))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
      }

      final vault = MemoryVault();
      final api =
          TypefluxApi(
              origin: Uri.parse('https://api.typeflux.app'),
              vault: vault,
              client: MockClient((request) async {
                expect(request.method, 'GET');
                final Object data = switch (request.url.path) {
                  '/api/v1/billing/subscription' => {
                    'billing_enabled': true,
                    'subscription': {'plan_code': 'pro', 'paid': true},
                  },
                  '/api/v1/usage/current-period/stats' => {
                    'period_end': '2026-10-31T00:00:00Z',
                    'credits': {
                      'remaining': 316,
                      'limit': 500,
                      'unlimited': false,
                    },
                  },
                  _ => fail('Unexpected offline screenshot request'),
                };
                return http.Response(
                  jsonEncode({'code': 'OK', 'data': data}),
                  200,
                );
              }),
            )
            ..session = const Session(
              'fixture-access',
              'fixture-refresh',
              9999999999,
            );
      final chat = ChatController(api, MemoryCache())
        ..accountId = 'screenshot-account'
        ..accountName = 'Demir Von'
        ..accountEmail = 'demir@example.com'
        ..accountHasPassword = true;
      final preferences = AppPreferences(vault);
      addTearDown(chat.dispose);
      addTearDown(api.close);
      addTearDown(preferences.dispose);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('zh'),
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: typefluxTheme(
              scene.dark ? Brightness.dark : Brightness.light,
              fontFamily: output == null ? null : 'PreviewLatin',
              fontFamilyFallback: output == null ? null : ['PreviewFont'],
            ).copyWith(platform: TargetPlatform.iOS),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: const EdgeInsets.only(top: 54, bottom: 21),
                viewPadding: const EdgeInsets.only(top: 54, bottom: 21),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: SettingsPage(
              controller: chat,
              version: '0.1.0 (1)',
              preferences: preferences,
              onLogout: () async => fail('Screenshots must never sign out'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (scene.target == 'password' || scene.target == 'advanced') {
        await tester.tap(find.byKey(const ValueKey('settings-profile')));
        await tester.pumpAndSettle();
      }
      if (scene.target != 'appearance') {
        final label = switch (scene.target) {
          'language' => '语言',
          'password' => '修改密码',
          _ => '高级设置',
        };
        final target = find.text(label);
        if (target.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            target,
            160,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      switch (scene.target) {
        case 'appearance':
          expect(find.text('浅色'), findsOneWidget);
          expect(find.text('深色'), findsOneWidget);
        case 'language':
          expect(find.text('简体中文'), findsOneWidget);
          expect(find.text('English'), findsOneWidget);
        case 'password':
          expect(find.byType(ChangePasswordPage), findsOneWidget);
          expect(find.text('当前密码'), findsOneWidget);
          expect(find.text('保存密码'), findsOneWidget);
        case 'advanced':
          expect(find.byType(AdvancedServerPage), findsOneWidget);
          expect(find.text('https://api.typeflux.app'), findsOneWidget);
          expect(find.byType(TextField), findsNothing);
      }
      expect(tester.takeException(), isNull);
      if (output != null) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/${scene.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      debugDisableShadows = previousShadows;
      expect(tester.takeException(), isNull);
    });
  }
}
