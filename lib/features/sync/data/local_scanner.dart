/// Local filesystem scanner producing a [Manifest].
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../domain/file_fingerprint.dart';
import '../domain/ignore_rules.dart';
import '../domain/manifest.dart';

/// Cached content hashes for one file.
typedef CachedHashes = ({String hash, String? textHash});

/// Progress callback: entries completed and total entries when known.
typedef ScanProgressCallback = void Function(int scanned, int? total);

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
    this.maxWorkers,
  }) : ignores = ignores ?? IgnoreRules.defaults();

  final IgnoreRules ignores;

  /// Whether to compute content fingerprints for file entries.
  final bool computeHashes;

  /// Files larger than this size are recorded without a hash. Null means no
  /// limit.
  final int? maxHashSize;

  final HashCache? hashCache;

  /// Overrides the isolate worker count. Defaults to
  /// `min(Platform.numberOfProcessors, 8)` for non-trivial scans.
  final int? maxWorkers;

  Future<Manifest> scan(
    String root, {
    String? subPath,
    ScanProgressCallback? onProgress,
  }) async {
    onProgress?.call(0, null);

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
    final pending = <_HashJob>[];
    var processed = 0;
    var lastReported = -1;

    void reportProgress({int? total, bool force = false}) {
      if (!force && processed - lastReported < 50) return;
      lastReported = processed;
      onProgress?.call(processed, total);
    }

    String fullPathOf(String relPath) =>
        normalized.isEmpty ? relPath : '$normalized/$relPath';

    bool shouldHash(int size) {
      return computeHashes && (maxHashSize == null || size <= maxHashSize!);
    }

    if (type == FileSystemEntityType.file) {
      final file = File(scanRoot);
      final stat = await file.stat();
      final entry = await _fileEntry(file.path, stat);
      entries[normalized] = entry;
      onProgress?.call(1, 1);
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
      processed++;
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
        processed++;
        reportProgress();
        continue;
      }

      final size = stat.size;
      final mtimeMs = stat.modified.millisecondsSinceEpoch;
      if (!shouldHash(size)) {
        entries[fullPath] = ManifestEntry.file(size: size, mtimeMs: mtimeMs);
        processed++;
        reportProgress();
        continue;
      }

      final cached = hashCache?.lookup(entity.path, size, mtimeMs);
      if (cached != null) {
        entries[fullPath] = ManifestEntry.file(
          size: size,
          mtimeMs: mtimeMs,
          hash: cached.hash,
          textHash: cached.textHash,
        );
        processed++;
        reportProgress();
        continue;
      }

      pending.add((
        path: entity.path,
        relPath: fullPath,
        size: size,
        mtimeMs: mtimeMs,
      ));
    }

    final total = processed + pending.length;
    onProgress?.call(processed, total);

    if (pending.isNotEmpty) {
      // Largest files first keeps the isolate workers balanced when a folder
      // mixes small photos with large videos.
      pending.sort((a, b) => b.size.compareTo(a.size));
      final workers = _workerCount(pending.length, maxWorkers);
      if (workers <= 1) {
        for (final job in pending) {
          final result = await _hashJob(job);
          _applyResult(entries, result);
          processed++;
          reportProgress(total: total);
        }
      } else {
        final chunks = _splitJobs(pending, 100);
        var nextChunk = 0;
        Future<void> worker() async {
          while (true) {
            final index = nextChunk++;
            if (index >= chunks.length) break;
            final chunk = chunks[index];
            final results = await _runHashChunk(chunk);
            for (final result in results) {
              _applyResult(entries, result);
              hashCache?.store(
                result.path,
                result.size,
                result.mtimeMs,
                result.hash,
                result.textHash,
              );
              processed++;
            }
            reportProgress(total: total);
          }
        }

        await Future.wait(List.generate(workers, (_) => worker()));
      }
    }

    onProgress?.call(total, total);
    await hashCache?.flush();
    return Manifest(
      root: p.normalize(p.absolute(root)),
      scannedAt: DateTime.now(),
      entries: entries,
    );
  }

  Future<ManifestEntry> _fileEntry(String path, FileStat stat) async {
    final mtimeMs = stat.modified.millisecondsSinceEpoch;
    final size = stat.size;
    if (!computeHashes || (maxHashSize != null && size > maxHashSize!)) {
      return ManifestEntry.file(size: size, mtimeMs: mtimeMs);
    }
    final cached = hashCache?.lookup(path, size, mtimeMs);
    if (cached != null) {
      return ManifestEntry.file(
        size: size,
        mtimeMs: mtimeMs,
        hash: cached.hash,
        textHash: cached.textHash,
      );
    }
    final result = await _hashJob((
      path: path,
      relPath: '',
      size: size,
      mtimeMs: mtimeMs,
    ));
    return ManifestEntry.file(
      size: size,
      mtimeMs: mtimeMs,
      hash: result.hash,
      textHash: result.textHash,
    );
  }

  Future<_HashResult> _hashJob(_HashJob job) async {
    final fingerprint = await fingerprintFile(job.path, size: job.size);
    hashCache?.store(
      job.path,
      job.size,
      job.mtimeMs,
      fingerprint.hash,
      fingerprint.textHash,
    );
    return (
      path: job.path,
      relPath: job.relPath,
      size: job.size,
      mtimeMs: job.mtimeMs,
      hash: fingerprint.hash,
      textHash: fingerprint.textHash,
    );
  }

  static void _applyResult(
    Map<String, ManifestEntry> entries,
    _HashResult result,
  ) {
    entries[result.relPath] = ManifestEntry.file(
      size: result.size,
      mtimeMs: result.mtimeMs,
      hash: result.hash,
      textHash: result.textHash,
    );
  }

  static int _workerCount(int pending, int? configured) {
    if (pending < 32) return 1;
    final count = configured ?? min(Platform.numberOfProcessors, 8);
    return count.clamp(1, 8);
  }

  static List<List<_HashJob>> _splitJobs(List<_HashJob> jobs, int size) {
    final chunks = <List<_HashJob>>[];
    for (var offset = 0; offset < jobs.length; offset += size) {
      chunks.add(jobs.sublist(offset, min(offset + size, jobs.length)));
    }
    return chunks;
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
}

typedef _HashJob = ({String path, String relPath, int size, int mtimeMs});

typedef _HashResult = ({
  String path,
  String relPath,
  int size,
  int mtimeMs,
  String hash,
  String? textHash,
});

Future<List<_HashResult>> _hashChunk(List<_HashJob> jobs) async {
  final results = <_HashResult>[];
  for (final job in jobs) {
    final fingerprint = await fingerprintFile(job.path, size: job.size);
    results.add((
      path: job.path,
      relPath: job.relPath,
      size: job.size,
      mtimeMs: job.mtimeMs,
      hash: fingerprint.hash,
      textHash: fingerprint.textHash,
    ));
  }
  return results;
}

/// Runs one chunk in a worker isolate.
///
/// This wrapper exists so the isolate closure only captures [jobs]. Inlining
/// `Isolate.run` inside `scan` would capture the enclosing scope, including
/// `onProgress` callbacks that may hold widget state and cannot be sent
/// across isolates.
Future<List<_HashResult>> _runHashChunk(List<_HashJob> jobs) {
  return Isolate.run(() => _hashChunk(jobs));
}
