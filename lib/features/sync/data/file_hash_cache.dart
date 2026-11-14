/// Persistent and in-memory hash caches.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'local_scanner.dart';

final class _Entry {
  const _Entry(this.size, this.mtimeMs, this.hash, this.textHash);

  final int size;
  final int mtimeMs;
  final String hash;
  final String? textHash;

  Map<String, Object?> toJson() => {
    'size': size,
    'mtime': mtimeMs,
    'hash': hash,
    if (textHash != null) 'textHash': textHash,
  };

  factory _Entry.fromJson(Map<String, Object?> json) => _Entry(
    (json['size'] as num?)?.toInt() ?? 0,
    (json['mtime'] as num?)?.toInt() ?? 0,
    json['hash'] as String? ?? '',
    json['textHash'] as String?,
  );
}

/// A hash cache backed by a JSON file.
///
/// The cache is keyed by absolute path + size + mtime. It is written with an
/// atomic rename so a crash never leaves a partially written cache behind.
final class FileHashCache implements HashCache {
  FileHashCache(this.path) {
    _load();
  }

  static const version = 2;

  final String path;
  final Map<String, _Entry> _entries = {};
  var _dirty = false;

  @override
  CachedHashes? lookup(String path, int size, int mtimeMs) {
    final entry = _entries[path];
    if (entry != null && entry.size == size && entry.mtimeMs == mtimeMs) {
      return (hash: entry.hash, textHash: entry.textHash);
    }
    return null;
  }

  @override
  void store(
    String path,
    int size,
    int mtimeMs,
    String hash,
    String? textHash,
  ) {
    _entries[path] = _Entry(size, mtimeMs, hash, textHash);
    _dirty = true;
  }

  @override
  void remove(String path) {
    if (_entries.remove(path) != null) {
      _dirty = true;
    }
  }

  @override
  void removeWhere(bool Function(String path) test) {
    final before = _entries.length;
    _entries.removeWhere((key, _) => test(key));
    if (_entries.length != before) {
      _dirty = true;
    }
  }

  @override
  Future<void> flush() async {
    if (!_dirty) return;
    final file = File(path);
    final parent = Directory(p.dirname(file.path));
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    final temp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temp.writeAsString(
        jsonEncode({
          'version': version,
          'entries': {
            for (final entry in _entries.entries)
              entry.key: entry.value.toJson(),
          },
        }),
        flush: true,
      );
      try {
        await temp.rename(file.path);
      } on FileSystemException {
        if (await file.exists()) {
          await file.delete();
        }
        await temp.rename(file.path);
      }
      _dirty = false;
    } finally {
      if (await temp.exists()) {
        await temp.delete();
      }
    }
  }

  void _load() {
    final file = File(path);
    if (!file.existsSync()) return;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map || decoded['version'] != version) return;
      final raw = decoded['entries'];
      if (raw is! Map) return;
      for (final entry in raw.entries) {
        if (entry.key is String && entry.value is Map) {
          _entries[entry.key as String] = _Entry.fromJson(
            (entry.value as Map).cast<String, Object?>(),
          );
        }
      }
    } catch (_) {
      // A corrupt cache is harmless: it is rebuilt on the next scan.
      _entries.clear();
    }
  }
}

/// A non-persistent hash cache used by short-lived servers and tests.
final class MemoryHashCache implements HashCache {
  final Map<String, _Entry> _entries = {};

  @override
  CachedHashes? lookup(String path, int size, int mtimeMs) {
    final entry = _entries[path];
    if (entry != null && entry.size == size && entry.mtimeMs == mtimeMs) {
      return (hash: entry.hash, textHash: entry.textHash);
    }
    return null;
  }

  @override
  void store(
    String path,
    int size,
    int mtimeMs,
    String hash,
    String? textHash,
  ) {
    _entries[path] = _Entry(size, mtimeMs, hash, textHash);
  }

  @override
  void remove(String path) {
    _entries.remove(path);
  }

  @override
  void removeWhere(bool Function(String path) test) {
    _entries.removeWhere((key, _) => test(key));
  }

  @override
  Future<void> flush() async {}
}
