import 'dart:io';

import 'package:file_sync_pro/features/sync/application/sync_engine.dart';
import 'package:file_sync_pro/features/sync/application/sync_source.dart';
import 'package:file_sync_pro/features/sync/domain/ignore_rules.dart';
import 'package:file_sync_pro/features/sync/domain/sync_plan.dart';
import 'package:file_sync_pro/features/transport/http_transport.dart';
import 'package:file_sync_pro/features/transport/protocol.dart';
import 'package:file_sync_pro/features/transport/remote_scanner.dart';
import 'package:file_sync_pro/features/transport/server/file_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  const token = 'test-token';

  late Directory temp;
  late Directory localDir;
  late Directory remoteDir;
  late String stateDir;
  late FileServer server;
  late String baseUrl;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('filesync-http-');
    localDir = Directory(p.join(temp.path, 'local'));
    remoteDir = Directory(p.join(temp.path, 'remote'));
    stateDir = p.join(temp.path, 'state');
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
    IgnoreRules? ignores,
  }) async {
    final rules = ignores ?? IgnoreRules.defaults();
    final engine = SyncEngine(
      a: LocalSyncSource(localDir.path, ignores: rules),
      b: RemoteSyncSource(baseUrl: baseUrl, token: clientToken, ignores: rules),
      stateDir: stateDir,
    );
    try {
      return await run(engine);
    } finally {
      await engine.dispose();
    }
  }

  test('syncs a remote-only file down and a local-only file up', () async {
    await File(p.join(remoteDir.path, 'from-windows.txt')).writeAsString('win');
    await File(p.join(localDir.path, 'from-mac.txt')).writeAsString('mac');

    final report = await withEngine((engine) => engine.sync());

    expect(report.hasConflicts, isFalse);
    expect(
      await File(p.join(localDir.path, 'from-windows.txt')).readAsString(),
      'win',
    );
    expect(
      await File(p.join(remoteDir.path, 'from-mac.txt')).readAsString(),
      'mac',
    );
  });

  test('scoped preview only scans the selected remote subtree', () async {
    await Directory(p.join(remoteDir.path, 'docs', 'notes'))
        .create(recursive: true);
    await File(p.join(remoteDir.path, 'docs', 'notes', 'a.txt'))
        .writeAsString('a');
    await File(p.join(remoteDir.path, 'docs', 'b.txt')).writeAsString('b');
    await File(p.join(remoteDir.path, 'other.txt')).writeAsString('o');
    await Directory(p.join(localDir.path, 'docs', 'notes'))
        .create(recursive: true);
    await File(p.join(localDir.path, 'docs', 'notes', 'a.txt'))
        .writeAsString('a');

    final preview = await withEngine(
      (engine) => engine.preview(subPath: 'docs/notes'),
    );

    expect(preview.b.entries.keys, ['docs/notes', 'docs/notes/a.txt']);
    expect(preview.a.entries.keys, ['docs/notes', 'docs/notes/a.txt']);
    expect(preview.plan.isEmpty, isTrue);
  });

  test('scoped preview supports a single file', () async {
    await File(p.join(remoteDir.path, 'other.txt')).writeAsString('o');

    final preview = await withEngine(
      (engine) => engine.preview(subPath: 'other.txt'),
    );

    expect(preview.b.entries.keys, ['other.txt']);
    expect(preview.plan.actions, hasLength(1));
    expect(preview.plan.actions.single.path, 'other.txt');
    expect(preview.plan.actions.single.kind, SyncActionKind.createLeft);
  });

  test('propagates edits and deletions both ways', () async {
    await withEngine((engine) => engine.sync());

    await File(p.join(localDir.path, 'a.txt')).writeAsString('v1');
    await withEngine((engine) => engine.sync());
    expect(await File(p.join(remoteDir.path, 'a.txt')).readAsString(), 'v1');

    await File(p.join(remoteDir.path, 'a.txt')).writeAsString('v2');
    await withEngine((engine) => engine.sync());
    expect(await File(p.join(localDir.path, 'a.txt')).readAsString(), 'v2');

    await File(p.join(localDir.path, 'a.txt')).delete();
    await withEngine((engine) => engine.sync());
    expect(await File(p.join(remoteDir.path, 'a.txt')).exists(), isFalse);
  });

  test('reports conflicts without overwriting either side', () async {
    await File(p.join(localDir.path, 'doc.txt')).writeAsString('base');
    await withEngine((engine) => engine.sync());

    await File(p.join(localDir.path, 'doc.txt')).writeAsString('mac edit');
    await File(p.join(remoteDir.path, 'doc.txt')).writeAsString('windows edit');

    final report = await withEngine((engine) => engine.sync());

    expect(report.conflictCount, 1);
    expect(
      await File(p.join(localDir.path, 'doc.txt')).readAsString(),
      'mac edit',
    );
    expect(
      await File(p.join(remoteDir.path, 'doc.txt')).readAsString(),
      'windows edit',
    );

    final backup = report.conflictBackupRoot!;
    expect(File(p.join(backup, 'a', 'doc.txt')).existsSync(), isTrue);
    expect(File(p.join(backup, 'b', 'doc.txt')).existsSync(), isTrue);
  });

  test('creates and removes empty directories', () async {
    await withEngine((engine) => engine.sync());

    await Directory(p.join(localDir.path, 'empty', 'nested'))
        .create(recursive: true);
    await withEngine((engine) => engine.sync());
    expect(
      Directory(p.join(remoteDir.path, 'empty', 'nested')).existsSync(),
      isTrue,
    );

    await Directory(p.join(localDir.path, 'empty')).delete(recursive: true);
    await withEngine((engine) => engine.sync());
    expect(Directory(p.join(remoteDir.path, 'empty')).existsSync(), isFalse);
  });

  test('resolves a conflict by keeping the local side', () async {
    await File(p.join(localDir.path, 'doc.txt')).writeAsString('base');
    await withEngine((engine) => engine.sync());

    await File(p.join(localDir.path, 'doc.txt')).writeAsString('mac edit');
    await File(p.join(remoteDir.path, 'doc.txt')).writeAsString('win edit');

    await withEngine((engine) async {
      final report = await engine.sync();
      expect(report.conflictCount, 1);
      final resolution = await engine.resolveConflicts(report.preview, {
        'doc.txt': ConflictSide.left,
      });
      expect(resolution.resolved, 1);
      expect(resolution.remaining, 0);
    });

    expect(
      await File(p.join(localDir.path, 'doc.txt')).readAsString(),
      'mac edit',
    );
    expect(
      await File(p.join(remoteDir.path, 'doc.txt')).readAsString(),
      'mac edit',
    );
  });

  test('resolves a conflict by keeping the remote side', () async {
    await File(p.join(localDir.path, 'doc.txt')).writeAsString('base');
    await withEngine((engine) => engine.sync());

    await File(p.join(localDir.path, 'doc.txt')).writeAsString('mac edit');
    await File(p.join(remoteDir.path, 'doc.txt')).writeAsString('win edit');

    await withEngine((engine) async {
      final report = await engine.sync();
      await engine.resolveConflicts(report.preview, {
        'doc.txt': ConflictSide.right,
      });
    });

    expect(
      await File(p.join(localDir.path, 'doc.txt')).readAsString(),
      'win edit',
    );
    expect(
      await File(p.join(remoteDir.path, 'doc.txt')).readAsString(),
      'win edit',
    );
  });

  test('applies default ignores on the remote manifest', () async {
    await Directory(p.join(remoteDir.path, '.git')).create();
    await File(p.join(remoteDir.path, '.git', 'config')).writeAsString('x');
    await File(p.join(remoteDir.path, '.DS_Store')).writeAsString('x');
    await Directory(p.join(remoteDir.path, '.venv')).create();
    await File(p.join(remoteDir.path, '.venv', 'x')).writeAsString('x');
    await Directory(p.join(remoteDir.path, '__pycache__')).create();
    await File(p.join(remoteDir.path, '__pycache__', 'x.pyc'))
        .writeAsString('x');
    await File(p.join(remoteDir.path, 'keep.txt')).writeAsString('keep');

    await withEngine((engine) => engine.sync());

    expect(await File(p.join(localDir.path, 'keep.txt')).exists(), isTrue);
    expect(
      await File(p.join(localDir.path, '.git', 'config')).exists(),
      isFalse,
    );
    expect(await File(p.join(localDir.path, '.DS_Store')).exists(), isFalse);
    expect(await Directory(p.join(localDir.path, '.venv')).exists(), isFalse);
    expect(
      await Directory(p.join(localDir.path, '__pycache__')).exists(),
      isFalse,
    );
  });

  test('rejects an invalid token', () async {
    await expectLater(
      withEngine((engine) => engine.preview(), clientToken: 'wrong-token'),
      throwsA(
        isA<RemoteException>().having(
          (error) => error.statusCode,
          'statusCode',
          401,
        ),
      ),
    );
  });

  test('rejects path traversal', () async {
    final transport = HttpTransport(baseUrl: baseUrl, token: token);
    try {
      await expectLater(
        transport.getJson(ServerRoute.manifest, query: {'path': '../'}),
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

  test('remote manifest includes content hashes', () async {
    await File(p.join(remoteDir.path, 'a.txt')).writeAsString('hello');

    final transport = HttpTransport(baseUrl: baseUrl, token: token);
    try {
      final manifest = await RemoteScanner(transport: transport).scan();
      expect(manifest.entries['a.txt']!.hash, isNotNull);
      expect(manifest.root, baseUrl);
    } finally {
      await transport.close();
    }
  });
}
