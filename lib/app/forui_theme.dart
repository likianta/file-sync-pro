import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// The application's Forui themes.
///
/// The palette is layered the same way as the reference design:
/// window background < cards < inset surfaces.
abstract final class AppForuiTheme {
  /// The accent color used across the app.
  static const accent = Color(0xFF2563EB);

  static const lightBackground = Color(0xFFF5F6F8);
  static const lightSidebar = Color(0xFFFFFFFF);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightBorder = Color(0xFFE3E6EA);

  static const darkBackground = Color(0xFF0B0C0E);
  static const darkSidebar = Color(0xFF111214);
  static const darkCard = Color(0xFF17191C);
  static const darkBorder = Color(0xFF2A2E33);

  /// The light theme.
  static final light = FThemeData(
    colors: FColors.neutralLight.copyWith(
      background: lightBackground,
      foreground: const Color(0xFF1A1D21),
      card: lightCard,
      border: lightBorder,
      muted: const Color(0xFFF1F3F5),
      mutedForeground: const Color(0xFF6F757C),
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
      background: darkBackground,
      foreground: const Color(0xFFEDEFF2),
      card: darkCard,
      border: darkBorder,
      muted: const Color(0xFF1E2125),
      mutedForeground: const Color(0xFF9BA1A8),
      primary: const Color(0xFF3B82F6),
      primaryForeground: const Color(0xFFFFFFFF),
      secondary: const Color(0xFF172554),
      secondaryForeground: const Color(0xFFBFDBFE),
    ),
    touch: false,
    debugLabel: 'File Sync Pro Dark',
  );

  /// The scaffold style that separates the sidebar from the content area.
  static FScaffoldStyleDelta scaffoldStyle({required bool dark}) {
    return FScaffoldStyleDelta.delta(
      backgroundColor: dark ? darkBackground : lightBackground,
      sidebarBackgroundColor: dark ? darkSidebar : lightSidebar,
    );
  }
}
