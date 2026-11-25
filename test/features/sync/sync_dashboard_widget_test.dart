import 'dart:convert';
import 'dart:io';

import 'package:file_sync_pro/app/theme.dart';
import 'package:file_sync_pro/features/sync/application/sync_config_store.dart';
import 'package:file_sync_pro/features/sync/presentation/devices_page.dart';
import 'package:file_sync_pro/features/sync/presentation/sync_workspace_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
      theme: AppTheme.light,
      home: Scaffold(body: child),
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
        'version': 4,
        'token': 'test-token',
        'devices': [
          {
            'id': 'd-test',
            'name': 'Test device',
            'type': 'windows',
            'host_type': 'remote',
            'host': '127.0.0.1',
            'port': 1,
            'pairs': [
              {
                'id': 'p-demo',
                'name': 'demo',
                'local_root': local.path,
                'remote_root': '/demo',
              },
            ],
          },
        ],
      }),
    );

    final store = await loadStore(configPath);
    await tester.pumpWidget(wrap(SyncWorkspacePage(store: store)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byKey(const ValueKey<String>('sync.device.select')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('sync.tree.left')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('sync.tree.right')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('sync.check')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('sync.run')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('sync.pull')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('sync.push')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('sync.autoLocate')),
      findsOneWidget,
    );
    expect(find.text('THIS MACHINE'), findsOneWidget);
    expect(find.text('Peer device'), findsOneWidget);
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

    expect(find.text('No devices'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('sync.device.select')),
      findsOneWidget,
    );
  });

  testWidgets('device pair list exposes the pair editor', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final local = Directory(p.join(temp.path, 'local'))..createSync();
    final configPath = p.join(toolDir, 'sync.config.json');
    File(configPath).writeAsStringSync(
      jsonEncode({
        'version': 4,
        'token': 'test-token',
        'devices': [
          {
            'id': 'd-test',
            'name': 'Windows box',
            'type': 'windows',
            'host_type': 'remote',
            'host': '127.0.0.1',
            'port': 1,
            'pairs': [
              {
                'id': 'p-demo',
                'name': 'demo',
                'local_root': local.path,
                'remote_root': '/demo',
              },
            ],
          },
        ],
      }),
    );

    final store = await loadStore(configPath);
    await tester.pumpWidget(wrap(DevicesPage(store: store)));
    await tester.pumpAndSettle();

    final edit = find.byKey(
      const ValueKey<String>('devices.pair.edit.d-test.demo'),
    );
    await tester.ensureVisible(edit);
    await tester.pumpAndSettle();

    expect(find.text('Windows box'), findsWidgets);
    await tester.tap(edit);
    // The editor loads ignores from disk in the background, so settle is not
    // possible here: real file IO never finishes under FakeAsync.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey<String>('sync.pair.mount')),
      findsOneWidget,
    );
    expect(find.textContaining('/demo'), findsWidgets);
  });
}
