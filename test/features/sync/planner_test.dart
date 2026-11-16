import 'package:file_sync_pro/features/sync/domain/manifest.dart';
import 'package:file_sync_pro/features/sync/domain/sync_plan.dart';
import 'package:flutter_test/flutter_test.dart';

Manifest _manifest(Map<String, ManifestEntry> entries) {
  return Manifest(
    root: '/test',
    scannedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    entries: entries,
  );
}

ManifestEntry _file(String hash, {int mtime = 100}) {
  return ManifestEntry.file(size: hash.length, mtimeMs: mtime, hash: hash);
}

ManifestEntry _dir({int mtime = 100}) {
  return ManifestEntry.directory(mtimeMs: mtime);
}

void main() {
  group('SyncPlanner files', () {
    test('creates a file on the right when only A has it', () {
      final plan = SyncPlanner.plan(
        base: _manifest({}),
        a: _manifest({'new.txt': _file('a')}),
        b: _manifest({}),
      );

      expect(plan.conflicts, isEmpty);
      expect(plan.actions, hasLength(1));
      expect(plan.actions.single.kind, SyncActionKind.createRight);
      expect(plan.actions.single.path, 'new.txt');
    });

    test('creates a file on the left when only B has it', () {
      final plan = SyncPlanner.plan(
        base: _manifest({}),
        a: _manifest({}),
        b: _manifest({'new.txt': _file('b')}),
      );

      expect(plan.actions.single.kind, SyncActionKind.createLeft);
    });

    test('pushes an A update to the right', () {
      final plan = SyncPlanner.plan(
        base: _manifest({'f.txt': _file('old')}),
        a: _manifest({'f.txt': _file('new')}),
        b: _manifest({'f.txt': _file('old')}),
      );

      expect(plan.conflicts, isEmpty);
      expect(plan.actions.single.kind, SyncActionKind.updateRight);
    });

    test('pushes a B update to the left', () {
      final plan = SyncPlanner.plan(
        base: _manifest({'f.txt': _file('old')}),
        a: _manifest({'f.txt': _file('old')}),
        b: _manifest({'f.txt': _file('new')}),
      );

      expect(plan.actions.single.kind, SyncActionKind.updateLeft);
    });

    test('reports a conflict when both sides changed a file', () {
      final plan = SyncPlanner.plan(
        base: _manifest({'f.txt': _file('old')}),
        a: _manifest({'f.txt': _file('from-a')}),
        b: _manifest({'f.txt': _file('from-b')}),
      );

      expect(plan.actions, isEmpty);
      expect(plan.conflicts, hasLength(1));
      expect(plan.conflicts.single.reason, ConflictReason.bothModified);
    });

    test('reports a conflict when one side modified and the other deleted', () {
      final plan = SyncPlanner.plan(
        base: _manifest({'f.txt': _file('old')}),
        a: _manifest({'f.txt': _file('new')}),
        b: _manifest({}),
      );

      expect(plan.actions, isEmpty);
      expect(plan.conflicts.single.reason, ConflictReason.modifiedVsDeleted);
    });

    test('propagates a deletion when the other side is unchanged', () {
      final plan = SyncPlanner.plan(
        base: _manifest({'f.txt': _file('old')}),
        a: _manifest({}),
        b: _manifest({'f.txt': _file('old')}),
      );

      expect(plan.actions.single.kind, SyncActionKind.deleteRight);
    });

    test('propagates a deletion to the left', () {
      final plan = SyncPlanner.plan(
        base: _manifest({'f.txt': _file('old')}),
        a: _manifest({'f.txt': _file('old')}),
        b: _manifest({}),
      );

      expect(plan.actions.single.kind, SyncActionKind.deleteLeft);
    });

    test('does nothing when both sides deleted', () {
      final plan = SyncPlanner.plan(
        base: _manifest({'f.txt': _file('old')}),
        a: _manifest({}),
        b: _manifest({}),
      );

      expect(plan.isEmpty, isTrue);
    });

    test('does nothing when both sides created the same content', () {
      final plan = SyncPlanner.plan(
        base: _manifest({}),
        a: _manifest({'f.txt': _file('same')}),
        b: _manifest({'f.txt': _file('same')}),
      );

      expect(plan.isEmpty, isTrue);
    });

    test('reports a conflict when both sides created different content', () {
      final plan = SyncPlanner.plan(
        base: _manifest({}),
        a: _manifest({'f.txt': _file('a')}),
        b: _manifest({'f.txt': _file('b')}),
      );

      expect(plan.conflicts.single.reason, ConflictReason.bothCreated);
    });

    test('ignores a newer mtime when content is identical', () {
      final plan = SyncPlanner.plan(
        base: _manifest({'f.txt': _file('same', mtime: 100)}),
        a: _manifest({'f.txt': _file('same', mtime: 900)}),
        b: _manifest({'f.txt': _file('same', mtime: 100)}),
      );

      expect(plan.isEmpty, isTrue);
    });

    test('treats an older but different content as a change', () {
      final plan = SyncPlanner.plan(
        base: _manifest({'f.txt': _file('old', mtime: 100)}),
        a: _manifest({'f.txt': _file('new', mtime: 50)}),
        b: _manifest({'f.txt': _file('old', mtime: 100)}),
      );

      expect(plan.actions.single.kind, SyncActionKind.updateRight);
    });
  });

  group('SyncPlanner directories', () {
    test('creates an empty directory on the other side', () {
      final plan = SyncPlanner.plan(
        base: _manifest({}),
        a: _manifest({'empty': _dir()}),
        b: _manifest({}),
      );

      expect(plan.actions.single.kind, SyncActionKind.createRight);
      expect(plan.actions.single.isDirectory, isTrue);
    });

    test('removes a directory deleted on the other side', () {
      final plan = SyncPlanner.plan(
        base: _manifest({'empty': _dir()}),
        a: _manifest({'empty': _dir()}),
        b: _manifest({}),
      );

      expect(plan.actions.single.kind, SyncActionKind.deleteLeft);
      expect(plan.actions.single.isDirectory, isTrue);
    });

    test('directory mtime differences are ignored', () {
      final plan = SyncPlanner.plan(
        base: _manifest({'dir': _dir(mtime: 1)}),
        a: _manifest({'dir': _dir(mtime: 2)}),
        b: _manifest({'dir': _dir(mtime: 3)}),
      );

      expect(plan.isEmpty, isTrue);
    });
  });

  group('SyncPlanner per-side snapshots', () {
    test('uses the right snapshot when only B has synced before', () {
      // A (a new device) matches what B had at its last sync, while B has
      // moved on. A must download B's change instead of reporting a conflict.
      final plan = SyncPlanner.plan(
        base: _manifest({}),
        baseB: _manifest({'f.txt': _file('old')}),
        a: _manifest({'f.txt': _file('old')}),
        b: _manifest({'f.txt': _file('new')}),
      );

      expect(plan.conflicts, isEmpty);
      expect(plan.actions.single.kind, SyncActionKind.updateLeft);
    });

    test('uses the left snapshot when only A has synced before', () {
      final plan = SyncPlanner.plan(
        base: _manifest({'f.txt': _file('old')}),
        baseB: _manifest({}),
        a: _manifest({'f.txt': _file('new')}),
        b: _manifest({'f.txt': _file('old')}),
      );

      expect(plan.conflicts, isEmpty);
      expect(plan.actions.single.kind, SyncActionKind.updateRight);
    });

    test('detects a deletion when the surviving side owns the snapshot', () {
      final plan = SyncPlanner.plan(
        base: _manifest({}),
        baseB: _manifest({'f.txt': _file('x')}),
        a: _manifest({'f.txt': _file('x')}),
        b: _manifest({}),
      );

      expect(plan.conflicts, isEmpty);
      expect(plan.actions.single.kind, SyncActionKind.deleteLeft);
    });

    test('still reports a conflict when both sides changed', () {
      final plan = SyncPlanner.plan(
        base: _manifest({'f.txt': _file('old')}),
        baseB: _manifest({'f.txt': _file('old')}),
        a: _manifest({'f.txt': _file('a')}),
        b: _manifest({'f.txt': _file('b')}),
      );

      expect(plan.actions, isEmpty);
      expect(plan.conflicts.single.reason, ConflictReason.bothModified);
    });
  });

  test('plan counts actions by category', () {
    final plan = SyncPlanner.plan(
      base: _manifest({'changed.txt': _file('old'), 'gone.txt': _file('x')}),
      a: _manifest({
        'changed.txt': _file('new'),
        'added.txt': _file('a'),
        'gone.txt': _file('x'),
      }),
      b: _manifest({'changed.txt': _file('old')}),
    );

    expect(plan.createCount, 1);
    expect(plan.updateCount, 1);
    expect(plan.deleteCount, 1);
  });
}
