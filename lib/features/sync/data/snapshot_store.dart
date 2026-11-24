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

  final SideSnapshot? snapshot;

  /// True when the file existed but was not in the current format and no
  /// backup directory was configured, so the caller must handle it.
  final bool legacy;

  /// Where a legacy file was copied before it was removed from its origin.
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
  /// A missing, empty, corrupt or legacy file yields no snapshot. Legacy files
  /// are copied to [backupDir] first, then removed from their origin.
  Future<SnapshotLoadResult> load() async {
    if (!await store.exists(fileName)) {
      return const SnapshotLoadResult();
    }

    final builder = BytesBuilder(copy: false);
    await for (final chunk in store.openRead(fileName)) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();

    final snapshot = _parse(bytes);
    if (snapshot != null) {
      return SnapshotLoadResult(snapshot: snapshot);
    }

    final backupDir = this.backupDir;
    if (backupDir == null) {
      return const SnapshotLoadResult(legacy: true);
    }

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
    await store.deleteFile(fileName);
    return SnapshotLoadResult(legacy: true, backupPath: target.path);
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

  static SideSnapshot? _parse(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    try {
      final text = utf8.decode(bytes);
      if (text.trim().isEmpty) return null;
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      return SideSnapshot.fromJson(decoded.cast<String, Object?>());
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
