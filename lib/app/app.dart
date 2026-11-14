import 'package:flutter/material.dart';

import 'home_shell.dart';
import 'theme.dart';

class FileSyncProApp extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'File Sync Pro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: HomeShell(
        projectRoot: projectRoot,
        clientConfigPath: clientConfigPath,
        serverConfigPath: serverConfigPath,
      ),
    );
  }
}
