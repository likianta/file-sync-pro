import 'dart:convert';
import 'dart:io';

import 'package:file_sync_pro/app/forui_theme.dart';
import 'package:file_sync_pro/features/sync/presentation/sync_workspace_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late String toolDir;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('filesync-ui-');
    toolDir = p.join(temp.path, 'tool');
    Directory(toolDir).createSync(recursive: true);
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  Widget wrap(String configPath) {
    return MaterialApp(
      localizationsDelegates: FLocalizations.localizationsDelegates,
      supportedLocales: FLocalizations.supportedLocales,
      builder: (context, child) => FTheme(
        data: AppForuiTheme.light,
        child: FToaster(child: FTooltipGroup(child: child!)),
      ),
      home: SyncWorkspacePage(configPath: configPath, projectRoot: temp.path),
    );
  }

  testWidgets('renders the sync workspace with a configured pair', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final local = Directory(p.join(temp.path, 'local'))..createSync();
    final configPath = p.join(toolDir, 'sync.config.json');
    File(configPath).writeAsStringSync(
      jsonEncode({
        'version': 2,
        'token': 'test-token',
        'pairs': [
          {
            'name': 'demo',
            'localRoot': local.path,
            'remoteUrl': 'http://127.0.0.1:1/demo',
            'stateDir': 'data/sync_pairs/demo',
          },
        ],
      }),
    );

    await tester.pumpWidget(wrap(configPath));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('sync.pair.select')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('sync.run')), findsOneWidget);
    expect(find.text('demo'), findsWidgets);
    expect(find.text('Sync'), findsWidgets);
  });

  testWidgets('shows the empty state when no pairs are configured', (
    tester,
  ) async {
    final configPath = p.join(toolDir, 'sync.config.json');
    File(
      configPath,
    ).writeAsStringSync(jsonEncode({'version': 2, 'token': '', 'pairs': []}));

    await tester.pumpWidget(wrap(configPath));
    await tester.pumpAndSettle();

    expect(find.text('No sync pairs yet.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('sync.pair.emptyAdd')),
      findsOneWidget,
    );
  });
}
