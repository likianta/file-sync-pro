import 'dart:io';

import 'package:file_sync_pro/features/sync/application/pair_ignores.dart';
import 'package:file_sync_pro/features/sync/data/file_store.dart';
import 'package:file_sync_pro/features/sync/data/snapshot_store.dart';
import 'package:file_sync_pro/features/sync/domain/sync_snapshot.dart';
import 'package:file_sync_pro/features/transport/server/file_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  const token = 'test-token';

  late Directory temp;
  late Directory localDir;
  late Directory remoteDir;
  late FileServer server;
  late String remoteUrl;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('filesync-ignores-');
    localDir = Directory(p.join(temp.path, 'local'));
    remoteDir = Directory(p.join(temp.path, 'remote'));
    await localDir.create();
    await remoteDir.create();
    server = FileServer(
      mounts: [FileServerMount(name: 'pair', root: remoteDir.path)],
      token: token,
      quiet: true,
    );
    await server.start(port: 0);
    remoteUrl = 'http://127.0.0.1:${server.port}/pair/';
  });

  tearDown(() async {
    await server.close(force: true);
    await temp.delete(recursive: true);
  });

  PairIgnoresStore createStore() {
    return PairIgnoresStore(
      localRoot: localDir.path,
      remoteUrl: remoteUrl,
      token: token,
      pairName: 'pair',
    );
  }

  Map<String, FolderSnapshot> entries() {
    return {
      '.': FolderSnapshot(
        mtimeMs: 1,
        files: {
          'keep.txt': const FileSnapshot(size: 1, mtimeMs: 1, hash: 'x64:1'),
        },
      ),
    };
  }

  test('loads list ignores and writes them to both snapshots', () async {
    final local = SnapshotStore(LocalFileStore(localDir.path));
    final remote = SnapshotStore(LocalFileStore(remoteDir.path));
    await local.save(
      SideSnapshot(
        base: SnapshotState.fromEntries(entries(), updatedAt: 1),
        current: SnapshotState.fromEntries(entries(), updatedAt: 2),
        ignores: const SnapshotIgnores.patterns(['old-local']),
      ),
    );
    await remote.save(
      SideSnapshot(
        base: SnapshotState.empty(),
        current: SnapshotState.fromEntries(entries(), updatedAt: 3),
        ignores: const SnapshotIgnores.patterns(['old-remote']),
      ),
    );

    final loaded = await createStore().load();
    expect(loaded.source, IgnoresSource.local);
    expect(loaded.form, IgnoresForm.builtinList);
    expect(loaded.text, 'old-local');
    expect(loaded.warning, isNull);

    await createStore().save(
      form: IgnoresForm.builtinList,
      text: '/skip/\n\n*.tmp\n',
    );

    final afterLocal = (await local.load()).snapshot!;
    final afterRemote = (await remote.load()).snapshot!;
    expect(afterLocal.ignores.patterns, ['/skip/', '*.tmp']);
    expect(afterRemote.ignores.patterns, ['/skip/', '*.tmp']);
    expect(afterLocal.current.entries['.']!.files.keys, ['keep.txt']);
    expect(afterRemote.current.entries['.']!.files.keys, ['keep.txt']);
  });

  test('creates seed snapshots when neither side has one', () async {
    final loaded = await createStore().load();
    expect(loaded.source, isNull);
    expect(loaded.form, IgnoresForm.builtinList);
    expect(loaded.text, isEmpty);

    await createStore().save(form: IgnoresForm.builtinList, text: 'a\nb');

    final afterLocal = (await SnapshotStore(
      LocalFileStore(localDir.path),
    ).load()).snapshot!;
    final afterRemote = (await SnapshotStore(
      LocalFileStore(remoteDir.path),
    ).load()).snapshot!;
    expect(afterLocal.ignores.patterns, ['a', 'b']);
    expect(afterRemote.ignores.patterns, ['a', 'b']);
    expect(afterLocal.current.isEmpty, isTrue);
    expect(afterRemote.current.isEmpty, isTrue);
  });

  test('loads .gitignore and writes it back on both sides', () async {
    await File(p.join(localDir.path, PairIgnoresStore.gitignoreFile))
        .writeAsString('# keep\n*.log\n');
    await SnapshotStore(LocalFileStore(localDir.path)).save(
      SideSnapshot(
        base: SnapshotState.empty(),
        current: SnapshotState.empty(),
        ignores: const SnapshotIgnores.gitignore(),
      ),
    );

    final loaded = await createStore().load();
    expect(loaded.source, IgnoresSource.local);
    expect(loaded.form, IgnoresForm.gitignore);
    expect(loaded.text, '# keep\n*.log\n');

    await createStore().save(form: IgnoresForm.gitignore, text: '*.log\n/tmp/');

    expect(
      File(p.join(localDir.path, PairIgnoresStore.gitignoreFile))
          .readAsStringSync(),
      '*.log\n/tmp/\n',
    );
    expect(
      File(p.join(remoteDir.path, PairIgnoresStore.gitignoreFile))
          .readAsStringSync(),
      '*.log\n/tmp/\n',
    );

    final afterLocal = (await SnapshotStore(
      LocalFileStore(localDir.path),
    ).load()).snapshot!;
    final afterRemote = (await SnapshotStore(
      LocalFileStore(remoteDir.path),
    ).load()).snapshot!;
    expect(afterLocal.ignores.useGitignore, isTrue);
    expect(afterRemote.ignores.useGitignore, isTrue);
  });
}
