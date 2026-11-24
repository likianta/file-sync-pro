/// Scans one folder and merges it into a side snapshot.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/ignore_rules.dart';
import '../domain/manifest.dart';
import '../domain/sync_snapshot.dart';
import 'file_hash_cache.dart';
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

final class SnapshotIgnoresException implements Exception {
  const SnapshotIgnoresException(this.root, this.message);

  final String root;
  final String message;

  @override
  String toString() => message;
}

/// Owns the local filesystem side of snapshot scanning.
final class LocalSnapshotManager {
  LocalSnapshotManager({
    required this.root,
    required this.store,
    this.defaultIgnores = SnapshotIgnores.empty,
  });

  final String root;
  final SnapshotStore store;

  /// Used only when creating a new snapshot. An existing snapshot keeps its
  /// own [SnapshotIgnores].
  final SnapshotIgnores defaultIgnores;

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
    SnapshotIgnores? ignores,
    void Function(int scanned, int? total)? onProgress,
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
    final existing = loaded.snapshot;
    if (existing == null) {
      if (loaded.legacy) throw const SnapshotLegacyException('local');
      if (!createIfMissing) throw const SnapshotMissingException('local');
    }

    final effectiveIgnores = existing?.ignores ?? ignores ?? defaultIgnores;
    final rules = await resolveSnapshotIgnores(effectiveIgnores, root);
    final cache = _memoryCacheFrom(existing?.current, root);

    final manifest = await LocalScanner(
      ignores: rules,
      hashCache: cache,
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
      ignores: effectiveIgnores,
    );
    await store.save(snapshot);
    return snapshot;
  }

  /// Refreshes one file's entry in `current` without walking a folder.
  Future<SideSnapshot> refreshFile(String relPath) async {
    final path = normalizeScope(relPath);
    if (path.isEmpty ||
        path
            .split('/')
            .any(
              (segment) => segment.isEmpty || segment == '.' || segment == '..',
            )) {
      throw SnapshotPathException(path, 'Invalid file path: $path');
    }
    final loaded = await store.load();
    final existing = loaded.snapshot;
    if (existing == null) {
      if (loaded.legacy) throw const SnapshotLegacyException('local');
      throw const SnapshotMissingException('local');
    }
    final rules = await resolveSnapshotIgnores(existing.ignores, root);
    final entries = _copyFolders(existing.current.entries);
    final parent = folderKey(parentScope(path));
    final folder = entries[parent];
    if (folder == null) {
      throw StateError('Snapshot is missing parent folder: $parent');
    }

    final abs = p.joinAll([root, ...path.split('/')]);
    final type = await FileSystemEntity.type(abs, followLinks: false);
    final files = {...folder.files};
    if (type == FileSystemEntityType.file &&
        !rules.ignores(path, isDirectory: false)) {
      final cache = _memoryCacheFrom(existing.current, root);
      final manifest = await LocalScanner(
        ignores: rules,
        hashCache: cache,
      ).scan(root, subPath: path);
      final entry = manifest.entries[path];
      if (entry != null) {
        files[baseName(path)] = FileSnapshot(
          size: entry.size,
          mtimeMs: entry.mtimeMs,
          hash: entry.hash ?? '',
          textHash: entry.textHash,
        );
      } else {
        files.remove(baseName(path));
      }
    } else {
      files.remove(baseName(path));
    }
    entries[parent] = folder.copyWith(files: files);
    final snapshot = SideSnapshot(
      base: existing.base,
      current: SnapshotState.fromEntries(
        entries,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
      ignores: existing.ignores,
    );
    await store.save(snapshot);
    return snapshot;
  }
}

Map<String, FolderSnapshot> _copyFolders(Map<String, FolderSnapshot> source) {
  return {
    for (final entry in source.entries)
      entry.key: entry.value.copyWith(
        dirs: [...entry.value.dirs],
        files: {...entry.value.files},
      ),
  };
}

/// Turns snapshot ignores into scanner rules. Built-in safety patterns always
/// apply, including the snapshot file itself and the `.git` directory.
Future<IgnoreRules> resolveSnapshotIgnores(
  SnapshotIgnores ignores,
  String root,
) async {
  final patterns = <String>[];
  if (ignores.useGitignore) {
    final file = File(p.join(root, '.gitignore'));
    if (!await file.exists()) {
      throw SnapshotIgnoresException(
        root,
        'Snapshot ignores is \$gitignore but .gitignore was not found in $root',
      );
    }
    patterns.addAll(
      (await file.readAsLines())
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty),
    );
  } else {
    patterns.addAll(ignores.patterns);
  }
  return IgnoreRules.defaults(extra: patterns);
}

MemoryHashCache _memoryCacheFrom(SnapshotState? current, String root) {
  final cache = MemoryHashCache();
  if (current == null) return cache;
  for (final folder in current.entries.entries) {
    final scope = scopeOfFolderKey(folder.key);
    final directory = scope.isEmpty
        ? root
        : p.joinAll([root, ...scope.split('/')]);
    for (final file in folder.value.files.entries) {
      cache.store(
        p.join(directory, file.key),
        file.value.size,
        file.value.mtimeMs,
        file.value.hash,
        file.value.textHash,
      );
    }
  }
  return cache;
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

final class _FolderBuilder {
  int mtimeMs = 0;
  final Set<String> dirs = {};
  final Map<String, FileSnapshot> files = {};
}
