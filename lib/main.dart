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

  runApp(
    FileSyncProApp(
      projectRoot: projectRoot,
      clientConfigPath: p.join(projectRoot, 'tool', 'sync.config.json'),
      serverConfigPath: p.join(projectRoot, 'tool', 'file_server.config.json'),
    ),
  );
}
