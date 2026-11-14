/// Manifest model for the sync engine.
///
/// A manifest maps relative POSIX paths to metadata. It is intentionally free
/// of any IO so it can be unit tested and reused on both devices.
library;

enum EntryKind { file, directory }

final class ManifestEntry {
  const ManifestEntry({
    required this.kind,
    required this.size,
    required this.mtimeMs,
    this.hash,
  });

  factory ManifestEntry.directory({required int mtimeMs}) {
    return ManifestEntry(kind: EntryKind.directory, size: 0, mtimeMs: mtimeMs);
  }

  factory ManifestEntry.file({
    required int size,
    required int mtimeMs,
    String? hash,
  }) {
    return ManifestEntry(
      kind: EntryKind.file,
      size: size,
      mtimeMs: mtimeMs,
      hash: hash,
    );
  }

  final EntryKind kind;
  final int size;
  final int mtimeMs;

  /// SHA-256 of the file content. Directories have no hash.
  final String? hash;

  bool get isDirectory => kind == EntryKind.directory;

  bool get isFile => kind == EntryKind.file;

  /// Content equality.
  ///
  /// Hash is authoritative when both sides have one; otherwise fall back to
  /// size + mtime. Note that a pure mtime change with the same content is
  /// considered "same" when hashes are available, which is the key difference
  /// from the old Python implementation.
  bool sameContent(ManifestEntry? other) {
    if (other == null) return false;
    if (kind != other.kind) return false;
    if (kind == EntryKind.directory) return true;
    if (size != other.size) return false;
    if (hash != null && other.hash != null) return hash == other.hash;
    return mtimeMs == other.mtimeMs;
  }

  Map<String, Object?> toJson() {
    return {
      'kind': isDirectory ? 'dir' : 'file',
      'size': size,
      'mtime': mtimeMs,
      if (hash != null) 'hash': hash,
    };
  }

  factory ManifestEntry.fromJson(Map<String, Object?> json) {
    final kind = json['kind'] == 'dir' ? EntryKind.directory : EntryKind.file;
    return ManifestEntry(
      kind: kind,
      size: (json['size'] as num?)?.toInt() ?? 0,
      mtimeMs: (json['mtime'] as num?)?.toInt() ?? 0,
      hash: json['hash'] as String?,
    );
  }

  @override
  String toString() {
    return 'ManifestEntry(${isDirectory ? 'dir' : 'file'}, '
        'size: $size, mtime: $mtimeMs, hash: $hash)';
  }
}

final class Manifest {
  Manifest({
    required this.root,
    required this.scannedAt,
    required Map<String, ManifestEntry> entries,
  }) : entries = _sorted(entries);

  factory Manifest.empty({String root = ''}) {
    return Manifest(
      root: root,
      scannedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      entries: const {},
    );
  }

  final String root;
  final DateTime scannedAt;

  /// Sorted by relative path so the JSON output and plan order are stable.
  final Map<String, ManifestEntry> entries;

  bool get isEmpty => entries.isEmpty;

  int get fileCount => entries.values.where((entry) => entry.isFile).length;

  int get directoryCount =>
      entries.values.where((entry) => entry.isDirectory).length;

  Map<String, Object?> toJson() {
    return {
      'root': root,
      'scannedAt': scannedAt.toUtc().toIso8601String(),
      'entries': {
        for (final entry in entries.entries) entry.key: entry.value.toJson(),
      },
    };
  }

  factory Manifest.fromJson(Map<String, Object?> json) {
    final rawEntries = (json['entries'] as Map?) ?? const {};
    return Manifest(
      root: json['root'] as String? ?? '',
      scannedAt:
          DateTime.tryParse(json['scannedAt'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      entries: {
        for (final entry in rawEntries.entries)
          entry.key as String: ManifestEntry.fromJson(
            (entry.value as Map).cast<String, Object?>(),
          ),
      },
    );
  }

  static Map<String, ManifestEntry> _sorted(
    Map<String, ManifestEntry> entries,
  ) {
    final keys = entries.keys.toList()..sort();
    return Map.unmodifiable({for (final key in keys) key: entries[key]!});
  }

  @override
  String toString() {
    return 'Manifest(root: $root, files: $fileCount, dirs: $directoryCount)';
  }
}
