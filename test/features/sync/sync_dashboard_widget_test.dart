import 'dart:convert';
import 'dart:io';

import 'package:file_sync_pro/app/forui_theme.dart';
import 'package:file_sync_pro/features/sync/application/sync_config_store.dart';
import 'package:file_sync_pro/features/sync/presentation/devices_page.dart';
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

  Widget wrap(Widget child) {
    return MaterialApp(
      localizationsDelegates: FLocalizations.localizationsDelegates,
      supportedLocales: FLocalizations.supportedLocales,
      builder: (context, child) => FTheme(
        data: AppForuiTheme.light,
        child: FToaster(child: FTooltipGroup(child: child!)),
      ),
      home: child,
    );
  }

  Future<SyncConfigStore> loadStore(String configPath) async {
    final store = SyncConfigStore(path: configPath, projectRoot: temp.path);
    await store.load();
    return store;
  }

  testWidgets('renders the device pair, tabs, and the action bar', (
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

    final store = await loadStore(configPath);
    await tester.pumpWidget(wrap(SyncWorkspacePage(store: store)));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('sync.device.select')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('sync.pair.tab.demo')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('sync.run')), findsOneWidget);
    expect(find.text('THIS MACHINE'), findsOneWidget);
    expect(find.text('PEER DEVICE'), findsOneWidget);
    expect(find.text('demo'), findsWidgets);
  });

  testWidgets('shows the empty state when no devices are configured', (
    tester,
  ) async {
    final configPath = p.join(toolDir, 'sync.config.json');
    File(
      configPath,
    ).writeAsStringSync(jsonEncode({'version': 3, 'token': '', 'pairs': []}));

    final store = await loadStore(configPath);
    await tester.pumpWidget(wrap(SyncWorkspacePage(store: store)));
    await tester.pumpAndSettle();

    expect(find.text('No devices yet.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('sync.device.select')),
      findsNothing,
    );
  });

  testWidgets('device pair list exposes the pair editor with ignores', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final local = Directory(p.join(temp.path, 'local'))..createSync();
    final configPath = p.join(toolDir, 'sync.config.json');
    File(configPath).writeAsStringSync(
      jsonEncode({
        'version': 3,
        'token': 'test-token',
        'ignores': ['.venv/'],
        'devices': [
          {
            'id': 'dev-test',
            'name': 'Windows box',
            'type': 'windows',
            'hostType': 'remote',
            'host': '127.0.0.1',
            'port': 1,
          },
        ],
        'pairs': [
          {
            'name': 'demo',
            'deviceId': 'dev-test',
            'localRoot': local.path,
            'remoteUrl': 'http://127.0.0.1:1/demo',
            'stateDir': 'data/sync_pairs/demo',
            'ignores': ['/blog/', '**.b64.html'],
          },
        ],
      }),
    );

    final store = await loadStore(configPath);
    await tester.pumpWidget(wrap(DevicesPage(store: store)));
    await tester.pumpAndSettle();

    final edit = find.byKey(
      const ValueKey<String>('devices.pair.edit.dev-test.demo'),
    );
    await tester.ensureVisible(edit);
    await tester.pumpAndSettle();

    expect(find.text('Windows box'), findsWidgets);
    await tester.tap(edit);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('sync.pair.ignores')),
      findsOneWidget,
    );
    expect(find.textContaining('/blog/'), findsWidgets);
  });
}
