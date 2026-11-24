import 'dart:convert';
import 'dart:io';

import 'package:file_sync_pro/features/sync/application/sync_engine.dart';
import 'package:file_sync_pro/features/sync/data/snapshot_manager.dart';
import 'package:file_sync_pro/features/sync/domain/sync_plan.dart';
import 'package:file_sync_pro/features/sync/domain/sync_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late Directory alice;
  late Directory bob;
  late String stateDir;
  late String snapshotBackupDir;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('filesync-local-');
    alice = Directory(p.join(temp.path, 'alice'));
    bob = Directory(p.join(temp.path, 'bob'));
    await alice.create();
    await bob.create();
    stateDir = p.join(temp.path, 'state');
    snapshotBackupDir = p.join(temp.path, 'chore');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  Future<T> withEngine<T>(Future<T> Function(SyncEngine engine) run) async {
    final engine = SyncEngine.local(
      rootA: alice.path,
      rootB: bob.path,
      stateDir: stateDir,
      snapshotBackupDir: snapshotBackupDir,
      labelA: 'alice',
      labelB: 'bob',
    );
    try {
      return await run(engine);
    } finally {
      await engine.dispose();
    }
  }

  Future<({SideSnapshot a, SideSnapshot b})> scanBoth(SyncEngine engine) {
    return engine.scanBoth(createIfMissing: true);
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

  test('initial scan writes current with an empty base', () async {
    await _file(alice, 'docs/readme.md').writeAsString('hello\n');
    await _file(bob, 'notes.txt').writeAsString('bob\n');

    await withEngine((engine) async {
      final snapshots = await scanBoth(engine);
      expect(snapshots.a.base.isEmpty, isTrue);
      expect(snapshots.b.base.isEmpty, isTrue);
      expect(
        snapshots.a.current.entries['.']!.files.containsKey('readme.md'),
        isFalse,
      );
      expect(
        snapshots.a.current.entries['docs']!.files.keys,
        contains('readme.md'),
      );
      expect(snapshots.a.current.key, isNotEmpty);
      expect(snapshots.b.current.key, isNotEmpty);
    });

    final json = jsonDecode(
      await _file(alice, '.file_sync_shot.json').readAsString(),
    ) as Map<String, Object?>;
    expect(json.keys, containsAll(['base', 'current']));
    final base = json['base']! as Map<String, Object?>;
    expect((base['entries']! as Map), isEmpty);
    final current = json['current']! as Map<String, Object?>;
    expect(current['key'], isA<String>());
    expect(current['updated_at'], isA<int>());
    final entries = current['entries']! as Map<String, Object?>;
    expect(entries.keys, containsAll(['.', 'docs']));
    expect(
      ((entries['docs']! as Map)['files']! as Map).keys,
      contains('readme.md'),
    );
    expect(entries.containsKey('.file_sync_shot.json'), isFalse);
  });

  test('first sync merges both sides and settles the snapshots', () async {
    await _file(alice, 'alice-only.txt').writeAsString('a\n');
    await _file(bob, 'bob-only.txt').writeAsString('b\n');
    await _file(alice, 'shared.txt').writeAsString('same\n');
    await _file(bob, 'shared.txt').writeAsString('same\n');

    final report = await withEngine((engine) async {
      await scanBoth(engine);
      return syncNow(engine);
    });

    expect(report.hasConflicts, isFalse);
    expect(await _exists(bob, 'alice-only.txt'), isTrue);
    expect(await _exists(alice, 'bob-only.txt'), isTrue);
    expect(await _read(bob, 'shared.txt'), 'same\n');

    final next = await withEngine(planNow);
    expect(next.plan.isEmpty, isTrue);
  });

  test('sync never scans: edits stay invisible until refreshed', () async {
    await _file(alice, 'doc.txt').writeAsString('v1\n');
    await withEngine((engine) async {
      await scanBoth(engine);
      await syncNow(engine);
    });

    await _file(alice, 'doc.txt').writeAsString('v2\n');

    final stale = await withEngine(planNow);
    expect(stale.plan.isEmpty, isTrue, reason: 'current is still v1');

    await withEngine((engine) => engine.scanSide(left: true));
    final refreshed = await withEngine(planNow);
    expect(
      refreshed.plan.actions.map((action) => action.path),
      contains('doc.txt'),
    );

    await withEngine(syncNow);
    expect(await _read(bob, 'doc.txt'), 'v2\n');
  });

  test('refreshes only the selected folder', () async {
    await _file(alice, 'docs/readme.md').writeAsString('docs v1\n');
    await _file(alice, 'media/photo.txt').writeAsString('media v1\n');
    await withEngine((engine) async {
      await scanBoth(engine);
      await syncNow(engine);
    });

    await _file(alice, 'docs/readme.md').writeAsString('docs v2\n');
    await _file(alice, 'media/photo.txt').writeAsString('media v2\n');

    await withEngine((engine) => engine.scanSide(left: true, subPath: 'docs'));

    final preview = await withEngine(planNow);
    expect(preview.plan.actions.map((action) => action.path), [
      'docs/readme.md',
    ]);

    await withEngine((engine) => syncNow(engine, subPath: 'docs'));
    expect(await _read(bob, 'docs/readme.md'), 'docs v2\n');
    expect(await _read(bob, 'media/photo.txt'), 'media v1\n');
  });

  test('propagates deletions after the side is refreshed', () async {
    await _file(alice, 'keep.txt').writeAsString('keep\n');
    await _file(bob, 'remove.txt').writeAsString('bye\n');
    await withEngine((engine) async {
      await scanBoth(engine);
      await syncNow(engine);
    });

    await _file(bob, 'remove.txt').delete();
    await withEngine((engine) => engine.scanSide(left: false));
    await withEngine(syncNow);

    expect(await _exists(alice, 'remove.txt'), isFalse);
    expect(await _exists(alice, 'keep.txt'), isTrue);
  });

  test('reports conflicts and keeps them for the next check', () async {
    await _file(alice, 'doc.txt').writeAsString('base\n');
    await withEngine((engine) async {
      await scanBoth(engine);
      await syncNow(engine);
    });

    await _file(alice, 'doc.txt').writeAsString('alice\n');
    await _file(bob, 'doc.txt').writeAsString('bob\n');
    final report = await withEngine((engine) async {
      await engine.scanSide(left: true);
      await engine.scanSide(left: false);
      return syncNow(engine);
    });

    expect(report.conflictCount, 1);
    expect(await _read(alice, 'doc.txt'), 'alice\n');
    expect(await _read(bob, 'doc.txt'), 'bob\n');
    expect(report.conflictBackupRoot, isNotNull);
    expect(
      File(p.join(report.conflictBackupRoot!, 'a', 'doc.txt')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(report.conflictBackupRoot!, 'b', 'doc.txt')).existsSync(),
      isTrue,
    );

    final next = await withEngine(planNow);
    expect(next.plan.conflicts, hasLength(1));
  });

  test('keeps a modified-vs-deleted conflict', () async {
    await _file(alice, 'doc.txt').writeAsString('base\n');
    await withEngine((engine) async {
      await scanBoth(engine);
      await syncNow(engine);
    });

    await _file(alice, 'doc.txt').writeAsString('still here\n');
    await _file(bob, 'doc.txt').delete();
    final report = await withEngine((engine) async {
      await engine.scanSide(left: true);
      await engine.scanSide(left: false);
      return syncNow(engine);
    });

    expect(report.conflictCount, 1);
    expect(
      report.plan.conflicts.single.reason,
      ConflictReason.modifiedVsDeleted,
    );
    expect(await _read(alice, 'doc.txt'), 'still here\n');
    expect(await _exists(bob, 'doc.txt'), isFalse);
  });

  test('resolves a conflict from the selected side', () async {
    await _file(alice, 'doc.txt').writeAsString('base\n');
    await withEngine((engine) async {
      await scanBoth(engine);
      await syncNow(engine);
    });

    await _file(alice, 'doc.txt').writeAsString('alice\n');
    await _file(bob, 'doc.txt').writeAsString('bob\n');
    final result = await withEngine((engine) async {
      await engine.scanSide(left: true);
      await engine.scanSide(left: false);
      final loaded = await engine.loadSnapshots();
      final preview = engine.planFromSnapshots(
        loaded.a.snapshot!,
        loaded.b.snapshot!,
      );
      return engine.resolveConflicts(
        preview,
        aSnapshot: loaded.a.snapshot!,
        bSnapshot: loaded.b.snapshot!,
        choices: {'doc.txt': ConflictSide.left},
      );
    });

    expect(result.resolved, 1);
    expect(result.remaining, 0);
    expect(await _read(bob, 'doc.txt'), 'alice\n');

    final next = await withEngine(planNow);
    expect(next.plan.conflicts, isEmpty);
    expect(next.plan.actions, isEmpty);
  });

  test('one-way push and pull copy only the selected subtree', () async {
    await _file(alice, 'docs/readme.md').writeAsString('alice docs\n');
    await _file(bob, 'shared/common.txt').writeAsString('bob shared\n');
    await withEngine((engine) async {
      await scanBoth(engine);
      await syncNow(engine);
    });

    await _file(alice, 'docs/readme.md').writeAsString('alice docs v2\n');
    await _file(bob, 'shared/common.txt').writeAsString('bob shared v2\n');

    await withEngine((engine) async {
      await engine.scanSide(left: true, subPath: 'docs');
      await syncNow(engine, direction: SyncDirection.push, subPath: 'docs');
    });
    expect(await _read(bob, 'docs/readme.md'), 'alice docs v2\n');
    expect(await _read(bob, 'shared/common.txt'), 'bob shared v2\n');

    await withEngine((engine) async {
      await engine.scanSide(left: false, subPath: 'docs');
      await syncNow(engine, direction: SyncDirection.pull, subPath: 'docs');
    });
    expect(await _read(alice, 'docs/readme.md'), 'alice docs v2\n');
  });

  test('refreshes and syncs empty directories', () async {
    await withEngine((engine) async {
      await scanBoth(engine);
      await syncNow(engine);
    });

    await Directory(p.join(alice.path, 'empty', 'nested'))
        .create(recursive: true);
    await withEngine((engine) => engine.scanSide(left: true));
    await withEngine(syncNow);
    expect(Directory(p.join(bob.path, 'empty', 'nested')).existsSync(), isTrue);

    await Directory(p.join(alice.path, 'empty')).delete(recursive: true);
    await withEngine((engine) => engine.scanSide(left: true));
    await withEngine(syncNow);
    expect(Directory(p.join(bob.path, 'empty')).existsSync(), isFalse);
  });

  test(
    'folder refresh fails without touching the snapshot when it is gone',
    () async {
      await _file(alice, 'docs/readme.md').writeAsString('v1\n');
      final before = await withEngine((engine) async {
        await scanBoth(engine);
        final loaded = await engine.loadSnapshots();
        return loaded.a.snapshot!.current.key;
      });

      await Directory(p.join(alice.path, 'docs')).delete(recursive: true);

      await withEngine((engine) async {
        await expectLater(
          engine.scanSide(left: true, subPath: 'docs'),
          throwsA(isA<SnapshotPathException>()),
        );
        final loaded = await engine.loadSnapshots();
        expect(loaded.a.snapshot!.current.key, before);
      });
    },
  );

  test('rejects refresh before an initial scan', () async {
    await withEngine((engine) async {
      await expectLater(
        engine.scanSide(left: true),
        throwsA(isA<SnapshotMissingException>()),
      );
    });
  });

  test('a no-op sync still advances base to current', () async {
    await _file(alice, 'doc.txt').writeAsString('v1\n');
    await withEngine((engine) async {
      await scanBoth(engine);
      await syncNow(engine);
    });

    final report = await withEngine(syncNow);
    expect(report.plan.isEmpty, isTrue);
    expect(report.aSnapshot!.base.key, report.aSnapshot!.current.key);
    expect(report.bSnapshot!.base.key, report.bSnapshot!.current.key);
  });

  test('scoped sync adds a new folder to both bases', () async {
    await withEngine((engine) async {
      await scanBoth(engine);
      await syncNow(engine);
    });

    await _file(alice, 'newdir/a.txt').writeAsString('a\n');
    final report = await withEngine((engine) async {
      await engine.scanSide(left: true, subPath: 'newdir');
      final loaded = await engine.loadSnapshots();
      final preview = engine.planFromSnapshots(
        loaded.a.snapshot!,
        loaded.b.snapshot!,
        subPath: 'newdir',
      );
      return engine.execute(
        preview,
        aSnapshot: loaded.a.snapshot!,
        bSnapshot: loaded.b.snapshot!,
        subPath: 'newdir',
      );
    });

    expect(report.aSnapshot!.base.entries['.']!.dirs, contains('newdir'));
    expect(report.bSnapshot!.base.entries['.']!.dirs, contains('newdir'));
    expect(
      report.aSnapshot!.base.entries['newdir']!.files.keys,
      contains('a.txt'),
    );
    expect(await _read(bob, 'newdir/a.txt'), 'a\n');
  });

  test('scoped sync of a single file updates both bases', () async {
    await _file(alice, 'doc.txt').writeAsString('v1\n');
    await withEngine((engine) async {
      await scanBoth(engine);
      await syncNow(engine);
    });

    await _file(alice, 'doc.txt').writeAsString('v2\n');
    final report = await withEngine((engine) async {
      await engine.scanSide(left: true);
      final loaded = await engine.loadSnapshots();
      final preview = engine.planFromSnapshots(
        loaded.a.snapshot!,
        loaded.b.snapshot!,
        subPath: 'doc.txt',
      );
      return engine.execute(
        preview,
        aSnapshot: loaded.a.snapshot!,
        bSnapshot: loaded.b.snapshot!,
        subPath: 'doc.txt',
      );
    });

    expect(
      report.aSnapshot!.base.entries['.']!.files['doc.txt']!.hash,
      report.aSnapshot!.current.entries['.']!.files['doc.txt']!.hash,
    );
    expect(
      report.bSnapshot!.base.entries['.']!.files['doc.txt']!.hash,
      report.bSnapshot!.current.entries['.']!.files['doc.txt']!.hash,
    );
    expect(await _read(bob, 'doc.txt'), 'v2\n');
  });

  test('uses the ignores stored in the snapshot', () async {
    await _file(alice, '.file_sync_shot.json').writeAsString(
      jsonEncode({
        'ignores': ['/skip/'],
        'base': {'key': '', 'updated_at': 0, 'entries': {}},
        'current': {'key': '', 'updated_at': 0, 'entries': {}},
      }),
    );
    await _file(alice, 'skip/hidden.txt').writeAsString('hidden\n');
    await _file(alice, 'keep.txt').writeAsString('keep\n');

    final snapshot = await withEngine((engine) => engine.scanSide(left: true));

    expect(snapshot.current.entries.containsKey('skip'), isFalse);
    expect(snapshot.current.entries['.']!.files.keys, contains('keep.txt'));
    expect(snapshot.ignores.patterns, ['/skip/']);
  });

  test('supports \$gitignore snapshot ignores', () async {
    await _file(alice, '.gitignore').writeAsString('/skip/\n');
    await _file(alice, '.file_sync_shot.json').writeAsString(
      jsonEncode({
        'ignores': r'$gitignore',
        'base': {'key': '', 'updated_at': 0, 'entries': {}},
        'current': {'key': '', 'updated_at': 0, 'entries': {}},
      }),
    );
    await _file(alice, 'skip/hidden.txt').writeAsString('hidden\n');
    await _file(alice, 'keep.txt').writeAsString('keep\n');

    final snapshot = await withEngine((engine) => engine.scanSide(left: true));

    expect(snapshot.current.entries.containsKey('skip'), isFalse);
    expect(snapshot.ignores.useGitignore, isTrue);
  });

  test('silently ignores snapshot files during a scan', () async {
    await _file(alice, 'doc.txt').writeAsString('v1\n');
    await withEngine((engine) async {
      await scanBoth(engine);
      await syncNow(engine);
    });

    final loaded = await withEngine((engine) => engine.loadSnapshots());
    expect(
      loaded.a.snapshot!.current.entries['.']!.files.containsKey(
        '.file_sync_shot.json',
      ),
      isFalse,
    );
    expect(
      loaded.b.snapshot!.current.entries['.']!.files.containsKey(
        '.file_sync_shot.json',
      ),
      isFalse,
    );
  });
}

File _file(Directory root, String relPath) {
  final file = File(p.joinAll([root.path, ...relPath.split('/')]));
  file.parent.createSync(recursive: true);
  return file;
}

Future<String> _read(Directory root, String relPath) {
  return File(p.joinAll([root.path, ...relPath.split('/')])).readAsString();
}

Future<bool> _exists(Directory root, String relPath) {
  return File(p.joinAll([root.path, ...relPath.split('/')])).exists();
}
