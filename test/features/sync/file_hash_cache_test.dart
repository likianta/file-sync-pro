import 'dart:convert';
import 'dart:io';

import 'package:file_sync_pro/features/sync/data/file_hash_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('filesync-hash-cache-');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('persists entries across instances', () async {
    final path = p.join(temp.path, 'cache.json');
    final cache = FileHashCache(path);
    cache.store('/a.txt', 3, 100, 'raw', 'text');
    await cache.flush();

    final reopened = FileHashCache(path);
    expect(reopened.lookup('/a.txt', 3, 100), (hash: 'raw', textHash: 'text'));
    expect(reopened.lookup('/a.txt', 4, 100), isNull);
    expect(reopened.lookup('/a.txt', 3, 101), isNull);
  });

  test('flushes nothing when there are no changes', () async {
    final path = p.join(temp.path, 'cache.json');
    await FileHashCache(path).flush();

    expect(File(path).existsSync(), isFalse);
  });

  test('removes entries by path and predicate', () async {
    final cache = FileHashCache(p.join(temp.path, 'cache.json'));
    cache.store('/root/a.txt', 1, 1, 'a', null);
    cache.store('/root/b.txt', 1, 1, 'b', null);
    cache.store('/other/c.txt', 1, 1, 'c', null);

    cache.remove('/root/a.txt');
    cache.removeWhere((key) => key.startsWith('/root/'));

    expect(cache.lookup('/root/a.txt', 1, 1), isNull);
    expect(cache.lookup('/root/b.txt', 1, 1), isNull);
    expect(cache.lookup('/other/c.txt', 1, 1), isNotNull);
  });

  test('rebuilds after reading a corrupt cache file', () async {
    final path = p.join(temp.path, 'cache.json');
    await File(path).writeAsString('not json');

    final cache = FileHashCache(path);
    expect(cache.lookup('/a.txt', 1, 1), isNull);

    cache.store('/a.txt', 1, 1, 'a', null);
    await cache.flush();

    final reopened = FileHashCache(path);
    expect(reopened.lookup('/a.txt', 1, 1)?.hash, 'a');
    expect(
      jsonDecode(await File(path).readAsString()),
      containsPair('version', FileHashCache.version),
    );
  });
}
