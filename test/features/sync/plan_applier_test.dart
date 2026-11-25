import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_sync_pro/features/sync/application/plan_applier.dart';
import 'package:file_sync_pro/features/sync/data/file_store.dart';
import 'package:file_sync_pro/features/sync/data/local_scanner.dart';
import 'package:file_sync_pro/features/sync/domain/line_endings.dart';
import 'package:file_sync_pro/features/sync/domain/manifest.dart';
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

  test('small files are copied on several lanes', () async {
    final source = _MemoryStore();
    final target = _MemoryStore(writeDelay: const Duration(milliseconds: 30));
    final actions = <SyncAction>[
      for (var i = 0; i < 8; i++)
        _createAction(source, 'small-$i.bin', 4 * 1024),
    ];

    await PlanApplier(
      a: source,
      b: target,
    ).apply(SyncPlan(actions: actions, conflicts: const []));

    expect(target.maxActiveWrites, 4);
    expect(target.files, hasLength(8));
  });

  test('large files are copied one at a time', () async {
    final source = _MemoryStore();
    final target = _MemoryStore(writeDelay: const Duration(milliseconds: 30));
    final actions = <SyncAction>[
      _createAction(source, 'large-a.bin', 9 * 1024 * 1024),
      _createAction(source, 'large-b.bin', 9 * 1024 * 1024),
    ];

    await PlanApplier(
      a: source,
      b: target,
    ).apply(SyncPlan(actions: actions, conflicts: const []));

    expect(target.maxActiveWrites, 1);
    expect(target.files, hasLength(2));
  });
}

SyncAction _createAction(_MemoryStore source, String path, int size) {
  source.files[path] = Uint8List(size);
  return SyncAction(
    kind: SyncActionKind.createRight,
    path: path,
    reason: ActionReason.created,
    entry: ManifestEntry.file(size: size, mtimeMs: 1000, hash: 'x64:test'),
  );
}

/// In-memory [FileStore] that records how many writes overlap.
final class _MemoryStore implements FileStore {
  _MemoryStore({this.writeDelay = Duration.zero});

  final Duration writeDelay;
  final Map<String, List<int>> files = {};
  int _activeWrites = 0;
  int maxActiveWrites = 0;

  @override
  String get root => 'memory://';

  @override
  Future<bool> exists(String relPath) async => files.containsKey(relPath);

  @override
  Future<FileInfo> stat(String relPath) async {
    final data = files[relPath];
    if (data == null) {
      throw FileSystemException('Missing file', relPath);
    }
    return FileInfo(isDirectory: false, size: data.length, mtimeMs: 1000);
  }

  @override
  Stream<List<int>> openRead(String relPath) async* {
    final data = files[relPath]!;
    const chunkSize = 64 * 1024;
    for (var offset = 0; offset < data.length; offset += chunkSize) {
      final end = offset + chunkSize;
      yield Uint8List.sublistView(
        data as Uint8List,
        offset,
        end > data.length ? data.length : end,
      );
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Future<void> writeAtomically(
    String relPath,
    Stream<List<int>> data, {
    required DateTime modified,
  }) async {
    _activeWrites++;
    if (_activeWrites > maxActiveWrites) {
      maxActiveWrites = _activeWrites;
    }
    try {
      await Future<void>.delayed(writeDelay);
      final builder = BytesBuilder(copy: false);
      await for (final chunk in data) {
        builder.add(chunk);
      }
      files[relPath] = builder.takeBytes();
    } finally {
      _activeWrites--;
    }
  }

  @override
  Future<void> deleteFile(String relPath) async {
    files.remove(relPath);
  }

  @override
  Future<void> ensureDirectory(String relPath) async {}

  @override
  Future<bool> deleteDirectoryIfEmpty(String relPath) async => false;
}
