import 'dart:io';

import 'package:file_sync_pro/app/app.dart';
import 'package:file_sync_pro/features/sync/application/sync_pair_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('filesync-ui-');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  testWidgets('renders the dashboard without touching the network', (
    tester,
  ) async {
    final config = SyncPairConfig(
      localRoot: p.join(temp.path, 'local'),
      remoteUrl: 'http://127.0.0.1:1/photolens',
      token: 'test',
      stateDir: p.join(temp.path, 'state'),
    );

    await tester.pumpWidget(
      FileSyncProApp(
        config: config,
        configPath: p.join(temp.path, 'tool', 'sync.config.json'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('File Sync Pro'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('sync.check')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('sync.run')), findsOneWidget);
    expect(find.textContaining('Local folder'), findsOneWidget);
    expect(find.textContaining('Remote mount'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('sync.plan.list')), findsNothing);
  });

  testWidgets('shows the setup page when config is missing', (tester) async {
    await tester.pumpWidget(
      FileSyncProApp(configPath: p.join(temp.path, 'tool', 'sync.config.json')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('setup.card')), findsOneWidget);
    expect(find.text('Configuration required'), findsOneWidget);
  });
}
