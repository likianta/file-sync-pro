import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'app/app.dart';
import 'features/sync/application/sync_pair_config.dart';

void main() {
  final projectRoot =
      SyncPairConfig.findProjectRoot(
        executablePath: Platform.resolvedExecutable,
      ) ??
      Directory.current.path;
  final configPath = p.join(projectRoot, 'tool', 'sync.config.json');

  SyncPairConfig? config;
  String? configError;
  try {
    config = SyncPairConfig.load(
      configPath: configPath,
      projectRoot: projectRoot,
    );
  } catch (error) {
    configError = 'Cannot read $configPath\n$error';
  }

  runApp(
    FileSyncProApp(
      config: config,
      configError: configError,
      configPath: configPath,
    ),
  );
}
