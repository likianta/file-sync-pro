import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:file_sync_pro/features/sync/data/file_hash_cache.dart';
import 'package:file_sync_pro/features/sync/data/local_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('filesync-scan-');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('scans files and directories with hashes', () async {
    await Directory(p.join(temp.path, 'sub')).create();
    await File(p.join(temp.path, 'sub', 'a.txt')).writeAsString('hello');
    await File(p.join(temp.path, 'root.txt')).writeAsString('');

    final manifest = await LocalScanner().scan(temp.path);

    expect(manifest.entries.keys, ['root.txt', 'sub', 'sub/a.txt']);
    expect(manifest.entries['sub']!.isDirectory, isTrue);
    expect(manifest.entries['root.txt']!.size, 0);
    expect(manifest.entries['root.txt']!.hash, isNotNull);
    expect(manifest.entries['sub/a.txt']!.size, 5);
    expect(manifest.entries['sub/a.txt']!.hash, isNotNull);
    expect(manifest.fileCount, 2);
    expect(manifest.directoryCount, 1);
  });

  test('skips ignored paths', () async {
    await File(p.join(temp.path, 'keep.txt')).writeAsString('keep');
    await Directory(p.join(temp.path, '.git')).create();
    await File(p.join(temp.path, '.git', 'config')).writeAsString('x');
    await File(p.join(temp.path, 'backup~')).writeAsString('x');

    final manifest = await LocalScanner().scan(temp.path);

    expect(manifest.entries.keys, ['keep.txt']);
  });

  test('omits hashes for files above the size limit', () async {
    await File(p.join(temp.path, 'small.txt')).writeAsString('abc');
    await File(p.join(temp.path, 'big.txt')).writeAsString('abcdef');

    final manifest = await LocalScanner(maxHashSize: 4).scan(temp.path);

    expect(manifest.entries['small.txt']!.hash, isNotNull);
    expect(manifest.entries['big.txt']!.hash, isNull);
  });

  test('normalizes line endings for text files', () async {
    await File(p.join(temp.path, 'lf.txt'))
        .writeAsBytes(utf8.encode('alpha\nbeta\ngamma\n'));
    await File(p.join(temp.path, 'crlf.txt'))
        .writeAsBytes(utf8.encode('alpha\r\nbeta\r\ngamma\r\n'));
    await File(p.join(temp.path, 'binary-a.bin'))
        .writeAsBytes(const [0, 13, 10, 1]);
    await File(p.join(temp.path, 'binary-b.bin'))
        .writeAsBytes(const [0, 10, 1]);

    final manifest = await LocalScanner().scan(temp.path);

    final lf = manifest.entries['lf.txt']!;
    final crlf = manifest.entries['crlf.txt']!;
    expect(lf.hash, isNot(crlf.hash));
    expect(lf.textHash, isNotNull);
    expect(lf.textHash, crlf.textHash);
    expect(lf.sameContent(crlf), isTrue);

    final binA = manifest.entries['binary-a.bin']!;
    final binB = manifest.entries['binary-b.bin']!;
    expect(binA.textHash, isNull);
    expect(binA.sameContent(binB), isFalse);
  });

  test('scans only the selected subtree with full relative paths', () async {
    await File(p.join(temp.path, 'root.txt')).writeAsString('root');
    await Directory(p.join(temp.path, 'docs', 'notes')).create(recursive: true);
    await File(p.join(temp.path, 'docs', 'notes', 'a.txt')).writeAsString('a');
    await File(p.join(temp.path, 'docs', 'info.txt')).writeAsString('i');

    final manifest = await LocalScanner().scan(
      temp.path,
      subPath: 'docs/notes',
    );

    expect(manifest.entries.keys, ['docs/notes', 'docs/notes/a.txt']);
    expect(manifest.entries['docs/notes']!.isDirectory, isTrue);
    expect(manifest.entries['docs/notes/a.txt']!.hash, isNotNull);
  });

  test('scans a single selected file', () async {
    await File(p.join(temp.path, 'root.txt')).writeAsString('root');

    final manifest = await LocalScanner().scan(temp.path, subPath: 'root.txt');

    expect(manifest.entries.keys, ['root.txt']);
    expect(manifest.entries['root.txt']!.size, 4);
    expect(manifest.entries['root.txt']!.hash, isNotNull);
  });

  test('reuses cached hashes keyed by size and mtime', () async {
    final file = File(p.join(temp.path, 'a.txt'));
    await file.writeAsString('hello');
    final stat = await file.stat();
    final cachePath = p.join(temp.path, 'cache.json');

    final seed = FileHashCache(cachePath);
    seed.store(
      file.path,
      stat.size,
      stat.modified.millisecondsSinceEpoch,
      'cached-hash',
      'cached-text',
    );
    await seed.flush();

    final manifest = await LocalScanner(hashCache: FileHashCache(cachePath))
        .scan(temp.path);

    expect(manifest.entries['a.txt']!.hash, 'cached-hash');
    expect(manifest.entries['a.txt']!.textHash, 'cached-text');
  });

  test('reports progress and finishes with the entry count', () async {
    for (var i = 0; i < 60; i++) {
      await File(p.join(temp.path, 'f$i.txt')).writeAsString('$i');
    }

    final reports = <(int, int?)>[];
    final manifest = await LocalScanner().scan(
      temp.path,
      onProgress: (scanned, total) => reports.add((scanned, total)),
    );

    expect(reports, isNotEmpty);
    expect(reports.first, (0, null));
    expect(reports.last, (60, 60));
    expect(manifest.entries.length, 60);
    expect(
      manifest.entries.values.every((entry) => entry.hash!.startsWith('x64')),
      isTrue,
    );
  });

  test('does not send progress callbacks into hash isolates', () async {
    for (var i = 0; i < 40; i++) {
      await File(p.join(temp.path, 'f$i.txt')).writeAsString('$i');
    }

    // ReceivePort cannot cross isolates. Capturing it in onProgress used to
    // leak into the worker isolate message and fail the whole scan.
    final port = ReceivePort();
    try {
      final manifest = await LocalScanner().scan(
        temp.path,
        onProgress: (scanned, total) => port.sendPort.send((scanned, total)),
      );
      expect(manifest.entries.length, 40);
    } finally {
      port.close();
    }
  });

  test('throws when the root does not exist', () async {
    await expectLater(
      LocalScanner().scan(p.join(temp.path, 'missing')),
      throwsA(isA<StateError>()),
    );
  });
}
