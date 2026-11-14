/// Scans a remote mount through the manifest endpoint.
library;

import '../sync/domain/ignore_rules.dart';
import '../sync/domain/manifest.dart';
import 'http_transport.dart';
import 'protocol.dart';

final class RemoteScanner {
  RemoteScanner({required this.transport, IgnoreRules? ignores})
    : ignores = ignores ?? IgnoreRules.defaults();

  final HttpTransport transport;
  final IgnoreRules ignores;

  Future<Manifest> scan([String relPath = '']) async {
    final json = await transport.getJson(
      ServerRoute.manifest,
      query: relPath.isEmpty ? null : {'path': relPath},
    );
    final manifest = Manifest.fromJson(json);

    // The server applies the same defaults, but filter again so a mismatched
    // server configuration can never leak ignored entries into a plan.
    final entries = <String, ManifestEntry>{};
    for (final entry in manifest.entries.entries) {
      if (ignores.ignores(entry.key, isDirectory: entry.value.isDirectory)) {
        continue;
      }
      entries[entry.key] = entry.value;
    }

    return Manifest(
      root: transport.baseUrl,
      scannedAt: DateTime.now(),
      entries: entries,
    );
  }
}
