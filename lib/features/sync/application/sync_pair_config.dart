/// Configuration for one sync pair.
///
/// Shared by the CLI and the desktop UI so both interpret the same config file
/// identically.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

final class SyncPairConfig {
  const SyncPairConfig({
    this.name = '',
    this.deviceId = '',
    this.pairId = '',
    required this.localRoot,
    required this.remoteUrl,
    required this.token,
    this.conflictRoot = '',
    this.timeoutSeconds = 300,
  });

  final String name;
  final String deviceId;
  final String pairId;
  final String localRoot;
  final String remoteUrl;
  final String token;

  /// Base folder for archived remote copies of conflicts.
  final String conflictRoot;
  final int timeoutSeconds;

  String get pairName {
    if (name.trim().isNotEmpty) return name.trim();
    final uri = Uri.tryParse(remoteUrl);
    final segments =
        uri?.pathSegments.where((segment) => segment.isNotEmpty).toList() ??
        const <String>[];
    return segments.isEmpty ? 'sync' : segments.last;
  }

  /// Finds the Flutter project root for development builds.
  ///
  /// A sandboxed macOS app's working directory is its container, and a
  /// launched app's working directory may be `/`, so neither can be trusted.
  /// We walk up from the executable (which lives under `build/` during
  /// development) and from the current directory.
  static String? findProjectRoot({String? executablePath}) {
    final starts = <String>{
      if (executablePath != null && executablePath.isNotEmpty)
        p.dirname(executablePath),
      Directory.current.path,
      Platform.environment['FILE_SYNC_PROJECT_ROOT'] ?? '',
    }..removeWhere((path) => path.isEmpty);

    for (final start in starts) {
      var directory = p.normalize(p.absolute(start));
      for (var depth = 0; depth < 16; depth++) {
        if (_looksLikeProjectRoot(directory)) return directory;
        final parent = p.dirname(directory);
        if (parent == directory) break;
        directory = parent;
      }
    }
    return null;
  }

  static bool _looksLikeProjectRoot(String directory) {
    return File(p.join(directory, 'pubspec.yaml')).existsSync() &&
        Directory(p.join(directory, 'tool')).existsSync();
  }
}
