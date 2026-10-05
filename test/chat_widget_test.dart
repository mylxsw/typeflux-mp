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
import 'package:typeflux_app/chat/chat_controller.dart';
import 'package:typeflux_app/chat/conversation.dart';
import 'package:typeflux_app/core/api.dart';
import 'package:typeflux_app/core/session.dart';
import 'package:typeflux_app/ui/chat_page.dart';
import 'package:typeflux_app/ui/theme.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.record/messages'),
          (_) async => null,
        );
  });
  for (final config in [
    (320.0, TargetPlatform.iOS),
    (390.0, TargetPlatform.iOS),
    (1200.0, TargetPlatform.windows),
    (1000.0, TargetPlatform.android),
  ]) {
    final width = config.$1;
    final desktop = config.$2 == TargetPlatform.windows;
    testWidgets('chat renders and accepts a draft at $width', (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final output = Platform.environment['TYPEFLUX_RENDER_DIR'];
      if (output != null) {
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = true);
        await tester.runAsync(() async {
          final font = FontLoader('PreviewFont')
            ..addFont(
              File(
                Platform.environment['TYPEFLUX_PREVIEW_FONT'] ??
                    '/System/Library/Fonts/STHeiti Light.ttc',
              ).readAsBytes().then(ByteData.sublistView),
            );
          await font.load();
          final icons = FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await icons.load();
        });
      }
      final api = TypefluxApi(
        origin: Uri.parse('https://example.com'),
        vault: MemoryVault(),
        client: MockClient(
          (request) async =>
              http.Response(jsonEncode({'code': 'OK', 'data': []}), 200),
        ),
      )..session = const Session('test-access', 'test-refresh', 9999999999);
      final chat = ChatController(api, MemoryCache())
        ..accountId = 'fixture'
        ..hasMore = false;
      chat.models = [
        {'id': 'default', 'name': 'Typeflux Cloud', 'vision': true},
      ];
      chat.current = Conversation({
        'id': 'fixture-chat',
        'title': '把想法整理成计划',
        'revision': 3,
        'messages': [
          {'id': 'u', 'role': 'user', 'text': '我想开始一个新项目，帮我理清第一步。'},
          {
            'id': 'a',
            'role': 'assistant',
            'text': '可以。先把目标写成一句话，再选一个今天就能完成的小步骤。\n\n**我们先从这三个问题开始：**\n\n1. 你想解决什么问题？\n2. 谁会用到它？\n3. 什么结果能证明它有用？',
          },
        ],
      });
      chat.conversations = [
        {'id': 'fixture-chat', 'title': '把想法整理成计划'},
        {'id': 'other', 'title': '周末的出行安排'},
      ];
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: typefluxTheme(
            Brightness.light,
            fontFamily: output == null ? null : 'PreviewFont',
          ).copyWith(platform: config.$2),
          home: RepaintBoundary(
            key: key,
            child: ChatPage(controller: chat, onLogout: () async {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('语音输入'), findsOneWidget);
      await tester.enterText(
        find.byKey(ValueKey(desktop ? 'desktop-composer' : 'message-draft')),
        '帮我列一个简单的行动清单',
      );
      await tester.pump();
      expect(find.text('帮我列一个简单的行动清单'), findsOneWidget);
      if (output != null && width != 320) {
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/chat-${width.toInt()}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      chat.dispose();
      api.close();
      debugDisableShadows = true;
      expect(tester.takeException(), isNull);
    });
  }
}
