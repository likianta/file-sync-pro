import 'package:flutter/material.dart';

import '../features/server/presentation/android_server_page.dart';

/// The Android build acts as a file server that the Mac controls.
class AndroidFileServerApp extends StatelessWidget {
  const AndroidFileServerApp({super.key});

  static const seed = Color(0xFF2563EB);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'File Sync Pro',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const AndroidServerPage(),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final light = brightness == Brightness.light;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: light ? const Color(0xFFF7F8FA) : scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: light ? const Color(0xFFF7F8FA) : scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0.5,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
