/// Persistence for the shared base manifest of a sync pair.
///
/// Unlike the old implementation, a pair has exactly one base. This removes
/// the "two baselines drift apart" failure mode.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/manifest.dart';

final class SyncState {
  const SyncState({
    required this.rootA,
    required this.rootB,
    required this.base,
    this.committedAt,
  });

  static const schemaVersion = 1;

  final String rootA;
  final String rootB;
  final Manifest base;
  final DateTime? committedAt;

  Map<String, Object?> toJson() {
    return {
      'schema': schemaVersion,
      'rootA': rootA,
      'rootB': rootB,
      'committedAt': committedAt?.toUtc().toIso8601String(),
      'base': base.toJson(),
    };
  }

  factory SyncState.fromJson(Map<String, Object?> json) {
    final schema = (json['schema'] as num?)?.toInt();
    if (schema != schemaVersion) {
      throw FormatException('Unsupported sync state schema: $schema');
    }
    return SyncState(
      rootA: json['rootA'] as String? ?? '',
      rootB: json['rootB'] as String? ?? '',
      base: Manifest.fromJson(
        (json['base'] as Map?)?.cast<String, Object?>() ?? const {},
      ),
      committedAt: DateTime.tryParse(json['committedAt'] as String? ?? '')
          ?.toUtc(),
    );
  }
}

final class SyncStateStore {
  SyncStateStore(this.filePath);

  final String filePath;

  Future<SyncState?> load() async {
    final file = File(filePath);
    if (!await file.exists()) return null;
    final text = await file.readAsString();
    if (text.trim().isEmpty) return null;
    final json = jsonDecode(text);
    if (json is! Map) {
      throw const FormatException('Sync state must be a JSON object');
    }
    return SyncState.fromJson(json.cast<String, Object?>());
  }

  Future<void> save(SyncState state) async {
    final file = File(filePath);
    final parent = Directory(p.dirname(file.path));
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final temp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(state.toJson()),
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
    } finally {
      if (await temp.exists()) {
        await temp.delete();
      }
    }
  }
}
