/// Multi-pair client configuration.
///
/// Version 2 layout:
/// {
///   "version": 2,
///   "token": "...",
///   "timeoutSeconds": 300,
///   "ignores": [...],
///   "pairs": [
///     {"name": "photolens", "localRoot": "...", "remoteUrl": "...", "stateDir": "..."}
///   ]
/// }
///
/// Legacy single-pair files are migrated in memory.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'sync_pair_config.dart';

final class SyncPairEntry {
  const SyncPairEntry({
    required this.name,
    required this.localRoot,
    required this.remoteUrl,
    required this.stateDir,
  });

  final String name;
  final String localRoot;
  final String remoteUrl;
  final String stateDir;

  SyncPairEntry copyWith({
    String? name,
    String? localRoot,
    String? remoteUrl,
    String? stateDir,
  }) {
    return SyncPairEntry(
      name: name ?? this.name,
      localRoot: localRoot ?? this.localRoot,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      stateDir: stateDir ?? this.stateDir,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'name': name,
      'localRoot': localRoot,
      'remoteUrl': remoteUrl,
      'stateDir': stateDir,
    };
  }

  SyncPairConfig toRuntime({
    required String token,
    required int timeoutSeconds,
    required List<String> extraIgnores,
  }) {
    return SyncPairConfig(
      name: name,
      localRoot: localRoot,
      remoteUrl: remoteUrl,
      token: token,
      stateDir: stateDir,
      timeoutSeconds: timeoutSeconds,
      extraIgnores: extraIgnores,
    );
  }
}

final class SyncClientConfig {
  SyncClientConfig({
    required this.token,
    required this.timeoutSeconds,
    required this.extraIgnores,
    required List<SyncPairEntry> pairs,
  }) : pairs = List.of(pairs);

  String token;
  int timeoutSeconds;
  final List<String> extraIgnores;
  final List<SyncPairEntry> pairs;

  static const schemaVersion = 2;

  static SyncClientConfig load({
    required String path,
    required String projectRoot,
  }) {
    final file = File(path);
    if (!file.existsSync()) {
      return SyncClientConfig(
        token: Platform.environment['FILE_SYNC_TOKEN'] ?? '',
        timeoutSeconds: 300,
        extraIgnores: const [],
        pairs: const [],
      );
    }

    final text = file.readAsStringSync();
    if (text.trim().isEmpty) {
      return SyncClientConfig(
        token: Platform.environment['FILE_SYNC_TOKEN'] ?? '',
        timeoutSeconds: 300,
        extraIgnores: const [],
        pairs: const [],
      );
    }

    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw FormatException('Config must be a JSON object: $path');
    }
    final json = decoded.cast<String, Object?>();
    final token =
        Platform.environment['FILE_SYNC_TOKEN'] ??
        json['token'] as String? ??
        '';
    final timeoutSeconds = (json['timeoutSeconds'] as num?)?.toInt() ?? 300;
    final ignores = json['ignores'] is List
        ? (json['ignores'] as List).whereType<String>().toList(growable: false)
        : const <String>[];

    final rawPairs = json['pairs'];
    if (rawPairs is List && rawPairs.isNotEmpty) {
      return SyncClientConfig(
        token: token,
        timeoutSeconds: timeoutSeconds,
        extraIgnores: ignores,
        pairs: [
          for (final raw in rawPairs)
            _entryFromJson(
              (raw as Map).cast<String, Object?>(),
              projectRoot: projectRoot,
            ),
        ],
      );
    }

    // Legacy single-pair layout.
    final remoteUrl = json['remoteUrl'] as String? ?? '';
    if (remoteUrl.isEmpty) {
      return SyncClientConfig(
        token: token,
        timeoutSeconds: timeoutSeconds,
        extraIgnores: ignores,
        pairs: const [],
      );
    }

    final name = _defaultPairName(remoteUrl);
    final localRoot = _resolve(
      projectRoot,
      _expandUser(
        json['localRoot'] as String? ?? p.join(projectRoot, '..', 'photolens'),
      ),
    );
    final stateDir = _resolve(
      projectRoot,
      _expandUser(
        json['stateDir'] as String? ??
            p.join(projectRoot, 'data', 'sync_pairs', name),
      ),
    );

    return SyncClientConfig(
      token: token,
      timeoutSeconds: timeoutSeconds,
      extraIgnores: ignores,
      pairs: [
        SyncPairEntry(
          name: name,
          localRoot: localRoot,
          remoteUrl: remoteUrl,
          stateDir: stateDir,
        ),
      ],
    );
  }

  Future<void> save({required String path}) async {
    final file = File(path);
    final parent = Directory(p.dirname(file.path));
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final data = <String, Object?>{
      'version': schemaVersion,
      'token': token,
      'timeoutSeconds': timeoutSeconds,
      'ignores': extraIgnores,
      'pairs': [for (final pair in pairs) pair.toJson()],
    };

    final temp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
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

  SyncPairConfig? runtimeFor(String name) {
    SyncPairEntry? pair;
    for (final entry in pairs) {
      if (entry.name == name) {
        pair = entry;
        break;
      }
    }
    return pair?.toRuntime(
      token: token,
      timeoutSeconds: timeoutSeconds,
      extraIgnores: extraIgnores,
    );
  }

  SyncPairConfig? get firstRuntime {
    if (pairs.isEmpty) return null;
    return pairs.first.toRuntime(
      token: token,
      timeoutSeconds: timeoutSeconds,
      extraIgnores: extraIgnores,
    );
  }

  static SyncPairEntry _entryFromJson(
    Map<String, Object?> json, {
    required String projectRoot,
  }) {
    final remoteUrl = json['remoteUrl'] as String? ?? '';
    final name = (json['name'] as String?)?.trim().isNotEmpty == true
        ? (json['name'] as String).trim()
        : _defaultPairName(remoteUrl);
    return SyncPairEntry(
      name: name,
      localRoot: _resolve(
        projectRoot,
        _expandUser(
          json['localRoot'] as String? ??
              p.join(projectRoot, '..', 'photolens'),
        ),
      ),
      remoteUrl: remoteUrl,
      stateDir: _resolve(
        projectRoot,
        _expandUser(
          json['stateDir'] as String? ??
              p.join(projectRoot, 'data', 'sync_pairs', name),
        ),
      ),
    );
  }

  static String _defaultPairName(String remoteUrl) {
    final uri = Uri.tryParse(remoteUrl);
    final segments =
        uri?.pathSegments.where((segment) => segment.isNotEmpty).toList() ??
        const <String>[];
    return segments.isEmpty ? 'sync' : segments.last;
  }

  static String _resolve(String projectRoot, String path) {
    return p.normalize(p.isAbsolute(path) ? path : p.join(projectRoot, path));
  }

  static String _expandUser(String path) {
    if (path == '~') return Platform.environment['HOME'] ?? path;
    if (path.startsWith('~/')) {
      final home = Platform.environment['HOME'] ?? '';
      return p.join(home, path.substring(2));
    }
    return path;
  }
}
