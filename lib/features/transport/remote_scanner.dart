/// Scans a remote mount through the manifest endpoint.
library;

import 'package:path/path.dart' as p;

import '../sync/domain/ignore_rules.dart';
import '../sync/domain/manifest.dart';
import 'http_transport.dart';
import 'protocol.dart';

final class RemoteScanner {
  RemoteScanner({required this.transport, IgnoreRules? ignores})
    : ignores = ignores ?? IgnoreRules.defaults();

  final HttpTransport transport;
  final IgnoreRules ignores;

  /// Scans the whole mount, or only [relPath] and its subtree.
  ///
  /// Entries are always returned relative to the mount root so paths match the
  /// local side and the snapshots.
  Future<Manifest> scan({String relPath = ''}) async {
    final normalized = _normalize(relPath);
    if (normalized.isEmpty) {
      final json = await transport.getJson(ServerRoute.manifest);
      return _build(json, prefix: '');
    }

    Map<String, Object?> stat;
    try {
      stat = await transport.getJson(
        ServerRoute.stat,
        query: {'path': normalized},
      );
    } on RemoteException catch (error) {
      if (error.isNotFound) {
        return Manifest(
          root: transport.baseUrl,
          scannedAt: DateTime.now(),
          entries: const {},
        );
      }
      rethrow;
    }
    final isDirectory = stat['kind'] == 'dir';
    final requestPath = isDirectory ? normalized : _parentOf(normalized);
    final json = await transport.getJson(
      ServerRoute.manifest,
      query: requestPath.isEmpty ? null : {'path': requestPath},
    );
    final manifest = Manifest.fromJson(json);

    final entries = <String, ManifestEntry>{};
    final mtimeMs = (stat['mtime'] as num?)?.toInt() ?? 0;
    if (isDirectory) {
      entries[normalized] = ManifestEntry.directory(mtimeMs: mtimeMs);
    }

    for (final entry in manifest.entries.entries) {
      final fullPath = requestPath.isEmpty
          ? entry.key
          : '$requestPath/${entry.key}';
      if (!isDirectory && fullPath != normalized) continue;
      if (ignores.ignores(fullPath, isDirectory: entry.value.isDirectory)) {
        continue;
      }
      entries[fullPath] = entry.value;
    }

    if (!isDirectory && !entries.containsKey(normalized)) {
      entries[normalized] = ManifestEntry.file(
        size: (stat['size'] as num?)?.toInt() ?? 0,
        mtimeMs: mtimeMs,
      );
    }

    return Manifest(
      root: transport.baseUrl,
      scannedAt: DateTime.now(),
      entries: entries,
    );
  }

  Manifest _build(Map<String, Object?> json, {required String prefix}) {
    final manifest = Manifest.fromJson(json);
    final entries = <String, ManifestEntry>{};
    for (final entry in manifest.entries.entries) {
      final fullPath = prefix.isEmpty ? entry.key : '$prefix/${entry.key}';
      if (ignores.ignores(fullPath, isDirectory: entry.value.isDirectory)) {
        continue;
      }
      entries[fullPath] = entry.value;
    }
    return Manifest(
      root: transport.baseUrl,
      scannedAt: DateTime.now(),
      entries: entries,
    );
  }

  static String _normalize(String path) {
    var result = path.replaceAll('\\', '/').trim();
    while (result.startsWith('/')) {
      result = result.substring(1);
    }
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  static String _parentOf(String path) {
    final parent = p.posix.dirname(path);
    return parent == '.' ? '' : parent;
  }
}
