import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:typeflux_app/account/account_summary.dart';
import 'package:typeflux_app/chat/chat_controller.dart';
import 'package:typeflux_app/chat/conversation.dart';
import 'package:typeflux_app/core/api.dart';
import 'package:typeflux_app/core/session.dart';
import 'package:typeflux_app/ui/mobile_history.dart';
import 'package:typeflux_app/ui/mobile_design.dart';
import 'package:typeflux_app/ui/settings_page.dart';
import 'package:typeflux_app/ui/theme.dart';

import 'support/fakes.dart';

http.Response _ok(Object? value) =>
    http.Response(jsonEncode({'code': 'OK', 'data': value}), 200);
ChatController _chat(Future<http.Response> Function(http.Request) handler) {
  final api = TypefluxApi(
    origin: Uri.parse('https://example.com'),
    vault: MemoryVault(),
    client: MockClient(handler),
  )..session = const Session('test-access', 'test-refresh', 9999999999);
  return ChatController(api, MemoryCache())
    ..accountId = 'fixture'
    ..accountName = 'Demir Von'
    ..accountEmail = 'demir@example.com';
}

const _billing = {
  'billing_enabled': true,
  'subscription': {'plan_code': 'pro', 'paid': true},
};
const _usage = {
  'credits': {'remaining': 316, 'limit': 500, 'unlimited': false},
  'period_end': '2026-10-31T00:00:00Z',
};
Future<void> _show(WidgetTester tester, Widget body) async {
  tester.view.physicalSize = const Size(392, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: typefluxTheme(Brightness.light),
      home: Scaffold(body: body),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test(
    'account summary uses macOS credit units and preserves missing values',
    () {
      final summary = AccountSummary.fromJson(_billing, _usage);
      expect(summary.plan, 'Pro');
      expect(summary.paid, true);
      expect(summary.remaining, 316);
      expect(summary.limit, 500);
      expect(summary.remainingFraction, .632);
      final unavailable = AccountSummary.fromJson({}, {});
      expect(unavailable.plan, isNull);
      expect(unavailable.hasBalance, false);
      expect(unavailable.remainingFraction, isNull);
      final unlimited = AccountSummary.fromJson({}, {
        'credits': {'unlimited': true},
      });
      expect(unlimited.unlimited, true);
      expect(unlimited.hasBalance, false);
      expect(
        AccountSummary.fromJson(_billing, {
          'credits': {'remaining': 999, 'limit': 500},
        }).remainingFraction,
        1,
      );
    },
  );
  test('summary loads the two existing macOS endpoints', () async {
    final paths = <String>[];
    final chat = _chat((request) async {
      paths.add(request.url.path);
      return _ok(request.url.path.endsWith('subscription') ? _billing : _usage);
    });
    addTearDown(chat.dispose);
    addTearDown(chat.api.close);
    await chat.refreshAccountSummary();
    expect(
      paths,
      unorderedEquals([
        '/api/v1/billing/subscription',
        '/api/v1/usage/current-period/stats',
      ]),
    );
    expect(chat.accountSummary?.remaining, 316);
    expect(chat.accountSummaryError, isNull);
  });
  test(
    'late balance responses cannot restore an account after logout',
    () async {
      final response = Completer<http.Response>();
      final chat = _chat(
        (request) =>
            request.method == 'GET' ? response.future : Future.value(_ok({})),
      );
      addTearDown(chat.dispose);
      addTearDown(chat.api.close);
      final refresh = chat.refreshAccountSummary();
      await chat.logout();
      response.complete(_ok(_usage));
      await refresh;
      expect(chat.accountSummary, isNull);
      expect(chat.accountSummaryLoading, false);
      expect(chat.accountId, isNull);
    },
  );
  test(
    'history refresh keeps selection and removes stale list items',
    () async {
      final chat = _chat((request) async {
        expect(request.url.path, '/api/v1/ask/conversations');
        return _ok([
          {'id': 'new', 'title': 'New history'},
        ]);
      });
      addTearDown(chat.dispose);
      addTearDown(chat.api.close);
      chat.current = Conversation({
        'id': 'open',
        'title': 'Open draft',
        'messages': [],
      });
      chat.conversations = [
        {'id': 'stale', 'title': 'Stale'},
      ];
      await chat.refreshHistory();
      expect(chat.current?.id, 'open');
      expect(chat.conversations.single['id'], 'new');
      expect(chat.hasMore, false);
    },
  );
  test(
    'delete any history row without changing a different selected conversation',
    () async {
      final paths = <String>[];
      final chat = _chat((request) async {
        paths.add('${request.method} ${request.url.path}');
        return _ok({});
      });
      addTearDown(chat.dispose);
      addTearDown(chat.api.close);
      chat.current = Conversation({'id': 'open', 'messages': []});
      chat.conversations = [
        {'id': 'other', 'title': 'Other'},
      ];
      expect(await chat.deleteConversation('other'), true);
      expect(chat.conversations, isEmpty);
      expect(chat.current?.id, 'open');
      expect(paths, ['DELETE /api/v1/ask/conversations/other']);
    },
  );
  testWidgets(
    'settings shows real plan credits version and honest deletion boundary',
    (tester) async {
      final methods = <String>[];
      final chat = _chat((request) async {
        methods.add(request.method);
        return _ok(
          request.url.path.endsWith('subscription') ? _billing : _usage,
        );
      });
      addTearDown(chat.dispose);
      addTearDown(chat.api.close);
      await _show(
        tester,
        SettingsPage(
          controller: chat,
          onLogout: () async {},
          version: '0.1.0 (1)',
        ),
      );
      expect(find.text('Demir Von'), findsOneWidget);
      expect(find.text('DV'), findsOneWidget);
      expect(find.text('Pro'), findsOneWidget);
      expect(find.text('316 / 500'), findsOneWidget);
      expect(find.text('0.1.0 (1)'), findsOneWidget);
      expect(tester.getTopRight(find.text('0.1.0 (1)')).dx, closeTo(360, 1));
      await tester.ensureVisible(find.text('注销账号'));
      await tester.tap(find.text('注销账号'));
      await tester.pumpAndSettle();
      expect(find.textContaining('当前服务暂不支持'), findsOneWidget);
      expect(methods, everyElement('GET'));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'history swipe reveals actions and deletion requires confirmation',
    (tester) async {
      var deletions = 0;
      final chat = _chat((request) async {
        if (request.method == 'DELETE') {
          deletions++;
          return _ok({});
        }
        return _ok(
          request.url.path.endsWith('subscription') ? _billing : _usage,
        );
      });
      addTearDown(chat.dispose);
      addTearDown(chat.api.close);
      chat.current = Conversation({'id': 'open', 'messages': []});
      chat.conversations = [
        {
          'id': 'other',
          'title': 'Cloud history',
          'updated_at': DateTime.now().toIso8601String(),
        },
      ];
      await _show(
        tester,
        SizedBox(
          width: 318,
          child: MobileHistory(
            controller: chat,
            onNew: () {},
            onSelected: () {},
            onLogout: () async {},
            onDelete: () async {},
          ),
        ),
      );
      expect(find.text('重命名'), findsNothing);
      expect(
        tester.getSize(find.byKey(const ValueKey('history-search'))).height,
        38,
      );
      final searchIcon = find.byWidgetPredicate(
        (widget) => widget is DesignIcon && widget.icon == Icons.search,
      );
      expect(tester.getSize(searchIcon), const Size(15, 15));
      await tester.drag(find.text('Cloud history'), const Offset(-170, 0));
      await tester.pumpAndSettle();
      expect(find.text('重命名'), findsOneWidget);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(deletions, 0);
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(deletions, 0);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '删除'));
      await tester.pumpAndSettle();
      expect(deletions, 1);
      expect(chat.current?.id, 'open');
      expect(find.text('Cloud history'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('sheet opens at design top edge and closes with Done', (
    tester,
  ) async {
    final chat = _chat((_) async => _ok({}));
    addTearDown(chat.dispose);
    addTearDown(chat.api.close);
    await _show(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showTypefluxSettings(
            context,
            controller: chat,
            onLogout: () async {},
          ),
          child: const Text('Open'),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(SettingsPage)).dy, closeTo(58, 1));
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsNothing);
  });
}
