import 'package:file_sync_pro/features/sync/domain/manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Manifest JSON', () {
    test('round-trips entries', () {
      final manifest = Manifest(
        root: '/tmp/example',
        scannedAt: DateTime.utc(2026, 11, 14, 12, 0, 0),
        entries: {
          'docs': ManifestEntry.directory(mtimeMs: 1000),
          'docs/a.txt': ManifestEntry.file(size: 5, mtimeMs: 2000, hash: 'abc'),
          'empty.txt': ManifestEntry.file(size: 0, mtimeMs: 3000),
        },
      );

      final restored = Manifest.fromJson(manifest.toJson());

      expect(restored.root, manifest.root);
      expect(restored.scannedAt, manifest.scannedAt);
      expect(restored.entries.keys, manifest.entries.keys);
      expect(restored.entries['docs']!.isDirectory, isTrue);
      expect(restored.entries['docs/a.txt']!.hash, 'abc');
      expect(restored.entries['empty.txt']!.hash, isNull);
      expect(restored.fileCount, 2);
      expect(restored.directoryCount, 1);
    });

    test('accepts an empty manifest', () {
      final restored = Manifest.fromJson(
        Manifest.empty(root: '/tmp/empty').toJson(),
      );
      expect(restored.isEmpty, isTrue);
      expect(restored.root, '/tmp/empty');
    });
  });

  group('ManifestEntry.sameContent', () {
    test('uses hash when both sides have one', () {
      final a = ManifestEntry.file(size: 5, mtimeMs: 100, hash: 'same');
      final b = ManifestEntry.file(size: 5, mtimeMs: 999, hash: 'same');
      expect(a.sameContent(b), isTrue);
    });

    test('detects different hashes', () {
      final a = ManifestEntry.file(size: 5, mtimeMs: 100, hash: 'a');
      final b = ManifestEntry.file(size: 5, mtimeMs: 100, hash: 'b');
      expect(a.sameContent(b), isFalse);
    });

    test('falls back to size and mtime without hashes', () {
      final a = ManifestEntry.file(size: 5, mtimeMs: 100);
      final b = ManifestEntry.file(size: 5, mtimeMs: 100);
      final c = ManifestEntry.file(size: 5, mtimeMs: 200);
      expect(a.sameContent(b), isTrue);
      expect(a.sameContent(c), isFalse);
    });

    test('directories are equal by kind', () {
      final a = ManifestEntry.directory(mtimeMs: 1);
      final b = ManifestEntry.directory(mtimeMs: 2);
      expect(a.sameContent(b), isTrue);
    });

    test('null and different kinds are not equal', () {
      final file = ManifestEntry.file(size: 1, mtimeMs: 1, hash: 'x');
      final dir = ManifestEntry.directory(mtimeMs: 1);
      expect(file.sameContent(null), isFalse);
      expect(file.sameContent(dir), isFalse);
    });
  });
}
