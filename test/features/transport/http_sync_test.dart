import 'dart:io';

import 'package:file_sync_pro/features/sync/application/sync_engine.dart';
import 'package:file_sync_pro/features/sync/application/sync_source.dart';
import 'package:file_sync_pro/features/transport/http_transport.dart';
import 'package:file_sync_pro/features/transport/protocol.dart';
import 'package:file_sync_pro/features/transport/server/file_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  const token = 'test-token';

  late Directory temp;
  late Directory localDir;
  late Directory remoteDir;
  late String backupDir;
  late FileServer server;
  late String baseUrl;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('filesync-http-');
    localDir = Directory(p.join(temp.path, 'local'));
    remoteDir = Directory(p.join(temp.path, 'remote'));
    backupDir = p.join(temp.path, 'chore');
    await localDir.create();
    await remoteDir.create();

    server = FileServer(
      mounts: [FileServerMount(name: 'photolens', root: remoteDir.path)],
      token: token,
      quiet: true,
    );
    await server.start(port: 0);
    baseUrl = 'http://127.0.0.1:${server.port}/photolens/';
  });

  tearDown(() async {
    await server.close(force: true);
    await temp.delete(recursive: true);
  });

  Future<T> withEngine<T>(
    Future<T> Function(SyncEngine engine) run, {
    String clientToken = token,
  }) async {
    final engine = SyncEngine(
      a: LocalSyncSource(
        localDir.path,
        snapshotBackupDir: backupDir,
        snapshotLabel: 'pair-local',
      ),
      b: RemoteSyncSource(
        baseUrl: baseUrl,
        token: clientToken,
        snapshotBackupDir: backupDir,
        snapshotLabel: 'pair-remote',
      ),
      conflictRoot: p.join(temp.path, 'conflicts'),
    );
    try {
      return await run(engine);
    } finally {
      await engine.dispose();
    }
  }

  Future<SyncPreview> planNow(SyncEngine engine, {String? subPath}) async {
    final loaded = await engine.loadSnapshots();
    return engine.planFromSnapshots(
      loaded.a.snapshot!,
      loaded.b.snapshot!,
      subPath: subPath,
    );
  }

  Future<SyncReport> syncNow(
    SyncEngine engine, {
    SyncDirection direction = SyncDirection.both,
    String? subPath,
  }) async {
    final loaded = await engine.loadSnapshots();
    return engine.execute(
      engine.planFromSnapshots(
        loaded.a.snapshot!,
        loaded.b.snapshot!,
        subPath: subPath,
      ),
      aSnapshot: loaded.a.snapshot!,
      bSnapshot: loaded.b.snapshot!,
      direction: direction,
      subPath: subPath,
    );
  }

  test('initial scan writes snapshots on both sides', () async {
    await File(p.join(localDir.path, 'from-mac.txt')).writeAsString('mac\n');
    await File(p.join(remoteDir.path, 'from-phone.txt'))
        .writeAsString('phone\n');

    await withEngine((engine) => engine.scanBoth(createIfMissing: true));

    expect(
      File(p.join(localDir.path, '.file_sync_shot.json')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(remoteDir.path, '.file_sync_shot.json')).existsSync(),
      isTrue,
    );

    final loaded = await withEngine((engine) => engine.loadSnapshots());
    final localFiles = loaded.a.snapshot!.current.entries['.']!.files;
    final remoteFiles = loaded.b.snapshot!.current.entries['.']!.files;
    expect(localFiles.keys, contains('from-mac.txt'));
    expect(remoteFiles.keys, contains('from-phone.txt'));
  });

  test('syncs a remote-only file down and a local-only file up', () async {
    await File(p.join(remoteDir.path, 'from-windows.txt')).writeAsString('win');
    await File(p.join(localDir.path, 'from-mac.txt')).writeAsString('mac');

    final report = await withEngine((engine) async {
      await engine.scanBoth(createIfMissing: true);
      return syncNow(engine);
    });

    expect(report.hasConflicts, isFalse);
    expect(
      await File(p.join(localDir.path, 'from-windows.txt')).readAsString(),
      'win',
    );
    expect(
      await File(p.join(remoteDir.path, 'from-mac.txt')).readAsString(),
      'mac',
    );

    final next = await withEngine(planNow);
    expect(next.plan.isEmpty, isTrue);
  });

  test('refreshes only the selected remote subtree', () async {
    await Directory(p.join(remoteDir.path, 'docs')).create(recursive: true);
    await File(p.join(remoteDir.path, 'docs', 'a.txt')).writeAsString('a1\n');
    await File(p.join(remoteDir.path, 'other.txt')).writeAsString('o1\n');

    await withEngine((engine) async {
      await engine.scanBoth(createIfMissing: true);
      await syncNow(engine);
    });

    final before = await withEngine((engine) => engine.loadSnapshots());
    final otherHashBefore =
        before.b.snapshot!.current.entries['.']!.files['other.txt']!.hash;
    final docsHashBefore =
        before.b.snapshot!.current.entries['docs']!.files['a.txt']!.hash;

    await File(p.join(remoteDir.path, 'docs', 'a.txt')).writeAsString('a2\n');
    await File(p.join(remoteDir.path, 'other.txt')).writeAsString('o2\n');

    final snapshot = await withEngine(
      (engine) => engine.scanSide(left: false, subPath: 'docs'),
    );

    final docsEntry = snapshot.current.entries['docs']!.files['a.txt']!;
    final otherEntry = snapshot.current.entries['.']!.files['other.txt']!;
    expect(docsEntry.hash, isNot(docsHashBefore));
    expect(
      otherEntry.hash,
      otherHashBefore,
      reason: 'other.txt was not part of the refresh',
    );

    final preview = await withEngine(planNow);
    expect(preview.plan.actions.map((action) => action.path), ['docs/a.txt']);
  });

  test('check and sync never scan on their own', () async {
    await File(p.join(localDir.path, 'doc.txt')).writeAsString('v1\n');
    await withEngine((engine) async {
      await engine.scanBoth(createIfMissing: true);
      await syncNow(engine);
    });

    await File(p.join(localDir.path, 'doc.txt')).writeAsString('v2\n');

    final stale = await withEngine(planNow);
    expect(stale.plan.isEmpty, isTrue);

    await withEngine((engine) => engine.scanSide(left: true));
    final refreshed = await withEngine(planNow);
    expect(refreshed.plan.actions.map((action) => action.path), ['doc.txt']);

    await withEngine(syncNow);
    expect(
      await File(p.join(remoteDir.path, 'doc.txt')).readAsString(),
      'v2\n',
    );
  });

  test('rejects a remote refresh before the initial scan', () async {
    await expectLater(
      withEngine((engine) => engine.scanSide(left: false)),
      throwsA(
        isA<RemoteException>().having(
          (error) => error.statusCode,
          'statusCode',
          409,
        ),
      ),
    );
  });

  test('migrates a legacy remote snapshot to the chore folder', () async {
    final legacy = File(p.join(remoteDir.path, '.file_sync_shot.json'));
    await legacy.writeAsString(
      '{"schema":1,"committedAt":"2026-01-01T00:00:00Z","entries":{}}',
    );

    final loaded = await withEngine((engine) => engine.loadSnapshots());

    expect(loaded.b.snapshot, isNull);
    expect(loaded.b.legacy, isTrue);
    expect(loaded.b.backupPath, isNotNull);
    expect(File(loaded.b.backupPath!).existsSync(), isTrue);
    expect(await legacy.exists(), isFalse);
  });

  test('applies default ignores on the remote snapshot', () async {
    await Directory(p.join(remoteDir.path, '.git')).create();
    await File(p.join(remoteDir.path, '.git', 'config')).writeAsString('x');
    await File(p.join(remoteDir.path, '.DS_Store')).writeAsString('x');
    await File(p.join(remoteDir.path, 'keep.txt')).writeAsString('keep');

    await withEngine((engine) async {
      await engine.scanBoth(createIfMissing: true);
      await syncNow(engine);
    });

    expect(await File(p.join(localDir.path, 'keep.txt')).exists(), isTrue);
    expect(await File(p.join(localDir.path, '.DS_Store')).exists(), isFalse);
    expect(await Directory(p.join(localDir.path, '.git')).exists(), isFalse);
  });

  test('rejects an invalid token', () async {
    await File(p.join(remoteDir.path, 'a.txt')).writeAsString('a');

    await expectLater(
      withEngine(
        (engine) => engine.loadSnapshots(),
        clientToken: 'wrong-token',
      ),
      throwsA(
        isA<RemoteException>().having(
          (error) => error.statusCode,
          'statusCode',
          401,
        ),
      ),
    );
  });

  test('rejects path traversal on the snapshot endpoint', () async {
    final transport = HttpTransport(baseUrl: baseUrl, token: token);
    try {
      await expectLater(
        transport.postJson(
          ServerRoute.snapshot,
          query: {'path': '../', 'mode': 'refresh'},
        ),
        throwsA(
          isA<RemoteException>().having(
            (error) => error.statusCode,
            'statusCode',
            400,
          ),
        ),
      );
    } finally {
      await transport.close();
    }
  });
}
