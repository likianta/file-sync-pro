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

  void remove(String path);

  void removeWhere(bool Function(String path) test);

  Future<void> flush();
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

  Future<Manifest> scan(
    String root, {
    String? subPath,
    void Function(int scanned)? onProgress,
  }) async {
    final rootDirectory = Directory(root);
    if (!await rootDirectory.exists()) {
      throw StateError('Sync root does not exist: $root');
    }

    final normalized = _normalizeSubPath(subPath);
    final scanRoot = normalized.isEmpty
        ? root
        : p.joinAll([root, ...normalized.split('/')]);
    final type = await FileSystemEntity.type(scanRoot, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      // The selected node may exist only on the other side. Treat it as
      // absent here so the planner can still produce a create action.
      return Manifest(
        root: p.normalize(p.absolute(root)),
        scannedAt: DateTime.now(),
        entries: const {},
      );
    }
    if (type == FileSystemEntityType.link) {
      throw StateError('Symbolic links are not supported: $scanRoot');
    }

    final entries = <String, ManifestEntry>{};
    var lastReported = 0;
    void reportProgress() {
      if (entries.length - lastReported < 200) return;
      lastReported = entries.length;
      onProgress?.call(entries.length);
    }

    String fullPathOf(String relPath) =>
        normalized.isEmpty ? relPath : '$normalized/$relPath';

    if (type == FileSystemEntityType.file) {
      final file = File(scanRoot);
      entries[normalized] = await _fileEntry(file.path, await file.stat());
      onProgress?.call(entries.length);
      await hashCache?.flush();
      return Manifest(
        root: p.normalize(p.absolute(root)),
        scannedAt: DateTime.now(),
        entries: entries,
      );
    }

    final directory = Directory(scanRoot);
    if (normalized.isNotEmpty) {
      final stat = await directory.stat();
      entries[normalized] = ManifestEntry.directory(
        mtimeMs: stat.modified.millisecondsSinceEpoch,
      );
    }

    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      final relPath = _relativePath(entity.path, directory.path);
      if (relPath.isEmpty) continue;

      final entityType = await FileSystemEntity.type(
        entity.path,
        followLinks: false,
      );
      if (entityType == FileSystemEntityType.link) {
        // Symlinks are skipped for now: syncing them safely needs platform
        // specific handling and a clear policy.
        continue;
      }

      final isDirectory = entityType == FileSystemEntityType.directory;
      final fullPath = fullPathOf(relPath);
      if (ignores.ignores(fullPath, isDirectory: isDirectory)) {
        continue;
      }
      if (!isDirectory && entityType != FileSystemEntityType.file) {
        continue;
      }

      final stat = await entity.stat();
      if (isDirectory) {
        entries[fullPath] = ManifestEntry.directory(
          mtimeMs: stat.modified.millisecondsSinceEpoch,
        );
        reportProgress();
        continue;
      }

      entries[fullPath] = await _fileEntry(entity.path, stat);
      reportProgress();
    }

    onProgress?.call(entries.length);
    await hashCache?.flush();
    return Manifest(
      root: p.normalize(p.absolute(root)),
      scannedAt: DateTime.now(),
      entries: entries,
    );
  }

  Future<ManifestEntry> _fileEntry(String path, FileStat stat) async {
    final mtimeMs = stat.modified.millisecondsSinceEpoch;
    final shouldHash =
        computeHashes && (maxHashSize == null || stat.size <= maxHashSize!);
    String? hash;
    String? textHash;
    if (shouldHash) {
      final cached = hashCache?.lookup(path, stat.size, mtimeMs);
      if (cached != null) {
        hash = cached.hash;
        textHash = cached.textHash;
      } else {
        final result = await _hashFile(path);
        hash = result.hash;
        textHash = result.textHash;
        hashCache?.store(path, stat.size, mtimeMs, hash, textHash);
      }
    }
    return ManifestEntry.file(
      size: stat.size,
      mtimeMs: mtimeMs,
      hash: hash,
      textHash: textHash,
    );
  }

  static String _normalizeSubPath(String? subPath) {
    if (subPath == null) return '';
    var path = subPath.replaceAll('\\', '/').trim();
    while (path.startsWith('/')) {
      path = path.substring(1);
    }
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return path;
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
