import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../transport/http_transport.dart';
import '../application/sync_engine.dart';
import '../application/sync_pair_config.dart';
import '../application/sync_source.dart';
import '../data/file_hash_cache.dart';
import '../domain/ignore_rules.dart';
import '../domain/sync_plan.dart';

enum SyncDashboardStatus { idle, scanning, applying, resolving, error }

/// Drives one sync pair for the new tree-based dashboard.
final class SyncDashboardController extends ChangeNotifier {
  SyncDashboardController({required this.config});

  final SyncPairConfig config;

  SyncDashboardStatus _status = SyncDashboardStatus.idle;
  SyncPreview? _preview;
  SyncPreview? _diffPreview;
  String? _diffSubPath;
  SyncReport? _report;
  String? _errorMessage;
  int _applied = 0;
  String? _currentPath;
  ScanPhase? _scanPhase;
  int _scanned = 0;
  FileHashCache? _hashCache;
  final List<String> _log = [];
  bool _disposed = false;

  SyncDashboardStatus get status => _status;

  SyncPreview? get preview => _preview;

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
      _status == SyncDashboardStatus.scanning ||
      _status == SyncDashboardStatus.applying ||
      _status == SyncDashboardStatus.resolving;

  String? get selectionHint => null;

  String get statusLabel {
    return switch (_status) {
      SyncDashboardStatus.idle => _idleLabel,
      SyncDashboardStatus.scanning => _scanLabel,
      SyncDashboardStatus.applying =>
        _applied == 0 ? 'Applying...' : 'Applying... $_applied actions',
      SyncDashboardStatus.resolving => 'Resolving conflicts...',
      SyncDashboardStatus.error => 'Error',
    };
  }

  String get _idleLabel {
    final report = _report;
    if (report == null) return 'Ready';
    final apply = report.applyReport;
    if (apply == null) return 'Ready';
    return 'Last run: ${apply.total} actions · '
        '${report.conflictCount} conflicts';
  }

  String get _scanLabel {
    return switch (_scanPhase) {
      ScanPhase.local => 'Scanning local files... $_scanned',
      ScanPhase.remote =>
        _scanned == 0
            ? 'Downloading remote manifest...'
            : 'Scanning remote files... $_scanned',
      null => 'Starting scan...',
    };
  }

  /// Re-scans both sides and rebuilds the trees without touching the disk.
  Future<void> refresh() async {
    if (busy) return;
    _diffPreview = null;
    _diffSubPath = null;
    _status = SyncDashboardStatus.scanning;
    _errorMessage = null;
    _scanPhase = null;
    _scanned = 0;
    _notify();

    final engine = _createEngine();
    try {
      await Directory(config.localRoot).create(recursive: true);
      _preview = await engine.preview(onProgress: _onScanProgress);
      _status = SyncDashboardStatus.idle;
    } catch (error) {
      _fail(error);
    } finally {
      await engine.dispose();
      _notify();
    }
  }

  /// Compares both sides and prepares the diff sheet.
  ///
  /// When [subPath] is set only that node's subtree is scanned and compared,
  /// so checking one folder does not walk or hash the whole tree.
  Future<void> check({String? subPath}) async {
    if (busy) return;
    final scope = subPath == null || subPath.isEmpty ? null : subPath;
    _log.clear();
    _report = null;
    _applied = 0;
    _currentPath = null;
    _diffSubPath = scope;
    _status = SyncDashboardStatus.scanning;
    _errorMessage = null;
    _scanPhase = null;
    _scanned = 0;
    _appendLog('Checking ${scope ?? 'the whole tree'}...');
    _notify();

    final engine = _createEngine();
    try {
      final preview = await engine.preview(
        subPath: scope,
        onProgress: _onScanProgress,
      );
      _diffPreview = preview;
      if (scope == null) {
        _preview = preview;
      }
      _status = SyncDashboardStatus.idle;
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
    if (_preview == null) {
      await refresh();
      if (_preview == null || _status == SyncDashboardStatus.error) return;
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
      final report = await engine.execute(
        _preview!,
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
      _status = SyncDashboardStatus.idle;
      _preview = await engine.preview(onProgress: _onScanProgress);
      _diffPreview = null;
      _diffSubPath = null;
    } catch (error) {
      _fail(error);
    } finally {
      await engine.dispose();
      _notify();
    }
  }

  /// Conflicts from the last check, or from the last executed run.
  List<SyncConflict> get conflicts {
    return _preview?.plan.conflicts ??
        _report?.plan.conflicts ??
        const <SyncConflict>[];
  }

  Future<void> resolveConflict(String path, ConflictSide side) async {
    if (busy) return;
    final preview = _diffPreview ?? _preview ?? _report?.preview;
    if (preview == null) return;

    _status = SyncDashboardStatus.resolving;
    _errorMessage = null;
    _appendLog(
      'Resolving $path by keeping '
      '${side == ConflictSide.left ? 'local' : 'remote'}...',
    );
    _notify();

    final engine = _createEngine();
    try {
      final result = await engine.resolveConflicts(preview, {path: side});
      _preview = await engine.preview();
      final scope = _diffSubPath;
      _diffPreview = scope == null
          ? _preview
          : await engine.preview(subPath: scope);
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

  void _onScanProgress(ScanPhase phase, int scanned) {
    final phaseChanged = _scanPhase != phase;
    if (!phaseChanged && scanned == _scanned) return;
    if (phaseChanged) {
      _appendLog(
        phase == ScanPhase.local
            ? 'Scanning local files...'
            : 'Local scan finished. Scanning remote files...',
      );
    }
    _scanPhase = phase;
    _scanned = scanned;
    _notify();
  }

  FileHashCache _cache() {
    return _hashCache ??= FileHashCache(
      p.normalize(p.absolute(p.join(config.stateDir, 'hash_cache.json'))),
    );
  }

  SyncEngine _createEngine() {
    final ignores = IgnoreRules.defaults(extra: config.extraIgnores);
    return SyncEngine(
      a: LocalSyncSource(
        config.localRoot,
        ignores: ignores,
        hashCache: _cache(),
      ),
      b: RemoteSyncSource(
        baseUrl: config.remoteUrl,
        token: config.token,
        ignores: ignores,
        timeout: Duration(seconds: config.timeoutSeconds),
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
    if (error is RemoteException) {
      final hint = switch (error.statusCode) {
        401 => 'Authentication failed. Set the same token on both sides.',
        404 =>
          'Mount or path not found. The URL must include the mount name, '
              'for example http://host:2160/photolens.',
        409 =>
          'The server refused the operation because the target is a '
              'non-empty directory or a different kind of entry.',
        _ => 'The server returned an error.',
      };
      return '${error.statusCode} ${error.message}\n$hint';
    }
    if (error is SocketException) {
      return 'Cannot reach ${config.remoteUrl}.\n'
          'Check that the peer file server is running and reachable.';
    }
    if (error is SyncDivergenceException) {
      return 'Sync finished but the two sides diverged: $error';
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
    final symbol = switch (action.kind) {
      SyncActionKind.createRight => '+>',
      SyncActionKind.updateRight => '=>',
      SyncActionKind.deleteRight => '->',
      SyncActionKind.createLeft => '<+',
      SyncActionKind.updateLeft => '<=',
      SyncActionKind.deleteLeft => '<-',
    };
    final verb = switch (action.kind) {
      SyncActionKind.createRight => 'upload',
      SyncActionKind.updateRight => 'upload',
      SyncActionKind.deleteRight => 'delete remote',
      SyncActionKind.createLeft => 'download',
      SyncActionKind.updateLeft => 'download',
      SyncActionKind.deleteLeft => 'delete local',
    };
    return '$symbol $verb  ${action.path}';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _hashCache?.flush();
    super.dispose();
  }
}
