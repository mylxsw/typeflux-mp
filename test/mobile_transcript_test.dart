import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:typeflux_app/chat/chat_controller.dart';
import 'package:typeflux_app/chat/conversation.dart';
import 'package:typeflux_app/core/api.dart';
import 'package:typeflux_app/ui/message_details.dart';
import 'package:typeflux_app/ui/mobile_transcript.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'support/fakes.dart';

Map<String, dynamic> toolCall(String id, String name) => {
  'id': id,
  'function': {'name': name, 'arguments': '{"query":"跨端聊天设计"}'},
};

Map<String, dynamic> toolMessage(
  String id,
  String callId, {
  String runId = 'run',
}) => {
  'id': id,
  'role': 'assistant',
  'run_id': runId,
  'text': '',
  'tool_calls': [toolCall(callId, 'web_search')],
};

Conversation fixture({bool active = false}) => Conversation({
  'id': 'conversation',
  'revision': 4,
  'run': {
    'id': 'run',
    'status': active ? 'running' : 'completed',
    'model_ref': 'cloud:model',
  },
  'messages': [
    {'id': 'question', 'role': 'user', 'text': '怎么让手机和电脑上的聊天体验更一致？'},
    {
      ...toolMessage('step', 'search'),
      'reasoning': '先对照高频入口。',
      'reasoning_milliseconds': 4000,
    },
    {
      'id': 'result',
      'role': 'tool',
      'tool_call_id': 'search',
      'text': '找到资料',
      'is_error': false,
    },
    if (!active)
      {
        'id': 'answer',
        'role': 'assistant',
        'run_id': 'run',
        'text': '先统一高频操作，让每次切换设备都能自然接上。\n\n| 组件名称 | macOS 操作 | iOS 操作 |\n| --- | --- | --- |\n| 推理选择 | 液体滑杆 | 扩大触摸区域 |',
      },
  ],
  'usage': {
    'runs': {
      'run': {
        'microcredits': 1200000,
        'calls': 1,
        'pending': 0,
        'missing': 0,
        'estimated': 0,
        'external': 0,
      },
    },
  },
});

void main() {
  test(
    'queued messages are visible once and disappear when committed to history',
    () {
      final entries = transcriptEntries(
        fixture(),
        queued: [
          {'id': 'queued', 'text': '追加问题'},
          {'id': 'queued', 'text': '重复队列'},
          {'id': 'question', 'text': '已经在历史中'},
        ],
      );
      final queued = entries.where((entry) => entry.message?['queued'] == true);
      expect(queued, hasLength(1));
      expect(queued.single.message!['text'], '追加问题');
    },
  );
  test(
    'groups read-only tool activity without presenting results as answers',
    () {
      final conversation = fixture();
      final entries = transcriptEntries(conversation);
      expect(entries.length, 3);
      expect(entries[1].isActivity, isTrue);
      expect(entries[1].activity.single['id'], 'step');
      expect(entries.last.message!['id'], 'answer');
    },
  );

  test('preview tools and answer remain separate while both stream', () {
    final entries = transcriptEntries(
      Conversation({
        'id': 'stream',
        'messages': <Map<String, dynamic>>[],
        'run': {
          'id': 'run',
          'status': 'running',
          'assistant_id': 'live',
          'preview': 'The answer so far',
          'reasoning': 'Working through the sources',
          'preview_tools': [toolCall('search', 'web_search')],
        },
      }),
    );
    expect(entries, hasLength(2));
    expect(entries.first.isActivity, isTrue);
    expect(entries.first.activity.single['text'], '');
    expect(entries.last.message!['text'], 'The answer so far');
    expect(entries.last.message!['preview'], isTrue);
  });

  test('progress preview keeps real reasoning and does not duplicate persisted messages', () {
    final conversation = Conversation({
      ...fixture(active: true).json,
      'run': {
        'id': 'run',
        'status': 'running',
        'assistant_id': 'live',
        'preview': '正在整理。',
        'reasoning': '对照两种操作。',
        'reasoning_milliseconds': 1800,
      },
    });
    final entries = transcriptEntries(conversation);
    expect(entries.last.message!['text'], '正在整理。');
    expect(entries.last.message!['reasoning'], '对照两种操作。');
    expect(entries.last.message!['preview'], isTrue);
    final persisted = Conversation({
      ...conversation.json,
      'messages': [
        ...conversation.messages,
        {'id': 'live', 'role': 'assistant', 'text': '已整理。'},
      ],
    });
    expect(
      transcriptEntries(persisted).where((e) => e.message?['id'] == 'live'),
      hasLength(1),
    );
  });

  test('billing requires a complete receipt and stays on the last answer of its run', () {
    final conversation = fixture();
    final message = conversation.messages.last;
    expect(answerCredits(message, conversation), '1.2');
    for (final key in ['pending', 'missing', 'estimated', 'external']) {
      final uncertain = Conversation({
        ...conversation.json,
        'usage': {
          'runs': {
            'run': {
              'microcredits': 1200000,
              'calls': 1,
              'pending': 0,
              'missing': 0,
              'estimated': 0,
              'external': 0,
              key: 1,
            },
          },
        },
      });
      expect(answerCredits(message, uncertain), isNull);
    }
    expect(answerCredits({...message, 'id': 'earlier'}, conversation), isNull);
    expect(
      answerModelLabel(message, conversation, [
        {'id': 'model', 'name': 'Actual model'},
      ]),
      'Actual model',
    );
    expect(
      answerModelLabel(
        {...message, 'run_id': 'old-run'},
        conversation,
        [
          {'id': 'model', 'name': 'Current model'},
        ],
      ),
      isNull,
    );
  });

  Future<void> mount(
    WidgetTester tester,
    _TestChat chat, {
    ValueChanged<String>? onQuote,
    Future<void> Function(String text)? onShare,
    double scale = 1,
  }) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: MobileTranscript(
              controller: chat,
              scrollController: scroll,
              onQuote: onQuote ?? (_) {},
              onShare: onShare,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  _TestChat makeChat() {
    final api = TypefluxApi(
      origin: Uri.parse('https://example.com'),
      vault: MemoryVault(),
      client: MockClient((_) async => http.Response('{}', 500)),
    );
    final chat = _TestChat(api)
      ..current = fixture()
      ..models = [
        {'id': 'model', 'name': 'Actual model'},
      ];
    addTearDown(() {
      chat.dispose();
      api.close();
    });
    return chat;
  }

  testWidgets(
    'reasoning and completed activity disclose; share and regenerate use the answer',
    (tester) async {
      final chat = makeChat();
      String? shared;
      await mount(tester, chat, onShare: (value) async => shared = value);
      expect(tester.takeException(), isNull);
      expect(find.text('先对照高频入口。'), findsNothing);
      expect(find.text('已完成'), findsNothing);
      await tester.tap(find.text('思考了 4 秒'));
      await tester.pump();
      expect(find.text('先对照高频入口。'), findsOneWidget);
      await tester.tap(find.text('调用了 1 次工具'));
      await tester.pump();
      expect(find.text('已完成'), findsOneWidget);
      expect(find.byTooltip('引用追问'), findsNothing);
      await tester.ensureVisible(find.byTooltip('分享'));
      await tester.tap(find.byTooltip('分享'));
      expect(shared, chat.current!.messages.last['text']);
      await tester.tap(find.byTooltip('重新生成'));
      expect(chat.action, 'regenerate');
      expect(find.text('Actual model · 1.2 credits'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('running activity starts expanded and cannot regenerate', (
    tester,
  ) async {
    final active = fixture(active: true);
    final chat = makeChat()
      ..current = Conversation({
        ...active.json,
        'messages': active.messages
            .where((message) => message['role'] != 'tool')
            .toList(),
      });
    await mount(tester, chat);
    expect(find.text('正在调用工具'), findsOneWidget);
    expect(find.text('执行中'), findsOneWidget);
    expect(find.byTooltip('重新生成'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('narrow large text and Markdown tables do not overflow', (
    tester,
  ) async {
    final chat = makeChat();
    await mount(tester, chat, scale: 1.5);
    expect(tester.takeException(), isNull);
    expect(find.byType(Table), findsOneWidget);
    final horizontal = tester
        .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .where((w) => w.scrollDirection == Axis.horizontal);
    expect(horizontal, isNotEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'citation badge stays inline with its sentence and opens its source',
    (tester) async {
      final original = UrlLauncherPlatform.instance, launcher = _TestLauncher();
      UrlLauncherPlatform.instance = launcher;
      addTearDown(() => UrlLauncherPlatform.instance = original);
      final chat = makeChat()
        ..current = Conversation({
          'id': 'cite',
          'messages': [
            {
              'id': 'answer',
              'role': 'assistant',
              'text': 'A sentence[1](https://example.com/citation)',
            },
          ],
        });
      await mount(tester, chat);
      final sentence = tester.getRect(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('A sentence'),
        ),
      );
      final citation = find.byKey(
        const ValueKey('citation-https://example.com/citation'),
      );
      final badge = tester.getRect(citation);
      expect(badge.center.dy, greaterThan(sentence.top));
      expect(badge.center.dy, lessThan(sentence.bottom));
      expect(badge.left, greaterThan(sentence.left + 30));
      await tester.tap(citation);
      await tester.pump();
      expect(launcher.urls, ['https://example.com/citation']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'short tables fill the reading width and preserve Markdown cell links',
    (tester) async {
      final original = UrlLauncherPlatform.instance, launcher = _TestLauncher();
      UrlLauncherPlatform.instance = launcher;
      addTearDown(() => UrlLauncherPlatform.instance = original);
      final chat = makeChat()
        ..current = Conversation({
          'id': 'table',
          'messages': [
            {
              'id': 'answer',
              'role': 'assistant',
              'text': '| A | B |\n| --- | --- |\n| [link](https://example.com/table) | **ok** |',
            },
          ],
        });
      await mount(tester, chat);
      expect(
        tester.getSize(find.byType(Table)).width,
        greaterThanOrEqualTo(276),
      );
      await tester.tap(find.text('link', findRichText: true));
      await tester.pump();
      expect(launcher.urls, ['https://example.com/table']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'completed tools collapse while the same run streams its answer',
    (tester) async {
      final active = fixture(active: true);
      final chat = makeChat()
        ..current = Conversation({
          ...active.json,
          'run': {...active.run!, 'preview': '正在整理回答。', 'assistant_id': 'live'},
        });
      await mount(tester, chat);
      expect(find.text('正在调用工具'), findsNothing);
      expect(find.text('调用了 1 次工具'), findsOneWidget);
      expect(find.text('已完成'), findsNothing);
      expect(
        find.textContaining('正在整理回答。', findRichText: true),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('streaming-caret')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'code cards keep language, copy exact source, and scroll horizontally',
    (tester) async {
      final chat = makeChat()
        ..current = Conversation({
          'id': 'code',
          'messages': [
            {
              'id': 'code-answer',
              'role': 'assistant',
              'text': '```swift\nlet number = 42\n```',
            },
          ],
        });
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await mount(tester, chat);
      expect(find.text('swift'), findsOneWidget);
      await tester.tap(find.byTooltip('复制代码'));
      await tester.pump();
      expect(copied, 'let number = 42');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('queued prompt offers resume only after the previous run stops', (
    tester,
  ) async {
    final chat = makeChat()
      ..queued = [
        {'id': 'queued', 'text': '追加问题'},
      ];
    await mount(tester, chat);
    expect(find.text('已排队'), findsOneWidget);
    await tester.ensureVisible(find.text('继续发送'));
    await tester.tap(find.text('继续发送'));
    expect(chat.retried, 'queued');
    chat.current = fixture(active: true);
    await mount(tester, chat);
    expect(find.text('已排队'), findsOneWidget);
    expect(find.text('继续发送'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final scheme in ['https', 'http']) {
    testWidgets('$scheme link opens externally only when tapped', (
      tester,
    ) async {
      final original = UrlLauncherPlatform.instance;
      final launcher = _TestLauncher();
      UrlLauncherPlatform.instance = launcher;
      addTearDown(() => UrlLauncherPlatform.instance = original);
      final chat = makeChat()
        ..current = Conversation({
          'id': 'links',
          'messages': [
            {
              'id': 'answer',
              'role': 'assistant',
              'text': '[参考文档]($scheme://example.com/docs)',
            },
          ],
        });
      await mount(tester, chat);
      expect(launcher.urls, isEmpty);
      await tester.tap(find.text('参考文档', findRichText: true));
      await tester.pump();
      expect(launcher.urls, ['$scheme://example.com/docs']);
      expect(launcher.mode, PreferredLaunchMode.externalApplication);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'non-web, malformed, and credential URLs never reach the launcher',
    (tester) async {
      final original = UrlLauncherPlatform.instance;
      final launcher = _TestLauncher();
      UrlLauncherPlatform.instance = launcher;
      addTearDown(() => UrlLauncherPlatform.instance = original);
      final chat = makeChat()
        ..current = Conversation({
          'id': 'links',
          'messages': [
            {
              'id': 'answer',
              'role': 'assistant',
              'text': '[参考文档](https://example.com)',
            },
          ],
        });
      await mount(tester, chat);
      final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      for (final url in [
        'file:///private/document',
        'javascript:alert(1)',
        'data:text/html,test',
        'https://',
        'https://user:password@example.com',
        'tel:1234',
      ]) {
        markdown.onTapLink!('test', url, '');
        await tester.pump();
      }
      expect(launcher.urls, isEmpty);
      expect(find.text('仅支持打开网页链接。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final throwsError in [false, true]) {
    testWidgets(
      'failed launch provides copy fallback (exception=$throwsError)',
      (tester) async {
        final original = UrlLauncherPlatform.instance;
        final launcher = _TestLauncher()
          ..succeeds = false
          ..throwsError = throwsError;
        UrlLauncherPlatform.instance = launcher;
        addTearDown(() => UrlLauncherPlatform.instance = original);
        String? copied;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.setData') {
            copied = call.arguments['text'] as String;
          }
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
        final chat = makeChat()
          ..current = Conversation({
            'id': 'links',
            'messages': [
              {
                'id': 'answer',
                'role': 'assistant',
                'text': '[参考文档](https://example.com/docs)',
              },
            ],
          });
        await mount(tester, chat);
        await tester.tap(find.text('参考文档', findRichText: true));
        await tester.pumpAndSettle();
        expect(find.text('无法打开链接，可复制后在浏览器中访问。'), findsOneWidget);
        await tester.tap(find.text('复制链接'));
        await tester.pumpAndSettle();
        expect(copied, 'https://example.com/docs');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'model-provided images need a tap and local image paths are not loaded',
    (tester) async {
      final chat = makeChat()
        ..current = Conversation({
          'id': 'images',
          'messages': [
            {
              'id': 'answer',
              'role': 'assistant',
              'text': '![远程图片](https://example.com/image.png)\n\n![本地图片](file:///private/image.png)',
            },
          ],
        });
      await mount(tester, chat);
      expect(find.text('查看图片 · 远程图片'), findsOneWidget);
      expect(find.text('本地图片'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _TestChat extends ChatController {
  _TestChat(TypefluxApi api) : super(api, MemoryCache());
  String? action;
  List<Map<String, dynamic>> queued = [];
  String? retried;
  @override
  List<Map<String, dynamic>> get queuedMessages => queued;
  @override
  Future<void> retryQueuedMessage(String id) async => retried = id;
  @override
  Future<void> runAction(String action) async => this.action = action;
}

class _TestLauncher extends UrlLauncherPlatform {
  final urls = <String>[];
  PreferredLaunchMode? mode;
  bool succeeds = true;
  bool throwsError = false;
  @override
  LinkDelegate? get linkDelegate => null;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    urls.add(url);
    mode = options.mode;
    if (throwsError) throw PlatformException(code: 'FAILED');
    return succeeds;
  }
}
