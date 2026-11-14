import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const seedColor = Color(0xFF3D7BFF);

  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }
}
