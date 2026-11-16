import 'dart:convert';
import 'dart:io';

import 'package:file_sync_pro/features/sync/application/sync_engine.dart';
import 'package:file_sync_pro/features/sync/domain/sync_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final fixturesAvailable =
      Directory(p.join('test', 'local_sync_test', 'alice')).existsSync() &&
      Directory(p.join('test', 'local_sync_test', 'bob')).existsSync();

  group(
    'local sync (auxiliary)',
    () {
      late Directory temp;
      late Directory alice;
      late Directory bob;
      late String stateDir;

      setUp(() async {
        temp = await Directory.systemTemp.createTemp('filesync-local-');
        alice = Directory(p.join(temp.path, 'alice'));
        bob = Directory(p.join(temp.path, 'bob'));
        await _copyTree(_fixture('alice'), alice);
        await _copyTree(_fixture('bob'), bob);
        stateDir = p.join(temp.path, 'state');
      });

      tearDown(() async {
        await temp.delete(recursive: true);
      });

      SyncEngine engine() {
        return SyncEngine.local(
          rootA: alice.path,
          rootB: bob.path,
          stateDir: stateDir,
        );
      }

      test('first sync merges both sides and commits a base', () async {
        final report = await engine().sync();

        expect(report.hasConflicts, isFalse);
        expect(await _exists(bob, 'alice-only.txt'), isTrue);
        expect(await _exists(alice, 'bob-only.txt'), isTrue);
        expect(await _exists(bob, 'media/alice-note.md'), isTrue);
        expect(await _exists(alice, 'media/bob-note.md'), isTrue);

        final second = await engine().sync();
        expect(second.preview.plan.isEmpty, isTrue);
        expect(second.applyReport!.total, 0);
      });

      test('propagates edits', () async {
        await engine().sync();

        await _file(alice, 'docs/readme.md').writeAsString('edited by alice\n');
        await engine().sync();

        expect(await _read(bob, 'docs/readme.md'), 'edited by alice\n');
      });

      test('propagates deletions', () async {
        await engine().sync();

        await _file(bob, 'shared/common.txt').delete();
        await engine().sync();

        expect(await _exists(alice, 'shared/common.txt'), isFalse);
      });

      test('treats a rename as delete plus create', () async {
        await engine().sync();

        await _file(
          alice,
          'docs/notes/todo.txt',
        ).rename(_file(alice, 'docs/notes/done.txt').path);
        await engine().sync();

        expect(await _exists(bob, 'docs/notes/done.txt'), isTrue);
        expect(await _exists(bob, 'docs/notes/todo.txt'), isFalse);
        expect(
          await _read(bob, 'docs/notes/done.txt'),
          '- buy milk\n- ship the sync tool\n',
        );
      });

      test('does not rewrite a file when only mtime changed', () async {
        await engine().sync();

        final path = 'docs/readme.md';
        final content = await _read(alice, path);
        await _file(alice, path).writeAsString(content);
        await _file(
          alice,
          path,
        ).setLastModified(DateTime.now().add(const Duration(hours: 1)));

        final bobMtime = await _file(bob, path).lastModified();
        final report = await engine().sync();

        expect(report.preview.plan.actions, isEmpty);
        expect(await _file(bob, path).lastModified(), bobMtime);
      });

      test('reports a conflict when both sides modify a file', () async {
        await engine().sync();

        await _file(alice, 'docs/readme.md').writeAsString('alice edit\n');
        await _file(bob, 'docs/readme.md').writeAsString('bob edit\n');
        await _file(alice, 'extra.txt').writeAsString('extra\n');

        final report = await engine().sync();

        expect(report.hasConflicts, isTrue);
        expect(report.conflictCount, 1);
        expect(
          report.preview.plan.conflicts.single.reason,
          ConflictReason.bothModified,
        );

        // Conflicting content is left untouched on both sides.
        expect(await _read(alice, 'docs/readme.md'), 'alice edit\n');
        expect(await _read(bob, 'docs/readme.md'), 'bob edit\n');

        // Non-conflicting work still happens.
        expect(await _read(bob, 'extra.txt'), 'extra\n');

        final backup = report.conflictBackupRoot!;
        expect(
          await File(p.join(backup, 'a', 'docs', 'readme.md')).readAsString(),
          'alice edit\n',
        );
        expect(
          await File(p.join(backup, 'b', 'docs', 'readme.md')).readAsString(),
          'bob edit\n',
        );

        // The same conflict is reported again on the next run.
        final again = await engine().preview();
        expect(again.plan.conflicts, hasLength(1));
      });

      test(
        'reports a conflict when one side modifies and the other deletes',
        () async {
          await engine().sync();

          await _file(bob, 'docs/readme.md').delete();
          await _file(
            alice,
            'docs/readme.md',
          ).writeAsString('alice keeps it\n');

          final report = await engine().sync();

          expect(report.conflictCount, 1);
          expect(
            report.preview.plan.conflicts.single.reason,
            ConflictReason.modifiedVsDeleted,
          );
          expect(await _read(alice, 'docs/readme.md'), 'alice keeps it\n');
          expect(await _exists(bob, 'docs/readme.md'), isFalse);

          final backup = report.conflictBackupRoot!;
          expect(
            await File(p.join(backup, 'a', 'docs', 'readme.md')).exists(),
            isTrue,
          );
        },
      );

      test('resolves every conflict with one side in one call', () async {
        await engine().sync();

        await _file(alice, 'docs/readme.md').writeAsString('alice edit\n');
        await _file(bob, 'docs/readme.md').writeAsString('bob edit\n');
        await _file(
          alice,
          'media/alice-note.md',
        ).writeAsString('alice note edit\n');
        await _file(
          bob,
          'media/alice-note.md',
        ).writeAsString('bob note edit\n');

        final report = await engine().sync();
        expect(report.conflictCount, 2);

        final resolving = engine();
        final preview = await resolving.preview();
        final result = await resolving.resolveConflicts(preview, {
          for (final conflict in preview.plan.conflicts)
            conflict.path: ConflictSide.left,
        });

        expect(result.resolved, 2);
        expect(result.remaining, 0);
        expect(await _read(bob, 'docs/readme.md'), 'alice edit\n');
        expect(await _read(bob, 'media/alice-note.md'), 'alice note edit\n');

        final after = await engine().preview();
        expect(after.plan.conflicts, isEmpty);
      });

      test('writes a snapshot into each synced folder', () async {
        await engine().sync();

        final aliceShot = File(p.join(alice.path, '.file_sync_shot.json'));
        final bobShot = File(p.join(bob.path, '.file_sync_shot.json'));
        expect(await aliceShot.exists(), isTrue);
        expect(await bobShot.exists(), isTrue);

        final json =
            jsonDecode(await aliceShot.readAsString()) as Map<String, Object?>;
        expect(json['schema'], 1);
        final entries = (json['entries'] as Map).cast<String, Object?>();
        expect(entries.containsKey('docs/readme.md'), isTrue);
        expect(entries.containsKey('.file_sync_shot.json'), isFalse);

        // Snapshots never take part in the sync itself.
        final preview = await engine().preview();
        expect(preview.a.entries.containsKey('.file_sync_shot.json'), isFalse);
        expect(preview.b.entries.containsKey('.file_sync_shot.json'), isFalse);
        expect(preview.plan.isEmpty, isTrue);
      });

      test('a new device reuses the peer snapshot after a sync', () async {
        await engine().sync();

        // Carol starts from Bob's last synced state, like a Windows machine
        // that already has the same folder but has never run a sync.
        final carol = Directory(p.join(temp.path, 'carol'));
        await _copyTree(bob, carol);
        await File(p.join(carol.path, '.file_sync_shot.json')).delete();

        // Bob changes one file after the previous sync.
        await _file(
          bob,
          'docs/readme.md',
        ).writeAsString('bob after home sync\n');

        final carolBob = SyncEngine.local(
          rootA: carol.path,
          rootB: bob.path,
          stateDir: p.join(temp.path, 'state-carol'),
        );
        final report = await carolBob.sync();

        expect(report.preview.plan.conflicts, isEmpty);
        expect(report.preview.baseA.isEmpty, isTrue);
        expect(report.preview.baseB.isEmpty, isFalse);
        expect(await _read(carol, 'docs/readme.md'), 'bob after home sync\n');
        expect(
          await File(p.join(carol.path, '.file_sync_shot.json')).exists(),
          isTrue,
        );
        expect(
          await File(p.join(bob.path, '.file_sync_shot.json')).exists(),
          isTrue,
        );
      });

      test('syncs only the selected subtree', () async {
        await engine().sync();

        await _file(alice, 'docs/readme.md').writeAsString('docs edit\n');
        await _file(alice, 'media/alice-note.md').writeAsString('media edit\n');

        final scoped = engine();
        final preview = await scoped.preview();
        final report = await scoped.execute(preview, subPath: 'docs');

        expect(report.plan.actions, isNotEmpty);
        expect(
          report.plan.actions.every(
            (action) => action.path.startsWith('docs/'),
          ),
          isTrue,
        );
        expect(await _read(bob, 'docs/readme.md'), 'docs edit\n');
        expect(await _read(bob, 'media/alice-note.md'), isNot('media edit\n'));

        // The untouched subtree is still pending, while docs is settled.
        final after = await engine().preview();
        expect(after.plan.actions.map((action) => action.path), [
          'media/alice-note.md',
        ]);
      });

      test('push copies the selected subtree from left to right', () async {
        await engine().sync();

        await _file(alice, 'docs/readme.md').writeAsString('alice docs\n');
        await _file(bob, 'shared/common.txt').writeAsString('bob shared\n');

        final pushing = engine();
        final preview = await pushing.preview();
        final report = await pushing.execute(
          preview,
          direction: SyncDirection.push,
          subPath: 'docs',
        );

        expect(report.plan.conflicts, isEmpty);
        expect(await _read(bob, 'docs/readme.md'), 'alice docs\n');
        expect(await _read(bob, 'shared/common.txt'), 'bob shared\n');

        final after = await engine().preview();
        expect(after.plan.actions.map((action) => action.path), [
          'shared/common.txt',
        ]);
        expect(after.plan.conflicts, isEmpty);
      });

      test('pull copies the selected subtree from right to left', () async {
        await engine().sync();

        await _file(bob, 'docs/readme.md').writeAsString('bob docs\n');

        final pulling = engine();
        final preview = await pulling.preview();
        await pulling.execute(
          preview,
          direction: SyncDirection.pull,
          subPath: 'docs',
        );

        expect(await _read(alice, 'docs/readme.md'), 'bob docs\n');
      });

      test('push resolves conflicts in favor of the left side', () async {
        await engine().sync();

        await _file(alice, 'docs/readme.md').writeAsString('alice wins\n');
        await _file(bob, 'docs/readme.md').writeAsString('bob loses\n');

        final pushing = engine();
        final preview = await pushing.preview();
        expect(preview.plan.conflicts, hasLength(1));

        final report = await pushing.execute(
          preview,
          direction: SyncDirection.push,
          subPath: 'docs',
        );

        expect(report.plan.conflicts, isEmpty);
        expect(await _read(bob, 'docs/readme.md'), 'alice wins\n');

        final after = await engine().preview();
        expect(after.plan.conflicts, isEmpty);
        expect(after.plan.actions, isEmpty);
      });

      test('syncs empty directories and removes them again', () async {
        await engine().sync();

        final emptyDir = Directory(p.join(alice.path, 'empty', 'nested'));
        await emptyDir.create(recursive: true);

        await engine().sync();
        expect(
          await Directory(p.join(bob.path, 'empty', 'nested')).exists(),
          isTrue,
        );

        await Directory(p.join(alice.path, 'empty')).delete(recursive: true);
        await engine().sync();

        expect(await Directory(p.join(bob.path, 'empty')).exists(), isFalse);
      });

      test('respects default ignore rules', () async {
        await engine().sync();

        await Directory(p.join(alice.path, '.git')).create();
        await File(p.join(alice.path, '.git', 'config')).writeAsString('x');
        await File(p.join(alice.path, 'backup~')).writeAsString('x');
        await File(p.join(alice.path, '.DS_Store')).writeAsString('x');

        await engine().sync();

        expect(await _exists(bob, '.git/config'), isFalse);
        expect(await _exists(bob, 'backup~'), isFalse);
        expect(await _exists(bob, '.DS_Store'), isFalse);

        final preview = await engine().preview();
        expect(preview.a.entries.containsKey('.git'), isFalse);
        expect(preview.a.entries.containsKey('backup~'), isFalse);
      });

      test('dry run reports changes without touching the disk', () async {
        await engine().sync();

        await _file(alice, 'docs/readme.md').writeAsString('not applied yet\n');

        final preview = await engine().sync(dryRun: true);
        expect(preview.preview.plan.actions, isNotEmpty);
        expect(await _read(bob, 'docs/readme.md'), isNot('not applied yet\n'));

        await engine().sync();
        expect(await _read(bob, 'docs/readme.md'), 'not applied yet\n');
      });

      test('verifies convergence after applying a plan', () async {
        await engine().sync();

        final report = await engine().sync();
        expect(report.preview.plan.isEmpty, isTrue);
        expect(report.applyReport!.created, 0);
        expect(report.applyReport!.updated, 0);
        expect(report.applyReport!.deleted, 0);
      });
    },
    skip: fixturesAvailable
        ? false
        : 'test/local_sync_test fixtures are gitignored and not present.',
  );
}

Directory _fixture(String name) {
  return Directory(p.join('test', 'local_sync_test', name));
}

File _file(Directory root, String relPath) {
  return File(p.joinAll([root.path, ...relPath.split('/')]));
}

Future<String> _read(Directory root, String relPath) {
  return _file(root, relPath).readAsString();
}

Future<bool> _exists(Directory root, String relPath) {
  return _file(root, relPath).exists();
}

Future<void> _copyTree(Directory source, Directory target) async {
  await target.create(recursive: true);
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final relPath = p.relative(entity.path, from: source.path);
    final targetPath = p.join(target.path, relPath);
    if (entity is Directory) {
      await Directory(targetPath).create(recursive: true);
    } else if (entity is File) {
      await Directory(p.dirname(targetPath)).create(recursive: true);
      await entity.copy(targetPath);
    }
  }
}
