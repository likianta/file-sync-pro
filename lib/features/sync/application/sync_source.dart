/// A sync participant: a local folder or a remote mount.
library;

import 'dart:convert';

import 'package:path/path.dart' as p;

import '../../transport/http_file_store.dart';
import '../../transport/http_transport.dart';
import '../../transport/protocol.dart';
import '../data/file_store.dart';
import '../data/snapshot_manager.dart';
import '../data/snapshot_store.dart';
import '../domain/sync_snapshot.dart';

abstract interface class SyncSource {
  /// Stable identity used to validate the saved base manifest.
  String get id;

  FileStore get store;

  /// Reads this side's `.file_sync_shot.json`.
  Future<SnapshotLoadResult> loadSnapshot();

  /// Scans one folder and merges it into this side's `current` snapshot.
  ///
  /// [ignores] is only used when the snapshot is created for the first time.
  Future<SideSnapshot> scanSnapshot({
    String? subPath,
    bool createIfMissing = false,
    SnapshotIgnores? ignores,
    void Function(int scanned)? onProgress,
  });

  /// Writes this side's `.file_sync_shot.json`.
  Future<void> saveSnapshot(SideSnapshot snapshot);

  Future<void> close();
}

final class LocalSyncSource implements SyncSource {
  LocalSyncSource(
    String root, {
    String? snapshotBackupDir,
    String snapshotLabel = 'local',
    SnapshotIgnores defaultIgnores = SnapshotIgnores.empty,
  }) : id = p.normalize(p.absolute(root)),
       _store = LocalFileStore(root) {
    _snapshotStore = SnapshotStore(
      _store,
      backupDir: snapshotBackupDir,
      label: snapshotLabel,
    );
    _snapshots = LocalSnapshotManager(
      root: id,
      store: _snapshotStore,
      defaultIgnores: defaultIgnores,
    );
  }

  @override
  final String id;

  final LocalFileStore _store;
  late final SnapshotStore _snapshotStore;
  late final LocalSnapshotManager _snapshots;

  @override
  FileStore get store => _store;

  @override
  Future<SnapshotLoadResult> loadSnapshot() => _snapshots.load();

  @override
  Future<SideSnapshot> scanSnapshot({
    String? subPath,
    bool createIfMissing = false,
    SnapshotIgnores? ignores,
    void Function(int scanned)? onProgress,
  }) {
    return _snapshots.scan(
      subPath: subPath,
      createIfMissing: createIfMissing,
      ignores: ignores,
      onProgress: onProgress,
    );
  }

  @override
  Future<void> saveSnapshot(SideSnapshot snapshot) => _snapshots.save(snapshot);

  @override
  Future<void> close() async {}
}

final class RemoteSyncSource implements SyncSource {
  RemoteSyncSource({
    required String baseUrl,
    String token = '',
    Duration timeout = const Duration(minutes: 5),
    String? snapshotBackupDir,
    String snapshotLabel = 'remote',
  }) : _transport = HttpTransport(
         baseUrl: baseUrl,
         token: token,
         timeout: timeout,
       ) {
    _store = HttpFileStore(_transport);
    _snapshotStore = SnapshotStore(
      _store,
      backupDir: snapshotBackupDir,
      label: snapshotLabel,
    );
  }

  final HttpTransport _transport;
  late final HttpFileStore _store;
  late final SnapshotStore _snapshotStore;

  @override
  String get id => _transport.baseUrl;

  @override
  FileStore get store => _store;

  HttpTransport get transport => _transport;

  @override
  Future<SnapshotLoadResult> loadSnapshot() => _snapshotStore.load();

  @override
  Future<SideSnapshot> scanSnapshot({
    String? subPath,
    bool createIfMissing = false,
    SnapshotIgnores? ignores,
    void Function(int scanned)? onProgress,
  }) async {
    final scope = normalizeScope(subPath);
    onProgress?.call(0);
    final json = await _transport.postJson(
      ServerRoute.snapshot,
      query: {
        if (scope.isNotEmpty) 'path': scope,
        'mode': createIfMissing ? 'init' : 'refresh',
        if (createIfMissing && ignores != null)
          'ignores': jsonEncode(ignores.toJson()),
      },
    );
    final snapshot = SideSnapshot.fromJson(json);
    final fileCount = snapshot.current.entries.values.fold<int>(
      0,
      (sum, folder) => sum + folder.files.length,
    );
    onProgress?.call(fileCount);
    return snapshot;
  }

  @override
  Future<void> saveSnapshot(SideSnapshot snapshot) async {
    await _snapshotStore.save(snapshot);
  }

  @override
  Future<void> close() async {
    await _transport.close();
  }
}
