import 'package:file_sync_pro/features/sync/domain/manifest.dart';
import 'package:file_sync_pro/features/sync/presentation/sync_tree.dart';
import 'package:flutter_test/flutter_test.dart';

Manifest _manifest(Map<String, ManifestEntry> entries) {
  return Manifest(
    root: '',
    scannedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    entries: entries,
  );
}

void main() {
  test('builds folders before files and sorts by name', () {
    final tree = buildSyncTree(
      _manifest({
        'b.txt': ManifestEntry.file(size: 1, mtimeMs: 1, hash: 'b'),
        'a/folder.txt': ManifestEntry.file(size: 1, mtimeMs: 1, hash: 'f'),
        'a.txt': ManifestEntry.file(size: 1, mtimeMs: 1, hash: 'a'),
        'a': ManifestEntry.directory(mtimeMs: 1),
      }),
      rootName: 'demo',
    );

    expect(tree.root.children.map((node) => node.name), [
      'a',
      'a.txt',
      'b.txt',
    ]);
    expect(tree.root.children.first.isDirectory, isTrue);
  });

  test('creates missing parent folders defensively', () {
    final tree = buildSyncTree(
      _manifest({
        'docs/notes/todo.txt': ManifestEntry.file(
          size: 3,
          mtimeMs: 1,
          hash: 'x',
        ),
      }),
      rootName: 'demo',
    );

    final docs = tree.byPath['docs'];
    expect(docs, isNotNull);
    expect(docs!.isDirectory, isTrue);
    expect(tree.byPath['docs/notes']!.children.single.name, 'todo.txt');
  });

  test('reveal expands ancestors and visible rows follow expansion', () {
    final tree = buildSyncTree(
      _manifest({
        'docs/notes/todo.txt': ManifestEntry.file(
          size: 3,
          mtimeMs: 1,
          hash: 'x',
        ),
      }),
      rootName: 'demo',
    );

    expect(tree.visibleRows().map((row) => row.node.path), ['', 'docs']);
    expect(tree.reveal('docs/notes/todo.txt'), isNotNull);
    expect(tree.byPath['docs']!.expanded, isTrue);
    expect(tree.byPath['docs/notes']!.expanded, isTrue);
    expect(tree.visibleRows().map((row) => row.node.path), [
      '',
      'docs',
      'docs/notes',
      'docs/notes/todo.txt',
    ]);
  });
}
