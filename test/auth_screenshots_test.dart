import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:typeflux_app/core/api.dart';
import 'package:typeflux_app/ui/login_page.dart';
import 'package:typeflux_app/ui/theme.dart';

import 'support/fakes.dart';

Finder input(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(TextField),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final scene in [
    (
      name: 'v4-01-welcome-light',
      page: 'welcome',
      dark: false,
      english: false,
      keyboard: false,
    ),
    (
      name: 'v4-01-welcome-dark',
      page: 'welcome',
      dark: true,
      english: false,
      keyboard: false,
    ),
    (
      name: 'v4-01-welcome-english',
      page: 'welcome',
      dark: false,
      english: true,
      keyboard: false,
    ),
    (
      name: 'login-light',
      page: 'login',
      dark: false,
      english: false,
      keyboard: false,
    ),
    (
      name: 'register-light',
      page: 'register',
      dark: false,
      english: false,
      keyboard: false,
    ),
    (
      name: 'server-settings-light',
      page: 'server',
      dark: false,
      english: false,
      keyboard: false,
    ),
    (
      name: 'login-dark',
      page: 'login',
      dark: true,
      english: false,
      keyboard: false,
    ),
    (
      name: 'register-dark',
      page: 'register',
      dark: true,
      english: false,
      keyboard: false,
    ),
    (
      name: 'verify-email-light',
      page: 'verify',
      dark: false,
      english: false,
      keyboard: false,
    ),
    (
      name: 'verify-email-dark',
      page: 'verify',
      dark: true,
      english: false,
      keyboard: false,
    ),
    (
      name: 'forgot-password-light',
      page: 'forgot',
      dark: false,
      english: false,
      keyboard: false,
    ),
    (
      name: 'reset-password-light',
      page: 'reset',
      dark: false,
      english: false,
      keyboard: false,
    ),
    (
      name: 'reset-password-dark',
      page: 'reset',
      dark: true,
      english: false,
      keyboard: false,
    ),
    (
      name: 'login-validation',
      page: 'validation',
      dark: false,
      english: false,
      keyboard: false,
    ),
    (
      name: 'login-keyboard',
      page: 'login',
      dark: false,
      english: false,
      keyboard: true,
    ),
    (
      name: 'login-english',
      page: 'login',
      dark: false,
      english: true,
      keyboard: false,
    ),
  ]) {
    testWidgets('v4 account screenshot ${scene.name}', (tester) async {
      tester.view.physicalSize = const Size(392, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final output = Platform.environment['TYPEFLUX_RENDER_DIR'];
      final previousShadows = debugDisableShadows;
      if (output != null) {
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = previousShadows);
        await tester.runAsync(() async {
          final font = FontLoader('PreviewFont')
            ..addFont(
              File(
                Platform.environment['TYPEFLUX_PREVIEW_FONT'] ??
                    '/System/Library/Fonts/STHeiti Light.ttc',
              ).readAsBytes().then(ByteData.sublistView),
            );
          await font.load();
          await (FontLoader('PreviewLatin')..addFont(
                File('/System/Library/Fonts/SFNS.ttf')
                    .readAsBytes()
                    .then(ByteData.sublistView),
              ))
              .load();
          final icons = FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await icons.load();
        });
      }

      final boundary = GlobalKey();
      final requests = <String>[];
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: Locale(scene.english ? 'en' : 'zh'),
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
                viewInsets: EdgeInsets.only(bottom: scene.keyboard ? 300 : 0),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: LoginPage(
              vault: MemoryVault(),
              initialOrigin: 'https://api.typeflux.app',
              apiFactory: (origin, vault) => TypefluxApi(
                origin: origin,
                vault: vault,
                client: MockClient((request) async {
                  requests.add(request.url.path);
                  expect(
                    request.url.path,
                    isIn([
                      '/api/v1/auth/register',
                      '/api/v1/auth/forgot-password',
                    ]),
                  );
                  return http.Response(
                    jsonEncode({
                      'code': 'OK',
                      'data': {'sent': true},
                    }),
                    200,
                  );
                }),
              ),
              onSignedIn: (_) async => fail('Screenshots must never sign in'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      if (scene.page != 'welcome') {
        await tester.tap(find.byKey(const ValueKey('auth-email-login')));
        await tester.pumpAndSettle();
      }

      if (scene.page == 'register' || scene.page == 'verify') {
        await tester.ensureVisible(find.byKey(const ValueKey('auth-switch')));
        await tester.tap(find.byKey(const ValueKey('auth-switch')));
        await tester.pumpAndSettle();
        expect(find.text('创建账户'), findsNWidgets(2));
        if (scene.page == 'verify') {
          await tester.enterText(input('auth-email'), 'demo@example.com');
          await tester.enterText(input('auth-password'), 'Screenshot123');
          await tester.ensureVisible(find.byKey(const ValueKey('auth-submit')));
          await tester.tap(find.byKey(const ValueKey('auth-submit')));
          await tester.pumpAndSettle();
          expect(find.text('验证邮箱'), findsOneWidget);
          expect(input('auth-code'), findsOneWidget);
          expect(requests, ['/api/v1/auth/register']);
        }
      } else if (scene.page == 'server') {
        await tester.ensureVisible(find.byKey(const ValueKey('auth-advanced')));
        await tester.tap(find.byKey(const ValueKey('auth-advanced')));
        await tester.pumpAndSettle();
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                widget.controller?.text == 'https://api.typeflux.app',
          ),
          findsOneWidget,
        );
      } else if (scene.page == 'forgot' || scene.page == 'reset') {
        await tester.ensureVisible(find.byKey(const ValueKey('auth-forgot')));
        await tester.tap(find.byKey(const ValueKey('auth-forgot')));
        await tester.pumpAndSettle();
        expect(find.text('找回密码'), findsOneWidget);
        if (scene.page == 'reset') {
          await tester.enterText(input('auth-email'), 'demo@example.com');
          await tester.ensureVisible(find.byKey(const ValueKey('auth-submit')));
          await tester.tap(find.byKey(const ValueKey('auth-submit')));
          await tester.pumpAndSettle();
          expect(input('auth-new-password'), findsOneWidget);
          expect(requests, ['/api/v1/auth/forgot-password']);
        }
      } else if (scene.page == 'validation') {
        await tester.ensureVisible(find.byKey(const ValueKey('auth-submit')));
        await tester.tap(find.byKey(const ValueKey('auth-submit')));
        await tester.pumpAndSettle();
        expect(find.text('请输入邮箱。'), findsOneWidget);
        expect(find.text('请输入密码。'), findsNothing);
        expect(requests, isEmpty);
      }
      if (scene.keyboard) {
        await tester.enterText(input('auth-email'), 'demo@example.com');
        await tester.tap(input('auth-password'));
        await tester.ensureVisible(input('auth-password'));
        await tester.pumpAndSettle();
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
