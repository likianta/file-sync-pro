/// Snapshot persistence that travels with the synced folder.
///
/// Each side of a pair keeps its own `.file_sync_shot.json` at the root of the
/// folder. The file contains a previous synced baseline (`base`) and the last
/// user-triggered scan (`current`).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../domain/sync_snapshot.dart';
import 'file_store.dart';

final class SnapshotLoadResult {
  const SnapshotLoadResult({
    this.snapshot,
    this.legacy = false,
    this.backupPath,
  });

  /// A usable snapshot. When an old hash algorithm was found, this is the
  /// freshly written seed that keeps `ignores` but drops the stale entries.
  final SideSnapshot? snapshot;

  /// True when the stored file could not be used as-is.
  final bool legacy;

  /// Where the original file was copied before it was rewritten or removed.
  final String? backupPath;

  bool get isMissing => snapshot == null && !legacy;
}

final class SnapshotStore {
  SnapshotStore(
    this.store, {
    this.fileName = defaultFileName,
    this.backupDir,
    this.label = 'snapshot',
  });

  /// The snapshot file name, relative to the synced root.
  static const defaultFileName = '.file_sync_shot.json';

  final FileStore store;

  final String fileName;

  /// Optional local directory where legacy snapshot files are preserved.
  final String? backupDir;

  /// Prefix for backup file names, for example `pictures-local`.
  final String label;

  /// Reads this side's snapshot.
  ///
  /// A missing or empty file yields no snapshot. Files written with a retired
  /// hash algorithm are backed up when [backupDir] exists, then replaced with
  /// an empty seed that keeps `ignores`. Corrupt files are backed up and
  /// removed.
  Future<SnapshotLoadResult> load() async {
    if (!await store.exists(fileName)) {
      return const SnapshotLoadResult();
    }

    final builder = BytesBuilder(copy: false);
    await for (final chunk in store.openRead(fileName)) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();

    final parsed = _parse(bytes);
    if (parsed != null) {
      if (parsed.algorithm == snapshotHashAlgorithm) {
        return SnapshotLoadResult(snapshot: parsed.snapshot);
      }
      return _migrateAlgorithm(parsed.snapshot, bytes);
    }

    final backupDir = this.backupDir;
    if (backupDir == null) {
      return const SnapshotLoadResult(legacy: true);
    }

    final backupPath = await _writeBackup(bytes, backupDir);
    await store.deleteFile(fileName);
    return SnapshotLoadResult(legacy: true, backupPath: backupPath);
  }

  /// Replaces a snapshot written by a retired hash algorithm with an empty
  /// seed so the next scan can rebuild `base` and `current` with the current
  /// algorithm while keeping the user's ignore rules.
  Future<SnapshotLoadResult> _migrateAlgorithm(
    SideSnapshot old,
    Uint8List bytes,
  ) async {
    final seed = SideSnapshot(
      base: SnapshotState.empty(),
      current: SnapshotState.empty(),
      ignores: old.ignores,
    );
    final backupDir = this.backupDir;
    final backupPath = backupDir == null
        ? null
        : await _writeBackup(bytes, backupDir);
    await save(seed);
    return SnapshotLoadResult(
      snapshot: seed,
      legacy: true,
      backupPath: backupPath,
    );
  }

  Future<String> _writeBackup(Uint8List bytes, String backupDir) async {
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp('[:.]'),
      '-',
    );
    final safeLabel = label.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
    final target = File(
      p.join(backupDir, '$safeLabel-$stamp.file_sync_shot.json'),
    );
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  Future<void> save(SideSnapshot snapshot) async {
    final bytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(snapshot.toJson()),
    );
    await store.writeAtomically(
      fileName,
      Stream.value(bytes),
      modified: DateTime.now(),
    );
  }

  static ({SideSnapshot snapshot, String algorithm})? _parse(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    try {
      final text = utf8.decode(bytes);
      if (text.trim().isEmpty) return null;
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      final json = decoded.cast<String, Object?>();
      final algorithm = json['hash_algo'];
      return (
        snapshot: SideSnapshot.fromJson(json),
        algorithm: algorithm is String ? algorithm : '',
      );
    } catch (_) {
      return null;
    }
  }
}

/// Where legacy snapshot files are preserved before being removed.
String defaultSnapshotBackupDir() {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    return p.join(Directory.systemTemp.path, 'file-sync-pro-chore');
  }
  return p.join(home, 'Desktop', 'temp', '2026-11', 'chore');
}
