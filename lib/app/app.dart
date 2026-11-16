import 'package:flutter/material.dart';

import 'home_shell.dart';
import 'theme.dart';

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
    return MaterialApp(
      title: 'File Sync Pro',
      debugShowCheckedModeBanner: false,
      themeMode: _mode,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: HomeShell(
        projectRoot: widget.projectRoot,
        clientConfigPath: widget.clientConfigPath,
        serverConfigPath: widget.serverConfigPath,
        isDark: _mode == ThemeMode.dark,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}
