/// Local filesystem scanner producing a [Manifest].
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../domain/ignore_rules.dart';
import '../domain/line_endings.dart';
import '../domain/manifest.dart';

/// Cached content hashes for one file.
typedef CachedHashes = ({String hash, String? textHash});

/// Optional cache for content hashes. The server uses it to avoid re-hashing
/// unchanged files on every manifest request.
abstract interface class HashCache {
  CachedHashes? lookup(String path, int size, int mtimeMs);

  void store(String path, int size, int mtimeMs, String hash, String? textHash);
}

final class LocalScanner {
  LocalScanner({
    IgnoreRules? ignores,
    this.computeHashes = true,
    this.maxHashSize,
    this.hashCache,
  }) : ignores = ignores ?? IgnoreRules.defaults();

  final IgnoreRules ignores;

  /// Whether to compute SHA-256 for file entries.
  final bool computeHashes;

  /// Files larger than this size are recorded without a hash. Null means no
  /// limit.
  final int? maxHashSize;

  final HashCache? hashCache;

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
      String? hash;
      String? textHash;
      if (shouldHash) {
        final cached = hashCache?.lookup(entity.path, stat.size, mtimeMs);
        if (cached != null) {
          hash = cached.hash;
          textHash = cached.textHash;
        } else {
          final result = await _hashFile(entity.path);
          hash = result.hash;
          textHash = result.textHash;
          hashCache?.store(entity.path, stat.size, mtimeMs, hash, textHash);
        }
      }
      entries[relPath] = ManifestEntry.file(
        size: stat.size,
        mtimeMs: mtimeMs,
        hash: hash,
        textHash: textHash,
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

  /// Hashes the raw bytes and, for text files, the LF-normalized bytes.
  ///
  /// A file is treated as text when its first 8 KiB contain no NUL byte. This
  /// is the same heuristic Git uses. The normalized hash lets CRLF and LF
  /// copies of the same document compare equal without transferring them.
  static Future<({String hash, String? textHash})> _hashFile(
    String path,
  ) async {
    final file = await File(path).open();
    try {
      final probe = await file.read(8192);
      final isText = !probe.contains(0);
      await file.setPosition(0);

      final rawSink = _DigestSink();
      final rawInput = sha256.startChunkedConversion(rawSink);
      final normalizer = isText ? LineEndingNormalizer() : null;
      final textSink = isText ? _DigestSink() : null;
      final textInput = textSink == null
          ? null
          : sha256.startChunkedConversion(textSink);

      while (true) {
        final chunk = await file.read(64 * 1024);
        if (chunk.isEmpty) break;
        rawInput.add(chunk);
        if (textInput != null) {
          final normalized = normalizer!.add(chunk);
          if (normalized.isNotEmpty) textInput.add(normalized);
        }
      }

      rawInput.close();
      if (textInput != null) {
        final tail = normalizer!.finish();
        if (tail.isNotEmpty) textInput.add(tail);
        textInput.close();
      }
      return (
        hash: rawSink.value!.toString(),
        textHash: textSink?.value?.toString(),
      );
    } finally {
      await file.close();
    }
  }
}

final class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
