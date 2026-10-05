import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typeflux_app/auth/account_links.dart';
import 'package:typeflux_app/ui/login_page.dart';

import 'support/fakes.dart';

Finder input(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(TextField),
);

Future<void> launch(
  WidgetTester tester, {
  Size size = const Size(392, 852),
  double textScale = 1,
  String language = 'zh',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: const EdgeInsets.only(top: 54, bottom: 21),
          disableAnimations: true,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: LoginPage(
        vault: MemoryVault(),
        onSignedIn: (_) async => fail('No sign-in expected'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('legal links use the existing public localized routes', () {
    expect(
      accountLegalUri(privacy: false, chinese: true).toString(),
      'https://typeflux.app/zh-CN/terms',
    );
    expect(
      accountLegalUri(privacy: true, chinese: false).toString(),
      'https://typeflux.app/privacy',
    );
  });

  testWidgets(
    'welcome is separate from the email form and back clears password',
    (tester) async {
      await launch(tester);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('通过 Apple 继续'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('auth-email-login')));
      await tester.pumpAndSettle();
      expect(find.text('邮箱登录'), findsOneWidget);
      await tester.enterText(input('auth-email'), 'demo@example.com');
      await tester.enterText(input('auth-password'), 'Fixture123');
      expect(find.text('邮箱'), findsOneWidget);
      expect(find.text('密码'), findsOneWidget);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.byKey(const ValueKey('auth-email-login')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(input('auth-email')).controller!.text,
        'demo@example.com',
      );
      expect(
        tester.widget<TextField>(input('auth-password')).controller!.text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unconfigured Apple authorization reports failure and leaves email available',
    (tester) async {
      await launch(tester);
      await tester.tap(find.byKey(const ValueKey('auth-apple')));
      await tester.pumpAndSettle();
      expect(find.text('此版本暂不支持 Apple 登录，请先使用邮箱登录。'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('auth-email-login')));
      await tester.pumpAndSettle();
      expect(input('auth-email'), findsOneWidget);
      expect(find.text('此版本暂不支持 Apple 登录，请先使用邮箱登录。'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'iOS build reports missing Apple configuration without claiming authorization',
    (tester) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await launch(tester);
        await tester.tap(find.byKey(const ValueKey('auth-apple')));
        await tester.pumpAndSettle();
        expect(find.text('此测试版本尚未启用 Apple 登录，请先使用邮箱登录。'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('auth-email-login')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    },
  );

  for (final language in ['zh', 'en']) {
    testWidgets(
      'small $language account flow remains reachable with large text and keyboard',
      (tester) async {
        await launch(
          tester,
          size: const Size(320, 568),
          textScale: 1.8,
          language: language,
        );
        final emailEntry = find.byKey(const ValueKey('auth-email-login'));
        await tester.ensureVisible(emailEntry);
        await tester.pumpAndSettle();
        expect(emailEntry.hitTestable(), findsOneWidget);
        await tester.tap(emailEntry);
        await tester.pumpAndSettle();
        await tester.enterText(input('auth-email'), 'demo@example.com');
        await tester.enterText(input('auth-password'), 'Fixture123');
        tester.view.viewInsets = const FakeViewPadding(bottom: 260);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        final submit = find.byKey(const ValueKey('auth-submit'));
        await tester.ensureVisible(submit);
        await tester.pumpAndSettle();
        final submitRect = tester.getRect(submit);
        expect(submitRect.bottom, lessThanOrEqualTo(308));
        expect(submit.hitTestable(), findsOneWidget);
        expect(
          tester.widget<TextField>(input('auth-email')).controller!.text,
          'demo@example.com',
        );
        expect(
          tester.widget<TextField>(input('auth-password')).controller!.text,
          'Fixture123',
        );
        expect(tester.takeException(), isNull);
        FocusManager.instance.primaryFocus?.unfocus();
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        final register = find.byKey(const ValueKey('auth-switch'));
        await tester.ensureVisible(register);
        await tester.tap(register);
        await tester.pumpAndSettle();
        expect(
          find.text(language == 'zh' ? '创建账户' : 'Create account'),
          findsNWidgets(2),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
