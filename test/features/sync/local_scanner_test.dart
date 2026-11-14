import 'dart:io';

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

  test('throws when the root does not exist', () async {
    await expectLater(
      LocalScanner().scan(p.join(temp.path, 'missing')),
      throwsA(isA<StateError>()),
    );
  });
}
