/// Local filesystem scanner producing a [Manifest].
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../domain/ignore_rules.dart';
import '../domain/manifest.dart';

final class LocalScanner {
  LocalScanner({
    IgnoreRules? ignores,
    this.computeHashes = true,
    this.maxHashSize,
  }) : ignores = ignores ?? IgnoreRules.defaults();

  final IgnoreRules ignores;

  /// Whether to compute SHA-256 for file entries.
  final bool computeHashes;

  /// Files larger than this size are recorded without a hash. Null means no
  /// limit.
  final int? maxHashSize;

  Future<Manifest> scan(String root) async {
    final directory = Directory(root);
    if (!await directory.exists()) {
      throw StateError('Sync root does not exist: $root');
    }

    final entries = <String, ManifestEntry>{};
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      final relPath = _relativePath(entity.path, directory.path);
      if (relPath.isEmpty) continue;

      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.link) {
        // Symlinks are skipped for now: syncing them safely needs platform
        // specific handling and a clear policy.
        continue;
      }

      final isDirectory = type == FileSystemEntityType.directory;
      if (ignores.ignores(relPath, isDirectory: isDirectory)) {
        continue;
      }
      if (!isDirectory && type != FileSystemEntityType.file) {
        continue;
      }

      final stat = await entity.stat();
      final mtimeMs = stat.modified.millisecondsSinceEpoch;

      if (isDirectory) {
        entries[relPath] = ManifestEntry.directory(mtimeMs: mtimeMs);
        continue;
      }

      final shouldHash =
          computeHashes && (maxHashSize == null || stat.size <= maxHashSize!);
      entries[relPath] = ManifestEntry.file(
        size: stat.size,
        mtimeMs: mtimeMs,
        hash: shouldHash ? await _hashFile(entity.path) : null,
      );
    }

    return Manifest(
      root: p.normalize(p.absolute(root)),
      scannedAt: DateTime.now(),
      entries: entries,
    );
  }

  static String _relativePath(String path, String root) {
    final relative = p.relative(path, from: root);
    if (relative == '.' || relative.isEmpty) return '';
    return p.posix.joinAll(p.split(relative));
  }

  static Future<String> _hashFile(String path) async {
    final digest = await sha256.bind(File(path).openRead()).first;
    return digest.toString();
  }
}
