import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:typeflux_app/chat/chat_controller.dart';
import 'package:typeflux_app/core/api.dart';
import 'package:typeflux_app/ui/model_picker.dart';
import 'package:typeflux_app/ui/theme.dart';

import 'support/fakes.dart';

const _catalog = [
  {
    'id': 'default',
    'name': 'Claude Sonnet 5.5 Extended Research and Multilingual Reasoning Preview',
    'vision': true,
    'capabilities': {'reasoning': true},
    'reasoning_efforts': ['low', 'medium', 'high', 'xhigh', 'max'],
    'context_window_tokens': 1000000,
    'max_output_tokens': 64000,
    'pricing': {'multiplier': '3'},
  },
  {
    'id': 'alternate',
    'name': 'MiniMax M3 Extended Research and Image Understanding Preview',
    'vision': true,
    'capabilities': {'reasoning': true},
    'reasoning_efforts': ['low', 'medium', 'high', 'xhigh', 'max'],
    'context_window_tokens': 1000000,
    'max_output_tokens': 128000,
    'pricing': {'multiplier': '1'},
  },
];

void main() {
  for (final language in ['zh', 'en']) {
    testWidgets(
      'v4 model popover supports $language large text, long names and all five levels at 292 wide',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        try {
          final api = TypefluxApi(
            origin: Uri.parse('https://example.com'),
            vault: MemoryVault(),
            client: MockClient((_) async {
              fail('The model picker must use the existing offline catalog.');
            }),
          );
          final controller = ChatController(api, MemoryCache())
            ..models = _catalog
                .map((item) => Map<String, dynamic>.from(item))
                .toList();
          final modelsPage = ValueNotifier(false);
          addTearDown(controller.dispose);
          addTearDown(api.close);
          addTearDown(modelsPage.dispose);
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(language),
              supportedLocales: const [Locale('zh'), Locale('en')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: typefluxTheme(Brightness.light),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.5),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 292,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 560),
                      child: AnimatedBuilder(
                        animation: Listenable.merge([controller, modelsPage]),
                        builder: (context, _) => MobileModelPicker(
                          controller: controller,
                          modelsPage: modelsPage.value,
                          onPageChanged: (value) => modelsPage.value = value,
                          hasImages: false,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.getSize(find.byType(MobileModelPicker)).width, 292);
          expect(tester.takeException(), isNull);

          // Keyboard navigation also exercises the slider's accessible choices.
          final slider = find.byType(EffortSlider);
          await tester.ensureVisible(slider);
          final gesture = find
              .descendant(of: slider, matching: find.byType(GestureDetector))
              .first;
          Focus.of(tester.element(gesture)).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.home);
          await tester.pumpAndSettle();
          expect(controller.reasoningEffort, 'low');
          for (final effort in ['medium', 'high', 'xhigh', 'max']) {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
            await tester.pumpAndSettle();
            expect(controller.reasoningEffort, effort);
            expect(tester.takeException(), isNull);
          }

          final changeLabel = language == 'zh' ? '更换模型' : 'Change model';
          final backLabel = language == 'zh' ? '推理强度' : 'Reasoning effort';
          await tester.tap(find.bySemanticsLabel(RegExp(changeLabel)));
          await tester.pumpAndSettle();
          expect(modelsPage.value, true);
          expect(find.byType(ListView), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text(backLabel));
          await tester.pumpAndSettle();
          expect(modelsPage.value, false);
          expect(find.byType(EffortSlider), findsOneWidget);
          expect(controller.reasoningEffort, 'max');

          await tester.tap(find.bySemanticsLabel(RegExp(changeLabel)));
          await tester.pumpAndSettle();
          final alternate = find.byKey(const ValueKey('model-cloud:alternate'));
          await tester.ensureVisible(alternate);
          await tester.pumpAndSettle();
          expect(alternate.hitTestable(), findsOneWidget);
          await tester.tap(alternate);
          await tester.pumpAndSettle();
          expect(controller.selectedModel!.reference, 'cloud:alternate');
          expect(controller.reasoningEffort, 'max');
          expect(modelsPage.value, false);
          expect(find.byType(EffortSlider), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
