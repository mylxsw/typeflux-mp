import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:typeflux_app/chat/chat_controller.dart';
import 'package:typeflux_app/core/api.dart';
import 'package:typeflux_app/core/preferences.dart';
import 'package:typeflux_app/core/session.dart';
import 'package:typeflux_app/ui/advanced_server_page.dart';
import 'package:typeflux_app/ui/change_password_page.dart';
import 'package:typeflux_app/ui/settings_page.dart';
import 'package:typeflux_app/ui/theme.dart';

import 'support/fakes.dart';

ChatController _controller({MockClient? client, bool hasPassword = true}) {
  final api =
      TypefluxApi(
          origin: Uri.parse('https://api.example.com'),
          vault: MemoryVault(),
          client:
              client ??
              MockClient(
                (_) async => http.Response('{"code":"OK","data":{}}', 200),
              ),
        )
        ..session = Session(
          'fixture-access',
          'fixture-refresh',
          DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        );
  return ChatController(api, MemoryCache())
    ..accountId = 'fixture'
    ..accountName = '演示用户'
    ..accountEmail = 'demo@example.com'
    ..accountHasPassword = hasPassword;
}

Future<void> _show(
  WidgetTester tester,
  Widget page, {
  AppPreferences? preferences,
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  Widget buildApp() => MaterialApp(
    locale: preferences?.locale ?? const Locale('zh'),
    supportedLocales: const [Locale('zh'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: typefluxTheme(brightness),
    darkTheme: typefluxTheme(Brightness.dark),
    themeMode: preferences?.themeMode ?? ThemeMode.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => page),
          ),
          child: const Text('Open settings'),
        ),
      ),
    ),
  );
  await tester.pumpWidget(
    preferences == null
        ? buildApp()
        : AnimatedBuilder(
            animation: preferences,
            builder: (_, _) => buildApp(),
          ),
  );
  await tester.tap(find.text('Open settings'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String text) async {
  final matches = find.text(text);
  if (matches.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      matches,
      180,
      scrollable: find.byType(Scrollable).first,
    );
  }
  final finder = matches.last;
  await tester.ensureVisible(finder);
  // ensureVisible changes the scroll offset synchronously; layout completes
  // on the next frame before the target's hit-test geometry is current.
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('appearance and language update their persisted preferences', (
    tester,
  ) async {
    final vault = MemoryVault();
    final preferences = AppPreferences(vault);
    final chat = _controller();
    addTearDown(preferences.dispose);
    addTearDown(chat.dispose);
    addTearDown(chat.api.close);
    await _show(
      tester,
      SettingsPage(
        controller: chat,
        preferences: preferences,
        onLogout: () async {},
      ),
      preferences: preferences,
    );
    expect(find.text('demo@example.com'), findsOneWidget);
    await _tap(tester, '深色');
    expect(preferences.themeMode, ThemeMode.dark);
    await _tap(tester, '语言');
    await _tap(tester, 'English');
    expect(preferences.locale, const Locale('en'));
    await tester.scrollUntilVisible(
      find.text('Settings'),
      -180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Settings'), findsOneWidget);
    final restored = AppPreferences(vault);
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.themeMode, ThemeMode.dark);
    expect(restored.locale, const Locale('en'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'logout requires confirmation and removes settings route after completion',
    (tester) async {
      final chat = _controller();
      final completion = Completer<void>();
      var calls = 0;
      addTearDown(chat.dispose);
      addTearDown(chat.api.close);
      await _show(
        tester,
        SettingsPage(
          controller: chat,
          onLogout: () {
            calls++;
            return completion.future;
          },
        ),
      );
      await _tap(tester, '退出登录');
      await _tap(tester, '取消');
      expect(calls, 0);
      await _tap(tester, '退出登录');
      await tester.tap(find.widgetWithText(TextButton, '退出登录'));
      await tester.pump();
      expect(calls, 1);
      expect(find.byType(SettingsPage), findsOneWidget);
      completion.complete();
      await tester.pumpAndSettle();
      expect(find.text('Open settings'), findsOneWidget);
      expect(find.byType(SettingsPage), findsNothing);
    },
  );

  testWidgets('signed-in advanced server cannot change the account origin', (
    tester,
  ) async {
    final chat = _controller();
    addTearDown(chat.dispose);
    addTearDown(chat.api.close);
    await _show(tester, SettingsPage(controller: chat, onLogout: () async {}));
    await tester.tap(find.byKey(const ValueKey('settings-profile')));
    await tester.pumpAndSettle();
    await _tap(tester, '高级设置');
    expect(find.text('https://api.example.com'), findsOneWidget);
    expect(find.textContaining('请先退出登录'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('保存'), findsNothing);
  });

  testWidgets(
    'anonymous advanced server validates input before returning a new origin',
    (tester) async {
      await _show(
        tester,
        const AdvancedServerPage(origin: 'https://api.example.com'),
      );
      await tester.enterText(
        find.byType(TextField),
        'https://example.com/private?token=fixture',
      );
      await _tap(tester, '保存');
      expect(find.textContaining('不包含路径'), findsOneWidget);
      expect(find.byType(AdvancedServerPage), findsOneWidget);
      await tester.enterText(
        find.byType(TextField),
        'https://custom.example.com/',
      );
      await _tap(tester, '保存');
      expect(find.byType(AdvancedServerPage), findsNothing);
    },
  );

  testWidgets(
    'password validation preserves fields and never submits mismatch',
    (tester) async {
      var requests = 0;
      final chat = _controller(
        client: MockClient((_) async {
          requests++;
          return http.Response('{"code":"OK","data":{}}', 200);
        }),
      );
      addTearDown(chat.dispose);
      addTearDown(chat.api.close);
      await _show(
        tester,
        ChangePasswordPage(controller: chat, onLogout: () async {}),
      );
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'OldPass1');
      await tester.enterText(fields.at(1), 'NewPass2');
      await tester.enterText(fields.at(2), 'Different1');
      await _tap(tester, '保存密码');
      expect(find.text('两次输入的密码不一致。'), findsOneWidget);
      expect(requests, 0);
      expect(
        tester.widget<TextField>(fields.at(1)).controller!.text,
        'NewPass2',
      );
    },
  );

  testWidgets('incorrect current password is recoverable without signing out', (
    tester,
  ) async {
    var requests = 0;
    var logouts = 0;
    final chat = _controller(
      client: MockClient((request) async {
        requests++;
        expect(request.url.path, '/api/v1/auth/change-password');
        return http.Response('{"code":"AUTH_INVALID_CREDENTIALS"}', 401);
      }),
    );
    addTearDown(chat.dispose);
    addTearDown(chat.api.close);
    await _show(
      tester,
      ChangePasswordPage(controller: chat, onLogout: () async => logouts++),
    );
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'WrongPass1');
    await tester.enterText(fields.at(1), 'NewPass2');
    await tester.enterText(fields.at(2), 'NewPass2');
    await _tap(tester, '保存密码');
    expect(find.text('当前密码不正确，请重试。'), findsOneWidget);
    expect(requests, 1);
    expect(logouts, 0);
    expect(tester.widget<TextField>(fields.at(1)).controller!.text, 'NewPass2');
  });

  testWidgets(
    'changing password submits once then signs out and closes the stack',
    (tester) async {
      final response = Completer<http.Response>();
      var requests = 0;
      var logouts = 0;
      final chat = _controller(
        client: MockClient((request) {
          if (request.method == 'GET') {
            return Future.value(http.Response('{"code":"OK","data":{}}', 200));
          }
          requests++;
          expect(jsonDecode(request.body), {
            'old_password': 'OldPass1',
            'new_password': 'NewPass2',
          });
          return response.future;
        }),
      );
      addTearDown(chat.dispose);
      addTearDown(chat.api.close);
      await _show(
        tester,
        SettingsPage(controller: chat, onLogout: () async => logouts++),
      );
      await tester.tap(find.byKey(const ValueKey('settings-profile')));
      await tester.pumpAndSettle();
      await _tap(tester, '修改密码');
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'OldPass1');
      await tester.enterText(fields.at(1), 'NewPass2');
      await tester.enterText(fields.at(2), 'NewPass2');
      await tester.ensureVisible(find.text('保存密码'));
      await tester.tap(find.text('保存密码'));
      await tester.pump();
      expect(requests, 1);
      expect(tester.widget<TextField>(fields.first).enabled, false);
      response.complete(
        http.Response('{"code":"OK","data":{"changed":true}}', 200),
      );
      await tester.pumpAndSettle();
      expect(logouts, 1);
      expect(find.byType(ChangePasswordPage), findsNothing);
      expect(find.byType(SettingsPage), findsNothing);
      expect(find.text('密码已更新，请重新登录。'), findsOneWidget);
    },
  );

  testWidgets(
    'an OAuth account can set its first password without an old password',
    (tester) async {
      Map<String, dynamic>? body;
      final chat = _controller(
        hasPassword: false,
        client: MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"code":"OK","data":{"changed":true}}', 200);
        }),
      );
      addTearDown(chat.dispose);
      addTearDown(chat.api.close);
      await _show(
        tester,
        ChangePasswordPage(controller: chat, onLogout: () async {}),
      );
      expect(find.text('当前密码'), findsNothing);
      expect(find.text('设置密码'), findsOneWidget);
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.at(0), 'NewPass2');
      await tester.enterText(fields.at(1), 'NewPass2');
      await _tap(tester, '保存密码');
      expect(body?['new_password'], 'NewPass2');
      expect(body?['old_password'], isNull);
    },
  );

  testWidgets(
    'settings and password form remain reachable on a small screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final chat = _controller();
      addTearDown(chat.dispose);
      addTearDown(chat.api.close);
      await _show(
        tester,
        SettingsPage(controller: chat, onLogout: () async {}),
        textScale: 1.8,
        brightness: Brightness.dark,
      );
      await tester.scrollUntilVisible(
        find.text('退出登录'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView), const Offset(0, 1600));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-profile')));
      await tester.pumpAndSettle();
      await _tap(tester, '修改密码');
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('保存密码'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
