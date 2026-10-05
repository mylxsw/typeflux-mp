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
import 'package:package_info_plus/package_info_plus.dart';
import 'package:typeflux_app/chat/chat_controller.dart';
import 'package:typeflux_app/chat/conversation.dart';
import 'package:typeflux_app/core/api.dart';
import 'package:typeflux_app/core/session.dart';
import 'package:typeflux_app/ui/settings_page.dart';
import 'package:typeflux_app/ui/mobile_chat.dart';
import 'package:typeflux_app/ui/theme.dart';

import 'mobile_design_test.dart' as fixtures;
import 'support/fakes.dart';

// Review captures use the real pages with synthetic, offline account data.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PackageInfo.setMockInitialValues(
    appName: 'Typeflux',
    packageName: 'app.typeflux',
    version: '0.1.0',
    buildNumber: '1',
    buildSignature: 'fixture',
  );
  final output = Platform.environment['TYPEFLUX_RENDER_DIR'];
  for (final state in [
    'account-light',
    'account-dark',
    'model-settings',
    'reasoning-settings',
    'chat-light',
    'chat-dark',
    'chat-reasoning',
    'chat-tools',
    'chat-followup',
    'chat-multiturn',
    'history-search',
  ]) {
    testWidgets('expanded review screenshot $state', (tester) async {
      tester.view.physicalSize = const Size(392, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => debugDisableShadows = true);
      if (output != null) {
        debugDisableShadows = false;
        await tester.runAsync(() async {
          await (FontLoader('PreviewFont')..addFont(
                File(
                  Platform.environment['TYPEFLUX_PREVIEW_FONT'] ??
                      '/System/Library/Fonts/STHeiti Light.ttc',
                ).readAsBytes().then(ByteData.sublistView),
              ))
              .load();
          await (FontLoader('PreviewLatin')..addFont(
                File('/System/Library/Fonts/SFNS.ttf')
                    .readAsBytes()
                    .then(ByteData.sublistView),
              ))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
      }
      final api =
          TypefluxApi(
              origin: Uri.parse('https://example.com'),
              vault: MemoryVault(),
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
                  '/api/v1/ask/conversations' => <Object>[],
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
        ..accountId = 'review-account'
        ..accountName = 'Demir Von'
        ..accountEmail = 'demir@example.com'
        ..hasMore = false
        ..models = fixtures.catalog
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
      chat.current = fixtures.answer(running: state == 'chat-followup');
      if (state == 'chat-followup') {
        chat.modelRef = 'cloud:sonnet';
        chat.reasoningEffort = 'high';
      }
      if (state == 'chat-multiturn') {
        chat.current = Conversation({
          'id': 'chat',
          'title': '安排一个轻松的周末',
          'revision': 5,
          'model_ref': 'cloud:default',
          'run': {'id': 'last-run', 'status': 'completed'},
          'messages': [
            {'id': 'q1', 'role': 'user', 'text': '想安排一个轻松的周末，不想太赶。'},
            {
              'id': 'a1',
              'role': 'assistant',
              'text': '可以把一天分成两个小安排，中间留出休息时间。\n\n- 上午去附近散步，找一家喜欢的咖啡店。\n- 下午看展或读书，晚上在家做顿简单的饭。\n\n你更想待在室内，还是出去走走？',
            },
            {'id': 'q2', 'role': 'user', 'text': '出去走走吧，但下午可能下雨。'},
            {
              'id': 'a2',
              'role': 'assistant',
              'run_id': 'last-run',
              'text': '那就把户外活动放在上午，下午留一个室内备选。\n\n**上午**：公园散步一小时，再慢慢吃午餐。\n\n**下午**：去书店或美术馆；如果累了，直接回家休息也很好。\n\n不需要把每个时间段都排满。',
            },
          ],
        });
      }
      final today = DateTime.now();
      chat.conversations = [
        {
          'id': 'chat',
          'title': '让跨端聊天体验更一致',
          'updated_at': today.toIso8601String(),
        },
        {
          'id': 'research',
          'title': '整理产品调研资料',
          'updated_at': today.toIso8601String(),
        },
        {
          'id': 'weekend',
          'title': '安排一个轻松的周末',
          'updated_at': today
              .subtract(const Duration(days: 1))
              .toIso8601String(),
        },
        {
          'id': 'swift',
          'title': '解释 Swift 并发中的 actor 重入',
          'updated_at': today
              .subtract(const Duration(days: 5))
              .toIso8601String(),
        },
      ];
      final composer = TextEditingController();
      final scroll = ScrollController();
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('zh'),
            supportedLocales: const [Locale('zh')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: typefluxTheme(
              state.endsWith('dark') ? Brightness.dark : Brightness.light,
              fontFamily: output == null ? null : 'PreviewLatin',
              fontFamilyFallback: output == null ? null : ['PreviewFont'],
            ).copyWith(platform: TargetPlatform.iOS),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: const EdgeInsets.only(top: 54, bottom: 21),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: AnimatedBuilder(
              animation: chat,
              builder: (context, _) => MobileChat(
                controller: chat,
                composer: composer,
                scrollController: scroll,
                attachments: const [],
                onAttach: () async {},
                onSend: () async {},
                onRemove: (_) {},
                onLogout: () async {},
                onDelete: () async {},
                onRetry: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (state.startsWith('account') || state == 'history-search') {
        await tester.tap(find.byTooltip('打开侧栏'));
        await tester.pumpAndSettle();
        if (state == 'history-search') {
          await tester.enterText(
            find.byKey(const ValueKey('history-search')),
            'Swift',
          );
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          expect(find.text('解释 Swift 并发中的 actor 重入'), findsOneWidget);
        } else {
          await tester.tap(find.byKey(const ValueKey('history-account')));
          await tester.pumpAndSettle();
          expect(find.byType(SettingsPage), findsOneWidget);
          expect(find.text('demir@example.com'), findsOneWidget);
          expect(find.text('316 / 500'), findsOneWidget);
          expect(find.text('0.1.0 (1)'), findsOneWidget);
          expect(find.text('退出登录'), findsOneWidget);
        }
      }
      if (state.endsWith('settings')) {
        chat.changeModel('cloud:sonnet');
        chat.setReasoningEffort('high');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('model-trigger')));
        await tester.pumpAndSettle();
        if (state == 'model-settings') {
          await tester.tap(find.bySemanticsLabel(RegExp('更换模型')));
          await tester.pumpAndSettle();
          expect(find.text('模型和价格由 Typeflux Cloud 提供'), findsOneWidget);
        } else {
          expect(find.text('思考更充分，适合复杂问题'), findsOneWidget);
        }
      }
      if (state == 'chat-reasoning') {
        await tester.tap(find.text('思考了 4 秒'));
        await tester.pumpAndSettle();
        expect(find.text('对照资料，再整理可执行的建议。'), findsOneWidget);
      }
      if (state == 'chat-tools') {
        await tester.tap(find.text('调用了 2 次工具'));
        await tester.pumpAndSettle();
        expect(find.textContaining('聊天离线同步方案'), findsOneWidget);
      }
      if (state == 'chat-followup') {
        composer.text = '再补充一下手机端的操作建议。';
        await tester.pumpAndSettle();
        expect(find.byTooltip('停止生成'), findsOneWidget);
        expect(find.byTooltip('发送'), findsNothing);
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
          await File('$output/$state.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      chat.dispose();
      api.close();
      composer.dispose();
      scroll.dispose();
      debugDisableShadows = true;
    });
  }
}
