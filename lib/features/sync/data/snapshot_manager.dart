/// Scans one folder and merges it into a side snapshot.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/ignore_rules.dart';
import '../domain/manifest.dart';
import '../domain/sync_snapshot.dart';
import 'local_scanner.dart';
import 'snapshot_store.dart';

final class SnapshotMissingException implements Exception {
  const SnapshotMissingException(this.side);

  final String side;

  @override
  String toString() => 'No snapshot on $side. Scan this pair first.';
}

final class SnapshotPathException implements Exception {
  const SnapshotPathException(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() => message;
}

final class SnapshotLegacyException implements Exception {
  const SnapshotLegacyException(this.side);

  final String side;

  @override
  String toString() => 'Snapshot on $side uses an old format.';
}

/// Owns the local filesystem side of snapshot scanning.
final class LocalSnapshotManager {
  LocalSnapshotManager({
    required this.root,
    required this.store,
    required this.ignores,
    this.hashCache,
  });

  final String root;
  final SnapshotStore store;
  final IgnoreRules ignores;
  final HashCache? hashCache;

  Future<SnapshotLoadResult> load() => store.load();

  Future<void> save(SideSnapshot snapshot) => store.save(snapshot);

  /// Scans [subPath] (empty means the root) and merges it into `current`.
  ///
  /// When no snapshot exists and [createIfMissing] is false, throws
  /// [SnapshotMissingException]. When the selected folder is gone, throws
  /// [SnapshotPathException] and leaves the snapshot untouched.
  Future<SideSnapshot> scan({
    String? subPath,
    bool createIfMissing = false,
    void Function(int scanned)? onProgress,
  }) async {
    final scope = normalizeScope(subPath);
    if (scope.isNotEmpty &&
        scope
            .split('/')
            .any(
              (segment) => segment.isEmpty || segment == '.' || segment == '..',
            )) {
      throw SnapshotPathException(scope, 'Invalid folder path: $scope');
    }
    final exists = await Directory(root).exists();
    if (!exists) {
      throw SnapshotPathException(root, 'Sync root does not exist: $root');
    }

    if (scope.isNotEmpty) {
      final abs = p.joinAll([root, ...scope.split('/')]);
      final type = await FileSystemEntity.type(abs, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        throw SnapshotPathException(scope, 'Folder no longer exists: $scope');
      }
      if (type != FileSystemEntityType.directory) {
        throw SnapshotPathException(scope, 'Not a folder: $scope');
      }
    }

    final loaded = await store.load();
    if (loaded.legacy) {
      throw const SnapshotLegacyException('local');
    }
    final existing = loaded.snapshot == null
        ? null
        : filterSideSnapshot(loaded.snapshot!, ignores);
    if (existing == null && !createIfMissing) {
      throw const SnapshotMissingException('local');
    }

    final manifest = await LocalScanner(
      ignores: ignores,
      hashCache: hashCache,
    ).scan(root, subPath: scope.isEmpty ? null : scope, onProgress: onProgress);

    final scanned = buildFolderSnapshots(manifest, root: root, scope: scope);
    final now = DateTime.now().millisecondsSinceEpoch;
    final current = existing == null
        ? SnapshotState.fromEntries(scanned, updatedAt: now)
        : existing.current.applyScannedScope(
            scope: scope,
            scanned: scanned,
            updatedAt: now,
          );
    final snapshot = SideSnapshot(
      base: existing?.base ?? SnapshotState.empty(),
      current: current,
    );
    await store.save(snapshot);
    return snapshot;
  }
}

/// Builds folder snapshots for [scope] from a flat scanner manifest.
Map<String, FolderSnapshot> buildFolderSnapshots(
  Manifest manifest, {
  required String root,
  required String scope,
}) {
  final scopeKey = folderKey(scope);
  final builders = <String, _FolderBuilder>{};

  _FolderBuilder folderOf(String key) {
    return builders.putIfAbsent(key, _FolderBuilder.new);
  }

  final rootEntry = manifest.entries[scope];
  if (scope.isEmpty) {
    final stat = Directory(root).statSync();
    folderOf(scopeKey).mtimeMs = stat.modified.millisecondsSinceEpoch;
  } else if (rootEntry != null && rootEntry.isDirectory) {
    folderOf(scopeKey).mtimeMs = rootEntry.mtimeMs;
  } else {
    final abs = p.joinAll([root, ...scope.split('/')]);
    folderOf(scopeKey).mtimeMs = Directory(abs)
        .statSync()
        .modified
        .millisecondsSinceEpoch;
  }

  for (final entry in manifest.entries.entries) {
    if (!entry.value.isDirectory) continue;
    folderOf(entry.key).mtimeMs = entry.value.mtimeMs;
  }

  for (final entry in manifest.entries.entries) {
    if (!entry.value.isFile) continue;
    final parent = folderKey(parentScope(entry.key));
    folderOf(parent).files[baseName(entry.key)] = FileSnapshot(
      size: entry.value.size,
      mtimeMs: entry.value.mtimeMs,
      hash: entry.value.hash ?? '',
      textHash: entry.value.textHash,
    );
  }

  for (final path in builders.keys.toList()) {
    if (path == '.' || path == scopeKey) continue;
    folderOf(folderKey(parentScope(path))).dirs.add(baseName(path));
  }

  return {
    for (final entry in builders.entries)
      entry.key: FolderSnapshot(
        mtimeMs: entry.value.mtimeMs,
        dirs: entry.value.dirs,
        files: entry.value.files,
      ),
  };
}

String normalizeScope(String? subPath) {
  if (subPath == null) return '';
  var result = subPath.replaceAll('\\', '/').trim();
  while (result.startsWith('/')) {
    result = result.substring(1);
  }
  while (result.endsWith('/')) {
    result = result.substring(0, result.length - 1);
  }
  if (result == '.') return '';
  return result;
}

/// Removes entries that the current ignore rules exclude.
///
/// Snapshots travel between devices, so a file may have been scanned when a
/// pattern was not configured. Filtering keeps the plan and tree consistent
/// with the pair's current rules.
SideSnapshot filterSideSnapshot(SideSnapshot snapshot, IgnoreRules ignores) {
  return SideSnapshot(
    base: filterSnapshotState(snapshot.base, ignores),
    current: filterSnapshotState(snapshot.current, ignores),
  );
}

SnapshotState filterSnapshotState(SnapshotState state, IgnoreRules ignores) {
  final entries = <String, FolderSnapshot>{};
  for (final entry in state.entries.entries) {
    final scope = scopeOfFolderKey(entry.key);
    if (scope.isNotEmpty && ignores.ignores(scope, isDirectory: true)) {
      continue;
    }
    final folder = entry.value;
    final files = <String, FileSnapshot>{};
    for (final file in folder.files.entries) {
      final path = scope.isEmpty ? file.key : '$scope/${file.key}';
      if (ignores.ignores(path, isDirectory: false)) continue;
      files[file.key] = file.value;
    }
    final dirs = folder.dirs.where((name) {
      final path = scope.isEmpty ? name : '$scope/$name';
      return !ignores.ignores(path, isDirectory: true);
    }).toList();
    entries[entry.key] = FolderSnapshot(
      mtimeMs: folder.mtimeMs,
      dirs: dirs,
      files: files,
    );
  }
  return SnapshotState.fromEntries(entries, updatedAt: state.updatedAt);
}

final class _FolderBuilder {
  int mtimeMs = 0;
  final Set<String> dirs = {};
  final Map<String, FileSnapshot> files = {};
}
