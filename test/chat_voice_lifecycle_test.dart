import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:typeflux_app/chat/chat_controller.dart';
import 'package:typeflux_app/core/api.dart';
import 'package:typeflux_app/ui/chat_page.dart';
import 'package:typeflux_app/ui/mobile_chat.dart';
import 'package:typeflux_app/ui/theme.dart';
import 'package:typeflux_app/voice/voice_controller.dart';
import 'package:typeflux_app/voice/windows_bridge.dart';

import 'support/fakes.dart';

class TrackingChatController extends ChatController {
  TrackingChatController(TypefluxApi api) : super(api, MemoryCache());
  int initializeCalls = 0;

  @override
  Future<void> initialize() async {
    initializeCalls++;
    newConversation();
  }
}

class FakeVoiceController extends VoiceController {
  FakeVoiceController(super.api);
  bool failStart = false;
  int startCalls = 0, stopCalls = 0, cancelCalls = 0, disposeCalls = 0;

  @override
  Future<void> start({String scenario = 'ask-anything'}) async {
    startCalls++;
    error = failStart ? 'MICROPHONE_DENIED' : null;
    phase = failStart ? VoicePhase.failed : VoicePhase.recording;
    notifyListeners();
  }

  @override
  Future<String?> stop() async {
    stopCalls++;
    phase = VoicePhase.idle;
    notifyListeners();
    return transcript.text;
  }

  @override
  Future<void> cancel({bool failed = false}) async {
    cancelCalls++;
    phase = failed ? VoicePhase.failed : VoicePhase.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    disposeCalls++;
    super.dispose();
  }
}

class FakeWindowsBridge extends WindowsBridge {
  FakeWindowsBridge({this.isWindows = false});
  final bool isWindows;
  Future<void> Function()? toggle;
  final inserted = <String>[];
  int disableCalls = 0;

  @override
  bool get available => isWindows;

  @override
  Future<void> enable(Future<void> Function() action) async {
    toggle = action;
  }

  @override
  Future<void> disable() async {
    disableCalls++;
    toggle = null;
  }

  @override
  Future<void> reset() async {}

  @override
  Future<void> showStatus(String text) async {}

  @override
  Future<bool> insert(String text) async {
    inserted.add(text);
    return true;
  }
}

Future<
  ({
    TrackingChatController chat,
    FakeVoiceController voice,
    FakeWindowsBridge bridge,
  })
>
showChat(
  WidgetTester tester, {
  bool desktop = false,
  bool failStart = false,
}) async {
  tester.view.physicalSize = Size(desktop ? 1200 : 392, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final api = TypefluxApi(
    origin: Uri.parse('https://example.com'),
    vault: MemoryVault(),
    client: MockClient(
      (_) async => fail('No remote calls expected in voice lifecycle tests.'),
    ),
  );
  final chat = TrackingChatController(api)
    ..accountId = 'fixture-account'
    ..hasMore = false
    ..models = [
      {'id': 'default', 'name': 'Fixture model', 'vision': true},
    ];
  chat.newConversation();
  final voice = FakeVoiceController(api)..failStart = failStart;
  final bridge = FakeWindowsBridge(isWindows: desktop);
  addTearDown(chat.dispose);
  addTearDown(api.close);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: typefluxTheme(Brightness.light).copyWith(
        platform: desktop ? TargetPlatform.windows : TargetPlatform.android,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: ChatPage(
        controller: chat,
        voiceController: voice,
        windowsBridge: bridge,
        onLogout: () async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (chat: chat, voice: voice, bridge: bridge);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? copiedText;
  setUp(() {
    copiedText = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (call) async {
        expectSync(call.method, isIn(['create', 'stop', 'dispose']));
        return null;
      },
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
  });

  testWidgets(
    'retrying a local voice failure preserves the draft and does not reload the account',
    (tester) async {
      final fixture = await showChat(tester, failStart: true);
      await tester.widget<MobileChat>(find.byType(MobileChat)).onVoice!();
      await tester.pumpAndSettle();
      expect(fixture.voice.phase, VoicePhase.failed);
      final conversation = fixture.chat.current!.id;
      await tester.enterText(
        find.byKey(const ValueKey('message-draft')),
        '请保留这段未发送的草稿',
      );
      await tester.pump();
      tester.widget<MobileChat>(find.byType(MobileChat)).onRetry();
      await tester.pumpAndSettle();
      expect(fixture.chat.initializeCalls, 0);
      expect(fixture.chat.current!.id, conversation);
      expect(
        tester.widget<MobileChat>(find.byType(MobileChat)).composer.text,
        '请保留这段未发送的草稿',
      );
      expect(fixture.voice.error, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'background interruption keeps recognized speech available to copy',
    (tester) async {
      final fixture = await showChat(tester);
      await tester.widget<MobileChat>(find.byType(MobileChat)).onVoice!();
      fixture.voice.transcript.committed = '已确认的内容，';
      fixture.voice.transcript.partial = '尚未说完的后半句';
      fixture.voice.notifyListeners();
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      try {
        await tester.pump();
        expect(fixture.voice.phase, VoicePhase.failed);
        expect(fixture.voice.error, 'ASR_INTERRUPTED');
      } finally {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await tester.pumpAndSettle();
      const recovered = '已确认的内容，尚未说完的后半句';
      expect(find.text(recovered), findsOneWidget);
      final copy = find.text('复制已识别的文字');
      await tester.ensureVisible(copy);
      await tester.tap(copy);
      await tester.pumpAndSettle();
      expect(copiedText, recovered);
      expect(
        tester.widget<MobileChat>(find.byType(MobileChat)).composer.text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'disposing during the Windows insertion delay never inserts into another app',
    (tester) async {
      final fixture = await showChat(tester, desktop: true);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(fixture.bridge.toggle, isNotNull);
      await fixture.bridge.toggle!();
      fixture.voice.transcript.committed = '不应在退出后插入的文本';
      await tester.pumpAndSettle();
      expect(fixture.voice.phase, VoicePhase.recording);
      final stopping = fixture.bridge.toggle!();
      await tester.pump();
      expect(fixture.voice.stopCalls, 1);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 250));
      await stopping;
      expect(fixture.voice.disposeCalls, 1);
      expect(fixture.bridge.inserted, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
