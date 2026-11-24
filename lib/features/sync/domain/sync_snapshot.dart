/// Hierarchical sync snapshots stored in `.file_sync_shot.json`.
///
/// Each side keeps two states:
/// - `base`: the state at the end of the last successful sync.
/// - `current`: the last user-triggered scan.
///
/// Snapshots are folder-oriented so a single folder can be rescanned without
/// walking the whole tree.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'manifest.dart';

/// Metadata for one file inside a folder snapshot.
final class FileSnapshot {
  const FileSnapshot({
    required this.size,
    required this.mtimeMs,
    required this.hash,
    this.textHash,
  });

  final int size;
  final int mtimeMs;
  final String hash;
  final String? textHash;

  ManifestEntry toManifestEntry() {
    return ManifestEntry.file(
      size: size,
      mtimeMs: mtimeMs,
      hash: hash.isEmpty ? null : hash,
      textHash: textHash,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'size': size,
      'mtime': mtimeMs,
      'hash': hash,
      if (textHash != null) 'text_hash': textHash,
    };
  }

  factory FileSnapshot.fromJson(Map<String, Object?> json) {
    return FileSnapshot(
      size: (json['size'] as num?)?.toInt() ?? 0,
      mtimeMs: (json['mtime'] as num?)?.toInt() ?? 0,
      hash: json['hash'] as String? ?? '',
      textHash: json['text_hash'] as String?,
    );
  }
}

/// One folder and its direct children.
final class FolderSnapshot {
  FolderSnapshot({
    required this.mtimeMs,
    Iterable<String> dirs = const [],
    Map<String, FileSnapshot> files = const {},
  }) : dirs = List.unmodifiable(dirs.toSet().toList()..sort()),
       files = Map.unmodifiable(files);

  final int mtimeMs;

  /// Direct child directory names, sorted.
  final List<String> dirs;

  /// Direct child files keyed by file name.
  final Map<String, FileSnapshot> files;

  FolderSnapshot copyWith({
    int? mtimeMs,
    Iterable<String>? dirs,
    Map<String, FileSnapshot>? files,
  }) {
    return FolderSnapshot(
      mtimeMs: mtimeMs ?? this.mtimeMs,
      dirs: dirs ?? this.dirs,
      files: files ?? this.files,
    );
  }

  Map<String, Object?> toJson() {
    final names = files.keys.toList()..sort();
    return {
      'mtime': mtimeMs,
      'dirs': dirs,
      'files': {for (final name in names) name: files[name]!.toJson()},
    };
  }

  factory FolderSnapshot.fromJson(Map<String, Object?> json) {
    final dirs = json['dirs'];
    final files = json['files'];
    return FolderSnapshot(
      mtimeMs: (json['mtime'] as num?)?.toInt() ?? 0,
      dirs: dirs is List ? dirs.whereType<String>() : const [],
      files: files is Map
          ? {
              for (final entry in files.entries)
                if (entry.key is String && entry.value is Map)
                  entry.key as String: FileSnapshot.fromJson(
                    (entry.value as Map).cast<String, Object?>(),
                  ),
            }
          : const {},
    );
  }
}

/// One state (`base` or `current`) of a side snapshot.
final class SnapshotState {
  SnapshotState._({
    required this.key,
    required this.updatedAt,
    required Map<String, FolderSnapshot> entries,
  }) : entries = Map.unmodifiable(entries);

  factory SnapshotState.fromEntries(
    Map<String, FolderSnapshot> entries, {
    required int updatedAt,
  }) {
    return SnapshotState._(
      key: computeKey(entries),
      updatedAt: updatedAt,
      entries: entries,
    );
  }

  factory SnapshotState.empty() {
    return SnapshotState.fromEntries(const {}, updatedAt: 0);
  }

  /// Stable identity of the entries, used to compare `base` and `current` on
  /// the same side. Volatile fields such as `updatedAt` are excluded on
  /// purpose; mtime is included because it is part of the scanned state.
  final String key;

  final int updatedAt;

  /// Folder entries keyed by POSIX path relative to the sync root. The root
  /// folder uses `"."`.
  final Map<String, FolderSnapshot> entries;

  bool get isEmpty => entries.isEmpty;

  FolderSnapshot? folder(String path) => entries[folderKey(path)];

  Map<String, Object?> toJson() {
    final paths = entries.keys.toList()..sort();
    return {
      'key': key,
      'updated_at': updatedAt,
      'entries': {for (final path in paths) path: entries[path]!.toJson()},
    };
  }

  factory SnapshotState.fromJson(Map<String, Object?> json) {
    final rawEntries = json['entries'];
    final entries = <String, FolderSnapshot>{};
    if (rawEntries is Map) {
      for (final entry in rawEntries.entries) {
        if (entry.key is String && entry.value is Map) {
          entries[entry.key as String] = FolderSnapshot.fromJson(
            (entry.value as Map).cast<String, Object?>(),
          );
        }
      }
    }
    return SnapshotState.fromEntries(
      entries,
      updatedAt: (json['updated_at'] as num?)?.toInt() ?? 0,
    );
  }

  /// Replaces the scanned subtree and recomputes [key].
  ///
  /// [scanned] contains the scope folder and all of its descendants, keyed the
  /// same way as [entries]. Other folders are kept as they were.
  SnapshotState applyScannedScope({
    required String scope,
    required Map<String, FolderSnapshot> scanned,
    required int updatedAt,
  }) {
    final next = <String, FolderSnapshot>{...entries};
    if (scope.isEmpty) {
      next.clear();
    } else {
      final key = folderKey(scope);
      next.removeWhere((path, _) => path == key || path.startsWith('$key/'));
    }
    next.addAll(scanned);

    if (scope.isNotEmpty) {
      final parent = parentScope(scope);
      final parentKey = folderKey(parent);
      final parentFolder = next[parentKey];
      if (parentFolder == null) {
        throw StateError('Snapshot is missing parent folder: $parent');
      }
      next[parentKey] = parentFolder.copyWith(
        dirs: {...parentFolder.dirs, baseName(scope)}.toList(),
      );
    }

    return SnapshotState.fromEntries(next, updatedAt: updatedAt);
  }

  /// Converts this state into a flat manifest for the planner and tree view.
  Manifest toManifest({String root = ''}) {
    final manifestEntries = <String, ManifestEntry>{};
    for (final folderEntry in entries.entries) {
      final path = folderEntry.key == '.' ? '' : folderEntry.key;
      if (path.isNotEmpty) {
        manifestEntries[path] = ManifestEntry.directory(
          mtimeMs: folderEntry.value.mtimeMs,
        );
      }
      for (final fileEntry in folderEntry.value.files.entries) {
        final filePath = path.isEmpty
            ? fileEntry.key
            : '$path/${fileEntry.key}';
        manifestEntries[filePath] = fileEntry.value.toManifestEntry();
      }
    }
    return Manifest(
      root: root,
      scannedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt, isUtc: true),
      entries: manifestEntries,
    );
  }

  static String computeKey(Map<String, FolderSnapshot> entries) {
    final paths = entries.keys.toList()..sort();
    final canonical = <String, Object?>{};
    for (final path in paths) {
      canonical[path] = entries[path]!.toJson();
    }
    return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
  }
}

/// Ignore configuration shared by every pair that uses the same root.
///
/// The snapshot file is the single source of truth so two pairs pointing at
/// the same folder cannot disagree about what should be scanned.
final class SnapshotIgnores {
  const SnapshotIgnores.patterns(this.patterns) : useGitignore = false;

  const SnapshotIgnores.gitignore() : patterns = const [], useGitignore = true;

  static const empty = SnapshotIgnores.patterns([]);

  final List<String> patterns;

  final bool useGitignore;

  Object toJson() => useGitignore ? r'$gitignore' : patterns;

  factory SnapshotIgnores.fromJson(Object? json) {
    if (json == null) return empty;
    if (json is String) {
      if (json == r'$gitignore') return const SnapshotIgnores.gitignore();
      throw FormatException('Unsupported ignores value: $json');
    }
    if (json is List) {
      return SnapshotIgnores.patterns(json.whereType<String>().toList());
    }
    throw const FormatException('ignores must be a string or a list');
  }
}

/// The contents of one `.file_sync_shot.json` file.
final class SideSnapshot {
  const SideSnapshot({
    required this.base,
    required this.current,
    this.ignores = SnapshotIgnores.empty,
  });

  final SnapshotState base;
  final SnapshotState current;

  /// Ignore rules used when scanning either side of this root.
  final SnapshotIgnores ignores;

  SideSnapshot copyWith({
    SnapshotState? base,
    SnapshotState? current,
    SnapshotIgnores? ignores,
  }) {
    return SideSnapshot(
      base: base ?? this.base,
      current: current ?? this.current,
      ignores: ignores ?? this.ignores,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'ignores': ignores.toJson(),
      'base': base.toJson(),
      'current': current.toJson(),
    };
  }

  factory SideSnapshot.fromJson(Map<String, Object?> json) {
    final base = json['base'];
    final current = json['current'];
    if (base is! Map || current is! Map) {
      throw const FormatException('Snapshot must contain base and current');
    }
    return SideSnapshot(
      base: SnapshotState.fromJson(base.cast<String, Object?>()),
      current: SnapshotState.fromJson(current.cast<String, Object?>()),
      ignores: SnapshotIgnores.fromJson(json['ignores']),
    );
  }
}

/// Folder keys use `"."` for the sync root; scopes use an empty string.
String folderKey(String scope) => scope.isEmpty ? '.' : scope;

String scopeOfFolderKey(String key) => key == '.' ? '' : key;

String parentScope(String path) {
  final index = path.lastIndexOf('/');
  return index < 0 ? '' : path.substring(0, index);
}

String baseName(String path) {
  final index = path.lastIndexOf('/');
  return index < 0 ? path : path.substring(index + 1);
}

bool inScope(String path, String? scope) {
  if (scope == null || scope.isEmpty) return true;
  return path == scope || path.startsWith('$scope/');
}
