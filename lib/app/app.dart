import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'forui_theme.dart';
import 'home_shell.dart';

class FileSyncProApp extends StatefulWidget {
  const FileSyncProApp({
    super.key,
    required this.projectRoot,
    required this.clientConfigPath,
    required this.serverConfigPath,
  });

  final String projectRoot;
  final String clientConfigPath;
  final String serverConfigPath;

  @override
  State<FileSyncProApp> createState() => _FileSyncProAppState();
}

class _FileSyncProAppState extends State<FileSyncProApp> {
  late ThemeMode _mode =
      WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark
      ? ThemeMode.dark
      : ThemeMode.light;

  void _toggleTheme() {
    setState(() {
      _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _mode == ThemeMode.dark;
    return MaterialApp(
      title: 'File Sync Pro',
      debugShowCheckedModeBanner: false,
      themeMode: _mode,
      theme: _materialTheme(Brightness.light),
      darkTheme: _materialTheme(Brightness.dark),
      localizationsDelegates: FLocalizations.localizationsDelegates,
      supportedLocales: FLocalizations.supportedLocales,
      builder: (context, child) => FTheme(
        data: isDark ? AppForuiTheme.dark : AppForuiTheme.light,
        child: FToaster(child: FTooltipGroup(child: child!)),
      ),
      home: HomeShell(
        projectRoot: widget.projectRoot,
        clientConfigPath: widget.clientConfigPath,
        serverConfigPath: widget.serverConfigPath,
        isDark: isDark,
        onToggleTheme: _toggleTheme,
      ),
    );
  }

  /// Material is only kept for the app shell (navigation routes, overlays).
  /// Every visible widget is a Forui widget.
  ThemeData _materialTheme(Brightness brightness) {
    return ThemeData(
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppForuiTheme.accent,
        brightness: brightness,
      ),
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xFFF6F7F9)
          : const Color(0xFF0B0B0C),
    );
  }
}
