import 'dart:io';

import 'package:file_sync_pro/features/sync/data/file_store.dart';
import 'package:file_sync_pro/features/sync/data/snapshot_store.dart';
import 'package:file_sync_pro/features/sync/domain/manifest.dart';
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

  test('round-trips a manifest through the snapshot file', () async {
    final store = SnapshotStore(LocalFileStore(temp.path));
    expect(await store.load(), isNull);

    final manifest = Manifest(
      root: '',
      scannedAt: DateTime.utc(2026, 1, 1),
      entries: {
        'docs/readme.md': ManifestEntry.file(
          size: 5,
          mtimeMs: 123,
          hash: 'abc',
          textHash: 'abd',
        ),
        'empty': ManifestEntry.directory(mtimeMs: 456),
      },
    );
    await store.save(manifest, committedAt: DateTime.utc(2026, 1, 2));

    final loaded = await store.load();
    expect(loaded, isNotNull);
    expect(loaded!.entries.keys, ['docs/readme.md', 'empty']);
    expect(loaded.entries['docs/readme.md']!.hash, 'abc');
    expect(loaded.entries['docs/readme.md']!.textHash, 'abd');
    expect(loaded.entries['empty']!.isDirectory, isTrue);
  });

  test('treats a corrupt snapshot as missing', () async {
    final store = SnapshotStore(LocalFileStore(temp.path));
    await File(p.join(temp.path, SnapshotStore.defaultFileName))
        .writeAsString('not json');

    expect(await store.load(), isNull);
  });
}
