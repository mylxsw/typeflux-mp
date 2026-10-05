import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/api.dart';
import 'core/environment.dart';
import 'core/session.dart';
import 'core/preferences.dart';
import 'auth/auth_flow.dart';
import 'chat/cache.dart';
import 'chat/chat_controller.dart';
import 'ui/login_page.dart';
import 'ui/chat_page.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TypefluxApp());
}

class TypefluxApp extends StatefulWidget {
  const TypefluxApp({
    super.key,
    this.vault = const SecureVault(),
    this.apiFactory = createAuthApi,
    this.environment = AppEnvironment.current,
  });
  final Vault vault;
  final AuthApiFactory apiFactory;
  final AppEnvironment environment;
  @override
  State<TypefluxApp> createState() => _TypefluxAppState();
}

class _TypefluxAppState extends State<TypefluxApp> {
  Vault get vault => widget.vault;
  late final preferences = AppPreferences(vault);
  final navigatorKey = GlobalKey<NavigatorState>();
  TypefluxApi? api;
  String? _resolvedOrigin;
  ChatController? chat;
  bool restoring = true, _loggingOut = false;
  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    try {
      await preferences.load();
    } catch (_) {
      // Device preferences must not prevent account restoration.
    }
    if (!mounted) return;
    try {
      // An explicit launch environment must not be replaced by a previously
      // saved server, or prevented by a failure reading that unrelated value.
      final saved = widget.environment.hasApiOverride
          ? null
          : await vault.read('server');
      _resolvedOrigin = widget.environment.resolveOrigin(savedOrigin: saved);
      if (!mounted) return;
      api = widget.apiFactory(Uri.parse(_resolvedOrigin!), vault);
      await api!.restore();
      if (!mounted) return;
      if (api!.signedIn) _createChat();
    } catch (_) {
      /* Show sign-in when stored configuration is unreadable. */
    }
    if (mounted) setState(() => restoring = false);
  }

  void _createChat() {
    chat?.removeListener(_sessionChanged);
    chat?.dispose();
    chat = ChatController(api!, FileChatCache());
    chat!.addListener(_sessionChanged);
    unawaited(chat!.initialize());
  }

  void _sessionChanged() {
    if (_loggingOut || api?.signedIn != false || chat == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loggingOut || api?.signedIn != false || chat == null) {
        return;
      }
      chat!.removeListener(_sessionChanged);
      chat!.dispose();
      chat = null;
      navigatorKey.currentState?.popUntil((route) => route.isFirst);
      setState(() {});
    });
    // A notifier may change between frames, so ensure the cleanup is scheduled.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _signedIn(TypefluxApi next) async {
    await vault.write('server', next.origin.origin);
    if (!mounted) {
      next.close();
      return;
    }
    if (api != next) api?.close();
    api = next;
    _resolvedOrigin = next.origin.origin;
    _createChat();
    if (mounted) setState(() {});
  }

  Future<void> _logout() async {
    if (_loggingOut) return;
    _loggingOut = true;
    try {
      await chat?.logout();
      chat?.removeListener(_sessionChanged);
      chat?.dispose();
      chat = null;
      if (mounted) setState(() {});
    } finally {
      _loggingOut = false;
    }
  }

  @override
  void dispose() {
    chat?.removeListener(_sessionChanged);
    chat?.dispose();
    api?.close();
    preferences.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: preferences,
    builder: (context, _) => PreferencesScope(
      preferences: preferences,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Typeflux',
        debugShowCheckedModeBanner: false,
        supportedLocales: const [Locale('en'), Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: typefluxTheme(Brightness.light),
        darkTheme: typefluxTheme(Brightness.dark),
        themeMode: preferences.themeMode,
        locale: preferences.locale,
        home: restoring
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : chat == null
            ? LoginPage(
                vault: vault,
                initialOrigin:
                    _resolvedOrigin ?? widget.environment.resolveOrigin(),
                onSignedIn: _signedIn,
                apiFactory: widget.apiFactory,
              )
            : ChatPage(controller: chat!, onLogout: _logout),
      ),
    ),
  );
}
