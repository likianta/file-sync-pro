import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../transport/http_transport.dart';
import '../application/sync_engine.dart';
import '../application/sync_pair_config.dart';
import '../application/sync_source.dart';
import '../data/snapshot_manager.dart';
import '../data/snapshot_store.dart';
import '../domain/sync_plan.dart';
import '../domain/sync_snapshot.dart';

enum SyncDashboardStatus { idle, loading, scanning, applying, resolving, error }

/// Drives one sync pair for the new tree-based dashboard.
///
/// Scans are user-triggered only. Check and Sync consume `.file_sync_shot.json`
/// and never walk the filesystem on their own.
final class SyncDashboardController extends ChangeNotifier {
  SyncDashboardController({required this.config});

  final SyncPairConfig config;

  SyncDashboardStatus _status = SyncDashboardStatus.idle;
  SideSnapshot? _localSnapshot;
  SideSnapshot? _remoteSnapshot;
  SyncPreview? _preview;
  SyncPreview? _diffPreview;
  String? _diffSubPath;
  SyncReport? _report;
  String? _errorMessage;
  int _applied = 0;
  String? _currentPath;
  ScanPhase? _scanPhase;
  int _scanned = 0;
  bool _needsInitialScan = false;
  final List<String> _log = [];
  final Stopwatch _scanWatch = Stopwatch();
  final Stopwatch _phaseWatch = Stopwatch();
  bool _disposed = false;

  SyncDashboardStatus get status => _status;

  SyncPreview? get preview => _preview;

  SideSnapshot? get localSnapshot => _localSnapshot;

  SideSnapshot? get remoteSnapshot => _remoteSnapshot;

  /// True when at least one side has no usable `current` snapshot.
  bool get needsInitialScan => _needsInitialScan;

  /// The preview shown in the Check sheet. It is scoped when Check was run on
  /// a selected node.
  SyncPreview? get diffPreview => _diffPreview;

  SyncPlan? get diffPlan => _diffPreview?.plan ?? _preview?.plan;

  /// The node Check was scoped to, or null for the whole tree.
  String? get diffSubPath => _diffSubPath;

  SyncReport? get report => _report;

  String? get errorMessage => _errorMessage;

  int get applied => _applied;

  String? get currentPath => _currentPath;

  List<String> get log => List.unmodifiable(_log);

  bool get busy =>
      _status == SyncDashboardStatus.loading ||
      _status == SyncDashboardStatus.scanning ||
      _status == SyncDashboardStatus.applying ||
      _status == SyncDashboardStatus.resolving;

  String? get selectionHint => null;

  String get statusLabel {
    return switch (_status) {
      SyncDashboardStatus.idle => _idleLabel,
      SyncDashboardStatus.loading => 'Loading snapshots...',
      SyncDashboardStatus.scanning => _scanLabel,
      SyncDashboardStatus.applying =>
        _applied == 0 ? 'Applying...' : 'Applying... $_applied actions',
      SyncDashboardStatus.resolving => 'Resolving conflicts...',
      SyncDashboardStatus.error => 'Error',
    };
  }

  String get _idleLabel {
    if (_needsInitialScan) return 'Scan required';
    final report = _report;
    if (report == null) {
      return _preview == null ? 'Ready' : 'Snapshots loaded';
    }
    final apply = report.applyReport;
    if (apply == null) return 'Ready';
    return 'Last run: ${apply.total} actions · '
        '${report.conflictCount} conflicts';
  }

  String get _scanLabel {
    return switch (_scanPhase) {
      ScanPhase.local =>
        _scanned == 0
            ? 'Scanning local files...'
            : 'Scanning local files... $_scanned',
      ScanPhase.remote =>
        _scanned == 0
            ? 'Scanning remote files...'
            : 'Scanning remote files... $_scanned',
      null => 'Starting scan...',
    };
  }

  /// Loads both snapshots without scanning any folder.
  ///
  /// When a snapshot is missing, [needsInitialScan] becomes true and the UI
  /// must ask the user to run a full root scan before trees can be shown.
  Future<void> load() async {
    if (busy) return;
    _needsInitialScan = false;
    _diffPreview = null;
    _diffSubPath = null;
    _preview = null;
    _report = null;
    _applied = 0;
    _currentPath = null;
    _status = SyncDashboardStatus.loading;
    _errorMessage = null;
    _scanPhase = null;
    _scanned = 0;
    _appendLog('Loading snapshots...');
    _notify();

    final engine = _createEngine();
    try {
      final loaded = await engine.loadSnapshots();
      _logSnapshotResult('local', loaded.a);
      _logSnapshotResult('remote', loaded.b);

      if (!_hasScan(loaded.a.snapshot) || !_hasScan(loaded.b.snapshot)) {
        _localSnapshot = loaded.a.snapshot;
        _remoteSnapshot = loaded.b.snapshot;
        _needsInitialScan = true;
        _appendLog('Scan required before trees can be loaded.');
        _status = SyncDashboardStatus.idle;
        return;
      }

      _localSnapshot = loaded.a.snapshot;
      _remoteSnapshot = loaded.b.snapshot;
      _preview = engine.planFromSnapshots(_localSnapshot!, _remoteSnapshot!);
      _status = SyncDashboardStatus.idle;
    } catch (error) {
      _fail(error);
    } finally {
      await engine.dispose();
      _notify();
    }
  }

  /// Scans both roots and creates the initial `current` snapshots.
  Future<void> initializeSnapshots() async {
    if (busy) return;
    _status = SyncDashboardStatus.scanning;
    _errorMessage = null;
    _scanPhase = null;
    _scanned = 0;
    _appendLog('Scanning both roots to create snapshots...');
    _startScanTiming();
    _notify();

    final engine = _createEngine();
    try {
      final result = await engine.scanBoth(
        createIfMissing: true,
        onProgress: _onInitialScanProgress,
      );
      _localSnapshot = result.a;
      _remoteSnapshot = result.b;
      _preview = engine.planFromSnapshots(result.a, result.b);
      _needsInitialScan = false;
      _logScanFinished();
      _status = SyncDashboardStatus.idle;
      _appendLog(
        'Snapshots created. Local current: ${_shortKey(result.a)}; '
        'remote current: ${_shortKey(result.b)}.',
      );
    } catch (error) {
      _fail(error);
    } finally {
      await engine.dispose();
      _notify();
    }
  }

  /// Rescans only one side. [subPath] empty means the root.
  Future<void> refreshSide({required bool left, String? subPath}) async {
    if (busy) return;
    if (_needsInitialScan ||
        _localSnapshot == null ||
        _remoteSnapshot == null) {
      _needsInitialScan = true;
      _notify();
      return;
    }

    final side = left ? 'local' : 'remote';
    final scope = subPath == null || subPath.isEmpty ? 'root' : subPath;
    _status = SyncDashboardStatus.scanning;
    _errorMessage = null;
    _scanPhase = left ? ScanPhase.local : ScanPhase.remote;
    _scanned = 0;
    _appendLog('Scanning $side $scope...');
    final watch = Stopwatch()..start();
    _notify();

    final engine = _createEngine();
    try {
      final snapshot = await engine.scanSide(
        left: left,
        subPath: subPath,
        onProgress: (scanned) {
          _scanned = scanned;
          _notify();
        },
      );
      if (left) {
        _localSnapshot = snapshot;
      } else {
        _remoteSnapshot = snapshot;
      }
      _preview = engine.planFromSnapshots(_localSnapshot!, _remoteSnapshot!);
      _diffPreview = null;
      _diffSubPath = null;
      _status = SyncDashboardStatus.idle;
      watch.stop();
      _appendLog(
        '$side scan finished in ${watch.elapsedMilliseconds} ms. '
        'Snapshot current updated.',
      );
    } catch (error) {
      _fail(error);
    } finally {
      await engine.dispose();
      _notify();
    }
  }

  /// Builds a diff from the current snapshots without scanning.
  Future<void> check({String? subPath}) async {
    if (busy) return;
    if (_needsInitialScan ||
        _localSnapshot == null ||
        _remoteSnapshot == null) {
      _needsInitialScan = true;
      _notify();
      return;
    }

    final scope = subPath == null || subPath.isEmpty ? null : subPath;
    _log.clear();
    _report = null;
    _applied = 0;
    _currentPath = null;
    _diffSubPath = scope;
    _errorMessage = null;
    _appendLog('Checking ${scope ?? 'the whole tree'} from snapshots...');
    _notify();

    final engine = _createEngine();
    try {
      final preview = engine.planFromSnapshots(
        _localSnapshot!,
        _remoteSnapshot!,
        subPath: scope,
      );
      _diffPreview = preview;
      if (scope == null) {
        _preview = preview;
      }
      final plan = preview.plan;
      _appendLog(
        'Plan${scope == null ? '' : ' ($scope)'}: '
        '${plan.createCount} create, '
        '${plan.updateCount} update, '
        '${plan.deleteCount} delete, '
        '${plan.conflicts.length} conflicts.',
      );
    } catch (error) {
      _fail(error);
    } finally {
      await engine.dispose();
      _notify();
    }
  }

  /// Runs a two-way or one-way sync for [subPath] (null means the whole tree).
  Future<void> run({required SyncDirection direction, String? subPath}) async {
    if (busy) return;
    if (_needsInitialScan ||
        _localSnapshot == null ||
        _remoteSnapshot == null) {
      _needsInitialScan = true;
      _notify();
      return;
    }

    _status = SyncDashboardStatus.applying;
    _errorMessage = null;
    _applied = 0;
    _currentPath = null;
    _appendLog(
      '${_directionLabel(direction)} '
      '${subPath == null || subPath.isEmpty ? 'whole tree' : subPath}...',
    );
    _notify();

    final engine = _createEngine();
    try {
      final preview =
          _preview ??
          engine.planFromSnapshots(_localSnapshot!, _remoteSnapshot!);
      final report = await engine.execute(
        preview,
        aSnapshot: _localSnapshot!,
        bSnapshot: _remoteSnapshot!,
        direction: direction,
        subPath: subPath,
        onAction: (action) {
          _applied++;
          _currentPath = action.path;
          _appendLog(_formatAction(action));
          _notify();
        },
      );
      _report = report;
      _localSnapshot = report.aSnapshot ?? _localSnapshot;
      _remoteSnapshot = report.bSnapshot ?? _remoteSnapshot;
      _preview = engine.planFromSnapshots(_localSnapshot!, _remoteSnapshot!);
      _diffPreview = null;
      _diffSubPath = null;

      final apply = report.applyReport;
      if (apply != null) {
        _appendLog(
          'Done: ${apply.created} created, '
          '${apply.updated} updated, '
          '${apply.deleted} deleted, '
          '${apply.removedDirectories} dirs removed.',
        );
      }
      if (report.hasConflicts) {
        _appendLog(
          '${report.conflictCount} conflict(s) left untouched. '
          'Backups: ${report.conflictBackupRoot}.',
        );
      }
      _appendLog('Snapshots updated incrementally; no rescan performed.');
      _status = SyncDashboardStatus.idle;
    } catch (error) {
      _fail(error);
    } finally {
      await engine.dispose();
      _notify();
    }
  }

  /// Conflicts from the last check, or from the last executed run.
  List<SyncConflict> get conflicts {
    return _diffPreview?.plan.conflicts ??
        _preview?.plan.conflicts ??
        _report?.plan.conflicts ??
        const <SyncConflict>[];
  }

  Future<void> resolveConflict(String path, ConflictSide side) async {
    if (busy) return;
    final preview = _diffPreview ?? _preview;
    if (preview == null || _localSnapshot == null || _remoteSnapshot == null) {
      return;
    }

    _status = SyncDashboardStatus.resolving;
    _errorMessage = null;
    _appendLog(
      'Resolving $path by keeping '
      '${side == ConflictSide.left ? 'local' : 'remote'}...',
    );
    _notify();

    final engine = _createEngine();
    try {
      final result = await engine.resolveConflicts(
        preview,
        aSnapshot: _localSnapshot!,
        bSnapshot: _remoteSnapshot!,
        choices: {path: side},
      );
      _localSnapshot = result.aSnapshot ?? _localSnapshot;
      _remoteSnapshot = result.bSnapshot ?? _remoteSnapshot;
      _preview = engine.planFromSnapshots(_localSnapshot!, _remoteSnapshot!);
      final scope = _diffSubPath;
      _diffPreview = scope == null
          ? _preview
          : engine.planFromSnapshots(
              _localSnapshot!,
              _remoteSnapshot!,
              subPath: scope,
            );
      _status = SyncDashboardStatus.idle;
      _appendLog(
        'Resolved ${result.resolved} conflict(s). '
        '${result.remaining} left.',
      );
    } catch (error) {
      _fail(error);
    } finally {
      await engine.dispose();
      _notify();
    }
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    if (_status == SyncDashboardStatus.error) {
      _status = SyncDashboardStatus.idle;
    }
    _notify();
  }

  void _onInitialScanProgress(ScanPhase phase, int scanned) {
    final phaseChanged = _scanPhase != phase;
    if (!phaseChanged && scanned == _scanned) return;
    if (phaseChanged) {
      if (phase == ScanPhase.local) {
        _phaseWatch
          ..reset()
          ..start();
        _appendLog('Scanning local files...');
      } else {
        final localMs = _phaseWatch.elapsedMilliseconds;
        _phaseWatch
          ..reset()
          ..start();
        _appendLog(
          'Local scan finished in $localMs ms. Scanning remote files...',
        );
      }
    } else if (phase == ScanPhase.remote && scanned > 0) {
      _phaseWatch.stop();
      _appendLog(
        'Remote scan finished in ${_phaseWatch.elapsedMilliseconds} ms.',
      );
    }
    _scanPhase = phase;
    _scanned = scanned;
    _notify();
  }

  void _startScanTiming() {
    _scanWatch
      ..reset()
      ..start();
    _phaseWatch.reset();
  }

  void _logScanFinished() {
    _scanWatch.stop();
    _appendLog('Scan finished in ${_scanWatch.elapsedMilliseconds} ms.');
  }

  void _logSnapshotResult(String side, SnapshotLoadResult result) {
    if (result.snapshot != null) {
      final current = result.snapshot!.current;
      _appendLog(
        'Loaded $side snapshot: current ${_shortKey(result.snapshot!)} '
        '(${_formatTime(current.updatedAt)}).',
      );
      return;
    }
    if (result.backupPath != null) {
      _appendLog('Legacy $side snapshot moved to ${result.backupPath}.');
      return;
    }
    _appendLog('No $side snapshot found.');
  }

  static bool _hasScan(SideSnapshot? snapshot) {
    return snapshot != null && snapshot.current.entries.isNotEmpty;
  }

  String _shortKey(SideSnapshot snapshot) {
    final key = snapshot.current.key;
    return key.length <= 8 ? key : key.substring(0, 8);
  }

  static String _formatTime(int milliseconds) {
    final time = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    return '${time.year}-${_two(time.month)}-${_two(time.day)} '
        '${_two(time.hour)}:${_two(time.minute)}';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  SyncEngine _createEngine() {
    final backupDir = defaultSnapshotBackupDir();
    return SyncEngine(
      a: LocalSyncSource(
        config.localRoot,
        snapshotBackupDir: backupDir,
        snapshotLabel: '${config.pairName}-local',
      ),
      b: RemoteSyncSource(
        baseUrl: config.remoteUrl,
        token: config.token,
        timeout: Duration(seconds: config.timeoutSeconds),
        snapshotBackupDir: backupDir,
        snapshotLabel: '${config.pairName}-remote',
      ),
      stateDir: config.stateDir,
    );
  }

  void _fail(Object error) {
    _status = SyncDashboardStatus.error;
    _errorMessage = _describe(error);
    _appendLog('ERROR: $_errorMessage');
  }

  String _describe(Object error) {
    if (error is SnapshotMissingException) {
      return 'A snapshot is missing. Run the initial scan first.';
    }
    if (error is SnapshotPathException) {
      return error.message;
    }
    if (error is SnapshotLegacyException) {
      return 'This side uses an old snapshot format. Restart the pair so it '
          'can be migrated.';
    }
    if (error is RemoteException) {
      final hint = switch (error.statusCode) {
        401 => 'Authentication failed. Set the same token on both sides.',
        404 =>
          'Mount or path not found. The URL must include the mount name, '
              'for example http://host:2160/photolens.',
        409 =>
          'The server refused the operation. The snapshot may be missing, '
              'or the target is a different kind of entry.',
        _ => 'The server returned an error.',
      };
      return '${error.statusCode} ${error.message}\n$hint';
    }
    if (error is SocketException) {
      return 'Cannot reach ${config.remoteUrl}.\n'
          'Check that the peer file server is running and reachable.';
    }
    return error.toString();
  }

  void _appendLog(String line) {
    final stamp = DateTime.now().toIso8601String().substring(11, 19);
    _log.add('$stamp  $line');
    if (_log.length > 500) {
      _log.removeAt(0);
    }
  }

  static String _directionLabel(SyncDirection direction) {
    return switch (direction) {
      SyncDirection.both => 'Syncing',
      SyncDirection.push => 'Pushing',
      SyncDirection.pull => 'Pulling',
    };
  }

  static String _formatAction(SyncAction action) {
    final label = switch (action.kind) {
      SyncActionKind.createRight => 'Create right',
      SyncActionKind.updateRight => 'Update right',
      SyncActionKind.deleteRight => 'Delete right',
      SyncActionKind.createLeft => 'Create left',
      SyncActionKind.updateLeft => 'Update left',
      SyncActionKind.deleteLeft => 'Delete left',
    };
    return '$label ${action.path}';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
