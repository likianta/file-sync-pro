import 'package:flutter/material.dart';

import '../features/setup/presentation/setup_page.dart';
import '../features/sync/application/sync_pair_config.dart';
import '../features/sync/presentation/sync_dashboard_page.dart';
import 'theme.dart';

class FileSyncProApp extends StatelessWidget {
  const FileSyncProApp({
    super.key,
    this.config,
    this.configError,
    required this.configPath,
  });

  final SyncPairConfig? config;
  final String? configError;
  final String configPath;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'File Sync Pro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: config == null
          ? SetupPage(configPath: configPath, error: configError)
          : SyncDashboardPage(config: config!),
    );
  }
}
