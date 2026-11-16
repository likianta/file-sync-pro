import 'package:flutter/material.dart';

/// The desktop application's Material 3 theme.
///
/// Colors are layered like the reference design: window background, surface
/// panels, and inset fields.
abstract final class AppTheme {
  static const accent = Color(0xFF3370FF);

  static const lightBackground = Color(0xFFF5F6F8);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightBorder = Color(0xFFE6E8EB);
  static const lightText = Color(0xFF1F2329);
  static const lightMuted = Color(0xFF8F959E);
  static const lightHover = Color(0xFFF0F7FF);
  static const lightSelected = Color(0xFFEAF1FF);

  static const darkBackground = Color(0xFF0B0C0E);
  static const darkSurface = Color(0xFF17191C);
  static const darkBorder = Color(0xFF2A2E33);
  static const darkText = Color(0xFFEDEFF2);
  static const darkMuted = Color(0xFF9BA1A8);
  static const darkHover = Color(0xFF1C2738);
  static const darkSelected = Color(0xFF1E2B44);

  static final ThemeData light = _build(Brightness.light);
  static final ThemeData dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final surface = isDark ? darkSurface : lightSurface;
    final border = isDark ? darkBorder : lightBorder;
    final text = isDark ? darkText : lightText;

    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: brightness,
        ).copyWith(
          primary: isDark ? const Color(0xFF6A9BFF) : accent,
          onPrimary: Colors.white,
          surface: surface,
          onSurface: text,
          onSurfaceVariant: isDark ? darkMuted : const Color(0xFF646A73),
          outlineVariant: border,
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
    );

    return base.copyWith(
      scaffoldBackgroundColor: isDark ? darkBackground : lightBackground,
      canvasColor: isDark ? darkBackground : lightBackground,
      dividerColor: border,
      splashFactory: InkSparkle.splashFactory,
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF111316) : Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        labelStyle: TextStyle(
          fontSize: 12,
          color: isDark ? darkMuted : lightMuted,
        ),
        hintStyle: TextStyle(
          fontSize: 13,
          color: isDark ? darkMuted : lightMuted,
        ),
        helperStyle: TextStyle(
          fontSize: 11,
          color: isDark ? darkMuted : lightMuted,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.error),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 34),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(visualDensity: VisualDensity.compact),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: border),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? const Color(0xFF26292E)
            : const Color(0xFF1F2329),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        textStyle: const TextStyle(fontSize: 12, color: Colors.white),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2329).withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: border),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? Colors.white : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : (isDark ? const Color(0xFF2A2E33) : const Color(0xFFD8DCE2)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: isDark
            ? const Color(0xFF23262B)
            : const Color(0xFFEFF0F1),
        circularTrackColor: Colors.transparent,
      ),
      listTileTheme: ListTileThemeData(
        dense: true,
        iconColor: isDark ? darkMuted : lightMuted,
        textColor: text,
      ),
    );
  }

  /// Resolves the row hover/selection colors outside of [ThemeData].
  static Color hoverColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkHover
        : lightHover;
  }

  static Color selectedColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkSelected
        : lightSelected;
  }
}
