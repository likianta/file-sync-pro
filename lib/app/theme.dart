import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const seedColor = Color(0xFF3370FF);

  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    final isLight = brightness == Brightness.light;
    return ThemeData(
      colorScheme: scheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      scaffoldBackgroundColor: isLight ? const Color(0xFFF5F6F8) : null,
      dividerColor: isLight ? const Color(0xFFE6E8EB) : null,
      cardTheme: CardThemeData(
        color: isLight ? Colors.white : null,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isLight ? const Color(0xFFE6E8EB) : scheme.outlineVariant,
          ),
        ),
      ),
    );
  }
}
