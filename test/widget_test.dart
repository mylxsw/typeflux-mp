import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typeflux_app/ui/login_page.dart';

import 'support/fakes.dart';

void main() {
  for (final width in [320.0, 390.0, 1200.0]) {
    testWidgets('login fits $width with Chinese labels and large text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.4),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: LoginPage(vault: MemoryVault(), onSignedIn: (_) async {}),
        ),
      );
      expect(find.text('使用邮箱登录'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey('auth-email-login')),
      );
      await tester.tap(find.byKey(const ValueKey('auth-email-login')));
      await tester.pumpAndSettle();
      expect(find.text('邮箱登录'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(
        find.byType(TextField).first,
        'reader@example.com',
      );
      await tester.ensureVisible(find.text('创建账户'));
      await tester.tap(find.text('创建账户'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
