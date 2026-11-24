/// Reads and updates the ignore rules stored in `.file_sync_shot.json`.
///
/// Ignore rules travel with the synced folder, so the pair editor shows the
/// ones from the local snapshot and writes the edited list back to both sides.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../transport/http_file_store.dart';
import '../../transport/http_transport.dart';
import '../data/file_store.dart';
import '../data/snapshot_store.dart';
import '../domain/sync_snapshot.dart';

/// Side that supplied the ignore rules shown by the editor.
enum IgnoresSource { local, remote }

final class IgnoresLoadResult {
  const IgnoresLoadResult({required this.ignores, this.source, this.warning});

  final SnapshotIgnores ignores;

  /// Null when neither side has a snapshot yet.
  final IgnoresSource? source;

  /// Non-fatal problem such as an unreachable peer.
  final String? warning;
}

final class IgnoresSaveException implements Exception {
  const IgnoresSaveException(this.side, this.cause);

  /// `local` or `remote`.
  final String side;
  final Object cause;

  @override
  String toString() => 'Cannot update the $side snapshot: $cause';
}

/// Loads and saves one pair's ignore rules without scanning any folder.
final class PairIgnoresStore {
  PairIgnoresStore({
    required this.localRoot,
    required this.remoteUrl,
    required this.token,
    this.pairName = 'pair',
    this.timeout = const Duration(seconds: 20),
  });

  final String localRoot;

  /// Empty while the dialog has no remote mount yet.
  final String remoteUrl;
  final String token;
  final String pairName;
  final Duration timeout;

  /// Reads ignores from the local snapshot, falling back to the remote one.
  ///
  /// Nothing is migrated or rewritten here, so simply opening the dialog has
  /// no side effects. Unusable snapshots only produce a warning.
  Future<IgnoresLoadResult> load() async {
    final problems = <String>[];

    try {
      final local = await _readIgnores(LocalFileStore(localRoot));
      if (local != null) {
        return IgnoresLoadResult(
          ignores: local,
          source: IgnoresSource.local,
          warning: problems.isEmpty ? null : problems.join('\n'),
        );
      }
    } catch (error) {
      problems.add('Cannot read the local snapshot: $error');
    }

    if (remoteUrl.isNotEmpty) {
      final transport = _transport();
      try {
        final remote = await _readIgnores(HttpFileStore(transport));
        if (remote != null) {
          return IgnoresLoadResult(
            ignores: remote,
            source: IgnoresSource.remote,
            warning: problems.isEmpty ? null : problems.join('\n'),
          );
        }
      } catch (error) {
        problems.add('Cannot read the remote snapshot: $error');
      } finally {
        await transport.close();
      }
    }

    return IgnoresLoadResult(
      ignores: SnapshotIgnores.empty,
      warning: problems.isEmpty ? null : problems.join('\n'),
    );
  }

  /// Writes [ignores] to both snapshots, creating empty seeds when needed.
  ///
  /// Base and current entries are preserved; only `ignores` changes.
  Future<void> save(SnapshotIgnores ignores) async {
    final backupDir = defaultSnapshotBackupDir();
    try {
      await _write(
        SnapshotStore(
          LocalFileStore(localRoot),
          backupDir: backupDir,
          label: '$pairName-local',
        ),
        ignores,
      );
    } catch (error) {
      throw IgnoresSaveException('local', error);
    }

    if (remoteUrl.isEmpty) return;
    final transport = _transport();
    try {
      await _write(
        SnapshotStore(
          HttpFileStore(transport),
          backupDir: backupDir,
          label: '$pairName-remote',
        ),
        ignores,
      );
    } catch (error) {
      throw IgnoresSaveException('remote', error);
    } finally {
      await transport.close();
    }
  }

  HttpTransport _transport() {
    return HttpTransport(baseUrl: remoteUrl, token: token, timeout: timeout);
  }

  static Future<void> _write(
    SnapshotStore store,
    SnapshotIgnores ignores,
  ) async {
    final loaded = await store.load();
    final existing = loaded.snapshot;
    final next = existing == null
        ? SideSnapshot(
            base: SnapshotState.empty(),
            current: SnapshotState.empty(),
            ignores: ignores,
          )
        : existing.copyWith(ignores: ignores);
    await store.save(next);
  }

  static Future<SnapshotIgnores?> _readIgnores(FileStore store) async {
    if (!await store.exists(SnapshotStore.defaultFileName)) return null;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in store.openRead(SnapshotStore.defaultFileName)) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (bytes.isEmpty) return null;
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) return null;
    final raw = decoded['ignores'];
    return raw == null ? SnapshotIgnores.empty : SnapshotIgnores.fromJson(raw);
  }
}
