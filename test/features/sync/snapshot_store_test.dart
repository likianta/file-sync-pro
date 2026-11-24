import 'dart:io';

import 'package:file_sync_pro/features/sync/data/file_store.dart';
import 'package:file_sync_pro/features/sync/data/snapshot_store.dart';
import 'package:file_sync_pro/features/sync/domain/sync_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('filesync-snapshot-');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('round-trips base and current snapshots', () async {
    final store = SnapshotStore(LocalFileStore(temp.path));
    expect((await store.load()).isMissing, isTrue);

    final current = SnapshotState.fromEntries({
      '.': FolderSnapshot(
        mtimeMs: 111,
        dirs: ['docs'],
        files: {
          'root.txt': const FileSnapshot(
            size: 3,
            mtimeMs: 112,
            hash: 'raw-root',
            textHash: 'text-root',
          ),
        },
      ),
      'docs': FolderSnapshot(
        mtimeMs: 222,
        files: {
          'readme.md': const FileSnapshot(
            size: 5,
            mtimeMs: 223,
            hash: 'raw-doc',
            textHash: 'text-doc',
          ),
        },
      ),
    }, updatedAt: 1234);
    final snapshot = SideSnapshot(
      base: SnapshotState.empty(),
      current: current,
      ignores: const SnapshotIgnores.patterns(['/skip/', '*.tmp']),
    );
    await store.save(snapshot);

    final loaded = await store.load();
    final result = loaded.snapshot!;
    expect(result.base.isEmpty, isTrue);
    expect(result.ignores.patterns, ['/skip/', '*.tmp']);
    expect(result.current.updatedAt, 1234);
    expect(result.current.key, current.key);
    expect(result.current.entries.keys, ['.', 'docs']);
    expect(
      result.current.entries['docs']!.files['readme.md']!.textHash,
      'text-doc',
    );

    final text = await File(p.join(temp.path, SnapshotStore.defaultFileName))
        .readAsString();
    expect(text, contains('"base"'));
    expect(text, contains('"current"'));
    expect(text, contains('"ignores"'));
    expect(text, contains('"text_hash"'));
  });

  test('moves a legacy snapshot to the backup directory', () async {
    final origin = File(p.join(temp.path, SnapshotStore.defaultFileName));
    await origin.writeAsString(
      '{"schema":1,"committedAt":"2026-01-01T00:00:00Z","entries":{}}',
    );
    final backupDir = p.join(temp.path, 'chore');
    final store = SnapshotStore(
      LocalFileStore(temp.path),
      backupDir: backupDir,
      label: 'pair-local',
    );

    final loaded = await store.load();
    expect(loaded.snapshot, isNull);
    expect(loaded.legacy, isTrue);
    expect(loaded.backupPath, isNotNull);
    expect(File(loaded.backupPath!).existsSync(), isTrue);
    expect(await origin.exists(), isFalse);
    expect(
      await File(loaded.backupPath!).readAsString(),
      contains('"schema":1'),
    );
  });

  test('reports legacy without a backup directory', () async {
    final origin = File(p.join(temp.path, SnapshotStore.defaultFileName));
    await origin.writeAsString('not json');
    final store = SnapshotStore(LocalFileStore(temp.path));

    final loaded = await store.load();
    expect(loaded.snapshot, isNull);
    expect(loaded.legacy, isTrue);
    expect(loaded.backupPath, isNull);
    expect(await origin.exists(), isTrue);
  });

  test('changes the key when entries change', () {
    FolderSnapshot folder(String hash) {
      return FolderSnapshot(
        mtimeMs: 1,
        files: {'a.txt': FileSnapshot(size: 1, mtimeMs: 1, hash: hash)},
      );
    }

    final first = SnapshotState.fromEntries({'.': folder('one')}, updatedAt: 1);
    final second = SnapshotState.fromEntries({
      '.': folder('two'),
    }, updatedAt: 2);
    expect(first.key, isNot(second.key));
  });
}
