import 'package:flutter/material.dart';

import 'mobile_design.dart';

ThemeData typefluxTheme(
  Brightness brightness, {
  String? fontFamily,
  List<String>? fontFamilyFallback,
}) {
  final p = MobilePalette(brightness == Brightness.dark);
  return ThemeData(
    brightness: brightness,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: p.accent,
          brightness: brightness,
        ).copyWith(
          primary: p.accent,
          onPrimary: Colors.white,
          surface: p.surface,
          onSurface: p.ink,
          error: p.red,
        ),
    scaffoldBackgroundColor: p.bg,
    useMaterial3: true,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
  );
}
