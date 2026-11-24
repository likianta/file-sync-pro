/// A sync participant: a local folder or a remote mount.
library;

import 'package:path/path.dart' as p;

import '../../transport/http_file_store.dart';
import '../../transport/http_transport.dart';
import '../../transport/protocol.dart';
import '../../transport/remote_scanner.dart';
import '../data/file_store.dart';
import '../data/local_scanner.dart';
import '../data/snapshot_manager.dart';
import '../data/snapshot_store.dart';
import '../domain/ignore_rules.dart';
import '../domain/manifest.dart';
import '../domain/sync_snapshot.dart';

abstract interface class SyncSource {
  /// Stable identity used to validate the saved base manifest.
  String get id;

  FileStore get store;

  /// Scans the whole source, or only [subPath] and its subtree.
  Future<Manifest> scan({
    String? subPath,
    void Function(int scanned)? onProgress,
  });

  /// Reads this side's `.file_sync_shot.json`.
  Future<SnapshotLoadResult> loadSnapshot();

  /// Scans one folder and merges it into this side's `current` snapshot.
  Future<SideSnapshot> scanSnapshot({
    String? subPath,
    bool createIfMissing = false,
    void Function(int scanned)? onProgress,
  });

  /// Writes this side's `.file_sync_shot.json`.
  Future<void> saveSnapshot(SideSnapshot snapshot);

  Future<void> close();
}

final class LocalSyncSource implements SyncSource {
  LocalSyncSource(
    String root, {
    IgnoreRules? ignores,
    bool computeHashes = true,
    HashCache? hashCache,
    String? snapshotBackupDir,
    String snapshotLabel = 'local',
  }) : id = p.normalize(p.absolute(root)),
       _store = LocalFileStore(root),
       _ignores = ignores ?? IgnoreRules.defaults(),
       _scanner = LocalScanner(
         ignores: ignores,
         computeHashes: computeHashes,
         hashCache: hashCache,
       ) {
    _snapshotStore = SnapshotStore(
      _store,
      backupDir: snapshotBackupDir,
      label: snapshotLabel,
    );
    _snapshots = LocalSnapshotManager(
      root: id,
      store: _snapshotStore,
      ignores: _ignores,
      hashCache: hashCache,
    );
  }

  @override
  final String id;

  final LocalFileStore _store;
  final IgnoreRules _ignores;
  final LocalScanner _scanner;
  late final SnapshotStore _snapshotStore;
  late final LocalSnapshotManager _snapshots;

  @override
  FileStore get store => _store;

  @override
  Future<Manifest> scan({
    String? subPath,
    void Function(int scanned)? onProgress,
  }) => _scanner.scan(id, subPath: subPath, onProgress: onProgress);

  @override
  Future<SnapshotLoadResult> loadSnapshot() async {
    final result = await _snapshots.load();
    final snapshot = result.snapshot;
    if (snapshot == null) return result;
    return SnapshotLoadResult(snapshot: filterSideSnapshot(snapshot, _ignores));
  }

  @override
  Future<SideSnapshot> scanSnapshot({
    String? subPath,
    bool createIfMissing = false,
    void Function(int scanned)? onProgress,
  }) {
    return _snapshots.scan(
      subPath: subPath,
      createIfMissing: createIfMissing,
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
    IgnoreRules? ignores,
    Duration timeout = const Duration(minutes: 5),
    String? snapshotBackupDir,
    String snapshotLabel = 'remote',
  }) : _transport = HttpTransport(
         baseUrl: baseUrl,
         token: token,
         timeout: timeout,
       ),
       _ignores = ignores ?? IgnoreRules.defaults() {
    _store = HttpFileStore(_transport);
    _scanner = RemoteScanner(transport: _transport, ignores: _ignores);
    _snapshotStore = SnapshotStore(
      _store,
      backupDir: snapshotBackupDir,
      label: snapshotLabel,
    );
  }

  final HttpTransport _transport;
  final IgnoreRules _ignores;
  late final HttpFileStore _store;
  late final RemoteScanner _scanner;
  late final SnapshotStore _snapshotStore;

  @override
  String get id => _transport.baseUrl;

  @override
  FileStore get store => _store;

  HttpTransport get transport => _transport;

  @override
  Future<Manifest> scan({
    String? subPath,
    void Function(int scanned)? onProgress,
  }) async {
    onProgress?.call(0);
    final manifest = await _scanner.scan(relPath: subPath ?? '');
    onProgress?.call(manifest.entries.length);
    return manifest;
  }

  @override
  Future<SnapshotLoadResult> loadSnapshot() async {
    final result = await _snapshotStore.load();
    final snapshot = result.snapshot;
    if (snapshot == null) return result;
    return SnapshotLoadResult(snapshot: filterSideSnapshot(snapshot, _ignores));
  }

  @override
  Future<SideSnapshot> scanSnapshot({
    String? subPath,
    bool createIfMissing = false,
    void Function(int scanned)? onProgress,
  }) async {
    final scope = normalizeScope(subPath);
    onProgress?.call(0);
    final json = await _transport.postJson(
      ServerRoute.snapshot,
      query: {
        if (scope.isNotEmpty) 'path': scope,
        'mode': createIfMissing ? 'init' : 'refresh',
      },
    );
    final snapshot = filterSideSnapshot(SideSnapshot.fromJson(json), _ignores);
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
