import 'dart:convert';
import 'dart:io';

import 'package:file_sync_pro/features/sync/application/plan_applier.dart';
import 'package:file_sync_pro/features/sync/data/file_store.dart';
import 'package:file_sync_pro/features/sync/data/local_scanner.dart';
import 'package:file_sync_pro/features/sync/domain/line_endings.dart';
import 'package:file_sync_pro/features/sync/domain/sync_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('filesync-apply-');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('normalizes text files to LF when copying', () async {
    final source = Directory(p.join(temp.path, 'a'))..createSync();
    final target = Directory(p.join(temp.path, 'b'))..createSync();
    File(p.join(source.path, 'doc.md'))
        .writeAsBytesSync(utf8.encode('alpha\r\nbeta\r\n'));
    File(p.join(source.path, 'bin.dat')).writeAsBytesSync(const [0, 13, 10, 1]);

    final manifest = await LocalScanner().scan(source.path);
    final applier = PlanApplier(
      a: LocalFileStore(source.path),
      b: LocalFileStore(target.path),
    );

    await applier.apply(
      SyncPlan(
        actions: [
          SyncAction(
            kind: SyncActionKind.createRight,
            path: 'doc.md',
            reason: ActionReason.created,
            entry: manifest.entries['doc.md']!,
          ),
          SyncAction(
            kind: SyncActionKind.createRight,
            path: 'bin.dat',
            reason: ActionReason.created,
            entry: manifest.entries['bin.dat']!,
          ),
        ],
        conflicts: const [],
      ),
    );

    expect(
      File(p.join(target.path, 'doc.md')).readAsBytesSync(),
      utf8.encode('alpha\nbeta\n'),
    );
    expect(File(p.join(target.path, 'bin.dat')).readAsBytesSync(), const [
      0,
      13,
      10,
      1,
    ]);
  });

  test('normalizer handles CRLF split across chunks', () {
    final normalizer = LineEndingNormalizer();
    final out = <int>[];
    out.addAll(normalizer.add(const [0x61, 0x0D]));
    out.addAll(normalizer.add(const [0x0A, 0x62]));
    out.addAll(normalizer.finish());
    expect(out, [0x61, 0x0A, 0x62]);
  });
}
