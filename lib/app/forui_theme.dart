import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// The application's Forui themes.
///
/// Both themes are derived from Forui's neutral palette, with the primary
/// color tuned to a blue accent. Desktop sizing is used on every platform
/// because this is a desktop-first tool.
abstract final class AppForuiTheme {
  /// The accent color used across the app.
  static const accent = Color(0xFF2563EB);

  /// The light theme.
  static final light = FThemeData(
    colors: FColors.neutralLight.copyWith(
      primary: accent,
      primaryForeground: const Color(0xFFFFFFFF),
      secondary: const Color(0xFFEFF4FF),
      secondaryForeground: const Color(0xFF1D4ED8),
    ),
    touch: false,
    debugLabel: 'File Sync Pro Light',
  );

  /// The dark theme.
  static final dark = FThemeData(
    colors: FColors.neutralDark.copyWith(
      primary: const Color(0xFF3B82F6),
      primaryForeground: const Color(0xFFFFFFFF),
      secondary: const Color(0xFF172554),
      secondaryForeground: const Color(0xFFBFDBFE),
    ),
    touch: false,
    debugLabel: 'File Sync Pro Dark',
  );
}
