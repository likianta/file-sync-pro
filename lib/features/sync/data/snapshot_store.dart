/// Snapshot persistence that travels with the synced folder.
///
/// Each side of a pair keeps its own `.file_sync_shot.json` at the root of the
/// folder. Any device that can reach that folder can reuse the snapshot, so a
/// new controller does not have to rebuild a baseline from scratch.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../domain/manifest.dart';
import 'file_store.dart';

final class SnapshotStore {
  SnapshotStore(this.store, {this.fileName = defaultFileName});

  /// The snapshot file name, relative to the synced root.
  static const defaultFileName = '.file_sync_shot.json';

  static const schemaVersion = 1;

  /// The store of the side that owns the snapshot.
  final FileStore store;

  final String fileName;

  /// Reads this side's snapshot.
  ///
  /// Returns null when the file is missing, empty or unreadable. A corrupt
  /// snapshot is equivalent to having no baseline; the next sync rebuilds it.
  Future<Manifest?> load() async {
    if (!await store.exists(fileName)) return null;

    try {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in store.openRead(fileName)) {
        builder.add(chunk);
      }
      final text = utf8.decode(builder.takeBytes());
      if (text.trim().isEmpty) return null;

      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      final json = decoded.cast<String, Object?>();
      if ((json['schema'] as num?)?.toInt() != schemaVersion) return null;

      final rawEntries = json['entries'];
      if (rawEntries is! Map) return null;

      final entries = <String, ManifestEntry>{};
      for (final entry in rawEntries.entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        entries[entry.key as String] = ManifestEntry.fromJson(
          (entry.value as Map).cast<String, Object?>(),
        );
      }

      final committedAt = DateTime.tryParse(
        json['committedAt'] as String? ?? '',
      );
      return Manifest(
        root: '',
        scannedAt:
            committedAt?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        entries: entries,
      );
    } catch (_) {
      return null;
    }
  }

  /// Writes this side's snapshot after a successful sync.
  Future<void> save(Manifest manifest, {required DateTime committedAt}) async {
    final data = <String, Object?>{
      'schema': schemaVersion,
      'committedAt': committedAt.toUtc().toIso8601String(),
      'entries': {
        for (final entry in manifest.entries.entries)
          entry.key: entry.value.toJson(),
      },
    };
    final bytes = utf8.encode(jsonEncode(data));
    await store.writeAtomically(
      fileName,
      Stream.value(bytes),
      modified: committedAt,
    );
  }
}
