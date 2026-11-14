/// Configuration for one sync pair.
///
/// Shared by the CLI and the desktop UI so both interpret the same config file
/// identically.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

final class SyncPairConfig {
  const SyncPairConfig({
    required this.localRoot,
    required this.remoteUrl,
    required this.token,
    required this.stateDir,
    this.timeoutSeconds = 300,
    this.extraIgnores = const [],
  });

  final String localRoot;
  final String remoteUrl;
  final String token;
  final String stateDir;
  final int timeoutSeconds;
  final List<String> extraIgnores;

  String get pairName {
    final uri = Uri.tryParse(remoteUrl);
    final segments =
        uri?.pathSegments.where((segment) => segment.isNotEmpty).toList() ??
        const <String>[];
    return segments.isEmpty ? 'sync' : segments.last;
  }

  /// Loads a config file with optional overrides (CLI flags or UI settings).
  ///
  /// Returns null when no remote URL is configured, so the caller can show a
  /// setup screen instead of failing with a partial config.
  static SyncPairConfig? load({
    required String configPath,
    required String projectRoot,
    String? localRoot,
    String? remoteUrl,
    String? token,
    String? stateDir,
    int? timeoutSeconds,
  }) {
    final json = _readJson(configPath);
    final resolvedRemote = remoteUrl ?? json['remoteUrl'] as String? ?? '';
    if (resolvedRemote.trim().isEmpty) return null;

    final rawLocal =
        localRoot ??
        json['localRoot'] as String? ??
        p.join(projectRoot, '..', 'photolens');
    final rawState =
        stateDir ??
        json['stateDir'] as String? ??
        p.join(projectRoot, 'data', 'sync_pairs', 'photolens');

    final ignores = json['ignores'];
    return SyncPairConfig(
      localRoot: _resolve(projectRoot, _expandUser(rawLocal)),
      remoteUrl: resolvedRemote.trim(),
      token:
          token ??
          Platform.environment['FILE_SYNC_TOKEN'] ??
          json['token'] as String? ??
          '',
      stateDir: _resolve(projectRoot, _expandUser(rawState)),
      timeoutSeconds:
          timeoutSeconds ?? (json['timeoutSeconds'] as num?)?.toInt() ?? 300,
      extraIgnores: ignores is List
          ? ignores.whereType<String>().toList(growable: false)
          : const <String>[],
    );
  }

  static Map<String, Object?> _readJson(String path) {
    final file = File(path);
    if (!file.existsSync()) return const {};
    final text = file.readAsStringSync();
    if (text.trim().isEmpty) return const {};
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw FormatException('Config must be a JSON object: $path');
    }
    return decoded.cast<String, Object?>();
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
