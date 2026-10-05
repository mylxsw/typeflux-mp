import 'dart:convert';

import 'package:flutter/material.dart';

import 'session.dart';

/// Device preferences are independent of accounts and never contain credentials.
class AppPreferences extends ChangeNotifier {
  AppPreferences(this.vault);
  final Vault vault;
  static const storageKey = 'preferences.v1';
  ThemeMode _themeMode = ThemeMode.system;
  Locale? _locale;
  bool _disposed = false, _changed = false;
  Future<void> _pending = Future<void>.value();
  ThemeMode get themeMode => _themeMode;
  Locale? get locale => _locale;

  Future<void> load() async {
    final saved = await vault.read(storageKey);
    if (_disposed || _changed || saved == null) return;
    try {
      final data = jsonDecode(saved) as Map<String, dynamic>;
      _themeMode = switch (data['theme']) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      _locale = switch (data['language']) {
        'zh' => const Locale('zh'),
        'en' => const Locale('en'),
        _ => null,
      };
      notifyListeners();
    } on FormatException {
      // Ignore a corrupt preference record; do not touch account storage.
    } on TypeError {
      // Older or unsupported formats fall back to the device settings.
    }
  }

  Future<void> setThemeMode(ThemeMode mode) => _save(mode: mode);

  Future<void> setLocale(Locale? locale) {
    if (locale != null && !['zh', 'en'].contains(locale.languageCode)) {
      return Future<void>.error(ArgumentError.value(locale, 'locale'));
    }
    return _save(language: locale, changeLanguage: true);
  }

  Future<void> _save({
    ThemeMode? mode,
    Locale? language,
    bool changeLanguage = false,
  }) {
    _changed = true;
    final operation = _pending.then((_) async {
      final oldMode = _themeMode, oldLocale = _locale;
      _themeMode = mode ?? _themeMode;
      if (changeLanguage) _locale = language;
      if (!_disposed) notifyListeners();
      try {
        await vault.write(
          storageKey,
          jsonEncode({
            'theme': _themeMode.name,
            'language': _locale?.languageCode ?? 'system',
          }),
        );
      } catch (_) {
        _themeMode = oldMode;
        _locale = oldLocale;
        if (!_disposed) notifyListeners();
        rethrow;
      }
    });
    // Each caller receives its own failure while later writes can still run.
    _pending = operation.catchError((Object _) {});
    return operation;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class PreferencesScope extends InheritedNotifier<AppPreferences> {
  const PreferencesScope({
    super.key,
    required AppPreferences preferences,
    required super.child,
  }) : super(notifier: preferences);

  static AppPreferences? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PreferencesScope>()?.notifier;
}
