import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:typeflux_app/chat/chat_controller.dart';
import 'package:typeflux_app/chat/conversation.dart';
import 'package:typeflux_app/core/api.dart';
import 'package:typeflux_app/ui/mobile_chat.dart';
import 'package:typeflux_app/ui/model_picker.dart';
import 'package:typeflux_app/ui/theme.dart';

import 'support/fakes.dart';

// Offline catalog and conversations match the supplied design's illustrative data.
const catalog = [
  {
    'id': 'sonnet',
    'name': 'Claude Sonnet 5.5',
    'vision': true,
    'capabilities': {'reasoning': true},
    'reasoning_efforts': ['low', 'medium', 'high', 'xhigh', 'max'],
    'context_window_tokens': 1000000,
    'max_output_tokens': 64000,
    'pricing': {'multiplier': '3'},
  },
  {
    'id': 'default',
    'name': 'MiniMax M3',
    'vision': true,
    'capabilities': {'reasoning': true},
    'reasoning_efforts': ['low', 'medium', 'high'],
    'context_window_tokens': 1000000,
    'max_output_tokens': 128000,
    'pricing': {'multiplier': '1'},
  },
  {
    'id': 'gpt',
    'name': 'GPT-5.1',
    'vision': true,
    'capabilities': {'reasoning': true},
    'reasoning_efforts': ['low', 'medium', 'high', 'xhigh'],
    'context_window_tokens': 400000,
    'max_output_tokens': 128000,
    'pricing': {'multiplier': '2'},
  },
  {
    'id': 'deepseek',
    'name': 'DeepSeek V3.2',
    'vision': false,
    'capabilities': {'reasoning': true},
    'reasoning_efforts': ['low', 'medium', 'high'],
    'context_window_tokens': 128000,
    'max_output_tokens': 32000,
    'pricing': {'multiplier': '0.5'},
  },
  {
    'id': 'plain',
    'name': '标准对话模型',
    'vision': false,
    'capabilities': {'reasoning': false},
    'context_window_tokens': 128000,
    'max_output_tokens': 16000,
    'pricing': {'multiplier': '1'},
  },
];

// Illustrative catalog exactly as authored in the final v4 board.
const v4Catalog = [
  {
    'id': 'default',
    'name': 'MiniMax M3',
    'vision': true,
    'capabilities': {'reasoning': true},
    'reasoning_efforts': ['low', 'medium', 'high', 'max'],
    'context_window_tokens': 1000000,
    'max_output_tokens': 64000,
    'pricing': {'multiplier': '1'},
  },
  {
    'id': 'sonnet',
    'name': 'Claude Sonnet',
    'vision': true,
    'capabilities': {'reasoning': true},
    'reasoning_efforts': ['low', 'medium', 'high', 'max'],
    'context_window_tokens': 200000,
    'max_output_tokens': 64000,
    'pricing': {'multiplier': '3'},
  },
  {
    'id': 'gpt',
    'name': 'GPT-5',
    'vision': true,
    'capabilities': {'reasoning': true},
    'reasoning_efforts': ['low', 'medium', 'high', 'max'],
    'context_window_tokens': 400000,
    'max_output_tokens': 128000,
    'pricing': {'multiplier': '4'},
  },
  {
    'id': 'deepseek',
    'name': 'DeepSeek V4',
    'vision': false,
    'capabilities': {'reasoning': true},
    'reasoning_efforts': ['low', 'medium', 'high'],
    'context_window_tokens': 128000,
    'max_output_tokens': 32000,
    'pricing': {'multiplier': '0.5'},
  },
];

Conversation answer({bool running = false}) => Conversation({
  'id': 'chat',
  'title': running ? '最近值得看的科幻片' : '离线同步怎么做',
  'revision': 3,
  'model_ref': 'cloud:default',
  'run': {
    'id': 'run',
    'status': running ? 'running' : 'completed',
    'steps': 2,
    if (running) ...{
      'assistant_id': 'live',
      'model_ref': 'cloud:default',
      'reasoning': '继续核对口碑和上映时间。',
      'preview': '按近三个月的口碑，先挑出两部：\n\n- **《星际回声》**：设定扎实，结尾有力[1](https://example.com/film)\n- **《零点轨道》**：动作场面很足，节奏',
    },
  },
  'usage': {
    'runs': {
      'run': {
        'microcredits': 1200000,
        'calls': 1,
        'pending': running ? 1 : 0,
        'missing': 0,
        'estimated': 0,
        'external': 0,
      },
    },
  },
  'messages': [
    {
      'id': 'q',
      'role': 'user',
      'text': running
          ? '最近有哪些值得看的科幻片？挑三部，说说理由。'
          : '聊天客户端要支持离线阅读，比较一下几种同步方案，给个能落地的建议。',
    },
    {
      'id': 'step1',
      'role': 'assistant',
      'text': '',
      'run_id': 'run',
      'reasoning': '对照资料，再整理可执行的建议。',
      'reasoning_milliseconds': running ? 2000 : 4000,
      'tool_calls': [
        {
          'id': 'search',
          'function': {
            'name': 'web_search',
            'arguments': running
                ? '{"query":"2026 科幻电影 口碑"}'
                : '{"query":"聊天离线同步方案"}',
          },
        },
      ],
    },
    {
      'id': 'r1',
      'role': 'tool',
      'tool_call_id': 'search',
      'is_error': false,
      'text': '找到参考文档',
      if (running) 'result_count': 8,
    },
    {
      'id': 'step2',
      'role': 'assistant',
      'text': '',
      'run_id': 'run',
      'tool_calls': [
        {
          'id': 'read',
          'function': {
            'name': 'web_fetch',
            'arguments': running
                ? '{"url":"https://www.imdb.com"}'
                : '{"url":"https://example.com/design"}',
          },
        },
      ],
    },
    if (!running)
      {
        'id': 'r2',
        'role': 'tool',
        'tool_call_id': 'read',
        'is_error': false,
        'text': '已读取文档',
      },
    if (!running)
      {
        'id': 'answer',
        'role': 'assistant',
        'run_id': 'run',
        'model_ref': 'cloud:default',
        'text': '### 推荐：快照同步\n\n本地缓存 + 服务端版本号。阅读可以完全离线，发送等服务端确认[1](https://example.com/sync)\n\n| 方案 | 离线阅读 | 冲突 |\n| --- | --- | --- |\n| 全量快照 | 支持 | 以版本号为准 |\n| 增量事件 | 支持 | 需排序合并 |\n| CRDT | 支持 | 自动合并 |\n\n先做快照，事件流以后再加。',
      },
  ],
});

// Offline image drawn from the supplied HTML's authored gradients and ellipses.
Future<String> referenceImage({bool thumbnail = false}) async {
  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder);
  final size = thumbnail ? const Size(54, 54) : const Size(176, 132);
  c.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(size.width, size.height),
        thumbnail
            ? const [Color(0xff7aa2f7), Color(0xffbb9af7), Color(0xfff7768e)]
            : const [Color(0xff5b4636), Color(0xff2e231b)],
        thumbnail ? const [0, .6, 1] : null,
      ),
  );
  if (!thumbnail) {
    c.drawCircle(
      const Offset(88, 71.28),
      53,
      Paint()..color = const Color(0xffe6dfd2),
    );
    c.drawCircle(
      const Offset(88, 71.28),
      46,
      Paint()..color = const Color(0xfff7f3ea),
    );
    c.save();
    c.translate(77, 55);
    c.rotate(-.349);
    c.drawOval(
      const Rect.fromLTWH(-15, -11, 30, 22),
      Paint()..color = const Color(0xff7fb04a),
    );
    c.restore();
    c.drawOval(
      const Rect.fromLTWH(84, 60, 34, 20),
      Paint()..color = const Color(0xffe8c27a),
    );
    c.drawOval(
      const Rect.fromLTWH(70, 72, 22, 16),
      Paint()..color = const Color(0xff5e9a3c),
    );
    c.drawOval(
      const Rect.fromLTWH(96, 46, 16, 12),
      Paint()..color = const Color(0xffd9534f),
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return 'data:image/png;base64,${base64Encode(data!.buffer.asUint8List())}';
}

Conversation photoAnswer(String image) => Conversation({
  'id': 'meal',
  'title': '这道菜清淡吗',
  'revision': 2,
  'model_ref': 'cloud:default',
  'run': {'id': 'meal-run', 'status': 'completed', 'steps': 1},
  'messages': [
    {
      'id': 'photo-question',
      'role': 'user',
      'image': image,
      'text': '这道菜清淡吗？适合减脂吗？',
    },
    {
      'id': 'photo-answer',
      'role': 'assistant',
      'run_id': 'meal-run',
      'reasoning': '根据图片中的食材估算。',
      'reasoning_milliseconds': 3000,
      'text': '看起来是**清炒时蔬配鸡胸**，整体偏清淡：\n\n- 少油快炒，热量大约 350 千卡\n- 蛋白质充足，适合减脂期\n- 酱汁另放，可以控制盐分\n\n```估算\n// 每份\n热量   ≈ 350 kcal\n蛋白质 ≈ 32 g\n```',
    },
  ],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final output = Platform.environment['TYPEFLUX_RENDER_DIR'];
  Future<void> loadFonts(WidgetTester tester) async {
    if (output == null) return;
    await tester.runAsync(() async {
      await (FontLoader('PreviewLatin')..addFont(
            File('/System/Library/Fonts/SFNS.ttf')
                .readAsBytes()
                .then(ByteData.sublistView),
          ))
          .load();
      await (FontLoader('monospace')..addFont(
            File('/System/Library/Fonts/Menlo.ttc')
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
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
  }

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    if (output == null) return;
    await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(output).create(recursive: true);
      await File('$output/v4-$name.png')
          .writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final state in [
    'new',
    'effort',
    'models',
    'answer',
    'running',
    'history',
    'dark',
    'unsupported',
    'keyboard',
    'compact',
    'voice-failed',
  ]) {
    testWidgets('v4 $state layout and interaction', (tester) async {
      final compact = state == 'compact';
      tester.view.physicalSize = Size(compact ? 320 : 392, compact ? 700 : 852);
      tester.view.devicePixelRatio = 1;
      if (state == 'keyboard') {
        tester.view.viewInsets = const FakeViewPadding(bottom: 286);
      }
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await loadFonts(tester);
      if (output != null) {
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = true);
      }
      final api = TypefluxApi(
        origin: Uri.parse('https://example.com'),
        vault: MemoryVault(),
        client: MockClient(
          (_) async =>
              http.Response(jsonEncode({'code': 'OK', 'data': []}), 200),
        ),
      );
      final chat = ChatController(api, MemoryCache())
        ..accountId = 'fixture'
        ..accountName = '演示用户'
        ..models = ([
          ...v4Catalog,
          if (['unsupported', 'keyboard'].contains(state)) catalog.last,
        ]).map((m) => Map<String, dynamic>.from(m)).toList()
        ..hasMore = false;
      chat.newConversation();
      if (state == 'keyboard') {
        chat.changeModel('cloud:sonnet');
      }
      if (['effort', 'models', 'answer'].contains(state)) {
        chat.setReasoningEffort('high');
      }
      if (state == 'unsupported') chat.changeModel('cloud:plain');
      if (['answer', 'running', 'keyboard', 'history'].contains(state)) {
        chat.current = answer(running: state == 'running');
      }
      String? meal, thumbnail;
      if (state == 'dark') {
        meal = await tester.runAsync(() => referenceImage());
        thumbnail = await tester.runAsync(
          () => referenceImage(thumbnail: true),
        );
        chat.current = photoAnswer(meal!);
        chat.setReasoningEffort('max');
      }
      final now = DateTime.now();
      chat.conversations = [
        {'id': 'chat', 'title': '离线同步怎么做', 'updated_at': now.toIso8601String()},
        {
          'id': 'other',
          'title': '最近值得看的科幻片',
          'updated_at': now.toIso8601String(),
        },
        {'id': 'hello', 'title': '早上好呀', 'updated_at': now.toIso8601String()},
        {
          'id': 'yesterday',
          'title': '个人产品如何找到第一批用户',
          'updated_at': now.subtract(const Duration(days: 1)).toIso8601String(),
        },
        {
          'id': 'copy',
          'title': '帮我优化一下这段文案',
          'updated_at': now.subtract(const Duration(days: 1)).toIso8601String(),
        },
        {
          'id': 'earlier',
          'title': '解释 Swift 并发中的 actor 重入',
          'updated_at': now.subtract(const Duration(days: 6)).toIso8601String(),
        },
      ];
      var sendCount = 0;
      final composer = TextEditingController(),
          scroll = ScrollController(),
          key = GlobalKey();
      if (state == 'dark') composer.text = '那换成牛肉呢？';
      final attachments = <Map<String, dynamic>>[
        if (state == 'dark')
          {'kind': 'image', 'name': '另一道菜.png', 'image': thumbnail},
        if (state == 'keyboard')
          {
            'kind': 'image',
            'name': '设计截图.png',
            'image': 'data:image/png;base64,',
          },
      ];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: typefluxTheme(
            state == 'dark' ? Brightness.dark : Brightness.light,
            fontFamily: output == null ? null : 'PreviewLatin',
            fontFamilyFallback: output == null ? null : const ['PreviewFont'],
          ),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: EdgeInsets.only(
                  top: 54,
                  bottom: state == 'keyboard' ? 0 : 21,
                ),
                disableAnimations: true,
                textScaler: TextScaler.linear(compact ? 1.6 : 1),
              ),
              child: RepaintBoundary(
                key: key,
                child: AnimatedBuilder(
                  animation: chat,
                  builder: (context, _) => MobileChat(
                    controller: chat,
                    composer: composer,
                    scrollController: scroll,
                    attachments: attachments,
                    onAttach: () async {},
                    onSend: () async {
                      sendCount++;
                    },
                    onRemove: attachments.remove,
                    onLogout: () async {},
                    onDelete: () async {},
                    onRetry: () {},
                    onVoice: () async {},
                    voiceFailed: state == 'voice-failed',
                    voicePartial: state == 'voice-failed'
                        ? '这段识别结果仍然保留，连接失败后可以复制。'
                        : null,
                    onShare: (_) async {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      if ([
        'effort',
        'models',
        'unsupported',
        'keyboard',
        'compact',
      ].contains(state)) {
        await tester.tap(find.byKey(const ValueKey('model-trigger')));
        await tester.pump();
      }
      if (['models', 'keyboard'].contains(state)) {
        await tester.tap(find.bySemanticsLabel(RegExp('更换模型')));
        await tester.pump();
      }
      if (state == 'history') {
        await tester.tap(find.byTooltip('打开侧栏'));
        await tester.pump();
      }
      if (state == 'dark') {
        final images = tester.widgetList<Image>(find.byType(Image)).toList();
        await tester.runAsync(() async {
          for (final image in images) {
            final stream = image.image.resolve(ImageConfiguration.empty),
                done = Completer<void>();
            late ImageStreamListener listener;
            listener = ImageStreamListener(
              (info, _) {
                info.dispose();
                if (!done.isCompleted) done.complete();
              },
              onError: (Object error, StackTrace? stack) {
                if (!done.isCompleted) done.complete();
              },
            );
            stream.addListener(listener);
            await done.future;
            stream.removeListener(listener);
          }
        });
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
      await capture(tester, key, state);
      if (state == 'voice-failed') {
        expect(find.text('这段识别结果仍然保留，连接失败后可以复制。'), findsOneWidget);
        expect(find.text('复制已识别的文字'), findsOneWidget);
        expect(composer.text, isEmpty);
        expect(sendCount, 0);
      }
      if (state == 'running') {
        expect(find.byTooltip('停止生成'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('message-draft')),
          '再比较一下模型入口',
        );
        await tester.pump();
        expect(find.byTooltip('停止生成'), findsOneWidget);
        expect(find.byTooltip('发送'), findsNothing);
        expect(find.byTooltip('语音输入'), findsNothing);
        expect(sendCount, 0);
      }
      if (state == 'answer') {
        expect(find.byTooltip('引用追问'), findsNothing);
        expect(find.byTooltip('分享'), findsOneWidget);
      }
      if (state == 'effort') {
        await tester.tapAt(
          tester.getTopRight(find.byType(EffortSlider)) - const Offset(10, -22),
        );
        await tester.pump();
        expect(chat.reasoningEffort, 'max');
        await tester.tap(find.byTooltip('恢复自动'));
        await tester.pump();
        expect(chat.reasoningEffort, isEmpty);
      }
      if (state == 'models') {
        await tester.tap(find.byKey(const ValueKey('model-cloud:default')));
        await tester.pump();
        expect(chat.selectedModel!.name, 'MiniMax M3');
        expect(find.byType(EffortSlider), findsOneWidget);
      }
      if (state == 'keyboard') {
        final popover = tester.getRect(find.byType(MobileModelPicker));
        final draft = tester.getRect(
          find.byKey(const ValueKey('message-draft')),
        );
        expect(popover.bottom, lessThan(draft.top));
        expect(draft.bottom, lessThan(852 - 286));
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('model-cloud:plain')),
          100,
          scrollable: find
              .descendant(
                of: find.byType(MobileModelPicker),
                matching: find.byType(Scrollable),
              )
              .last,
        );
        final modelList = find.descendant(
          of: find.byType(MobileModelPicker),
          matching: find.byType(ListView),
        );
        await tester.drag(modelList, const Offset(0, -400));
        await tester.pumpAndSettle();
        final row = tester.getRect(
          find.byKey(const ValueKey('model-cloud:plain')),
        );
        expect(tester.getRect(modelList).contains(row.center), isTrue);
        await tester.tapAt(row.center);
        await tester.pump();
        expect(chat.selectedModel!.reference, 'cloud:sonnet');
      }
      if (state == 'unsupported') {
        expect(find.byType(EffortSlider), findsNothing);
      }
      if (state == 'history') {
        await tester.enterText(
          find.byKey(const ValueKey('history-search')),
          'Swift',
        );
        await tester.pump();
        expect(find.text('解释 Swift 并发中的 actor 重入'), findsOneWidget);
        expect(find.text('早上好呀'), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      composer.dispose();
      scroll.dispose();
      chat.dispose();
      api.close();
      debugDisableShadows = true;
    });
  }
}
