import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../transport/http_transport.dart';
import '../application/sync_engine.dart';
import '../application/sync_pair_config.dart';
import '../application/sync_source.dart';
import '../domain/ignore_rules.dart';
import '../domain/sync_plan.dart';

enum SyncDashboardStatus { idle, scanning, applying, error }

/// Drives one sync pair for the dashboard.
final class SyncDashboardController extends ChangeNotifier {
  SyncDashboardController({required this.config});

  final SyncPairConfig config;

  SyncDashboardStatus _status = SyncDashboardStatus.idle;
  SyncPreview? _preview;
  SyncReport? _report;
  String? _errorMessage;
  int _applied = 0;
  int _total = 0;
  String? _currentPath;
  final List<String> _log = [];
  bool _disposed = false;

  SyncDashboardStatus get status => _status;

  SyncPreview? get preview => _preview;

  SyncReport? get report => _report;

  String? get errorMessage => _errorMessage;

  int get applied => _applied;

  int get total => _total;

  String? get currentPath => _currentPath;

  List<String> get log => List.unmodifiable(_log);

  bool get busy =>
      _status == SyncDashboardStatus.scanning ||
      _status == SyncDashboardStatus.applying;

  bool get canRun => !busy;

  String get statusLabel {
    return switch (_status) {
      SyncDashboardStatus.idle => 'Ready',
      SyncDashboardStatus.scanning => 'Scanning both sides...',
      SyncDashboardStatus.applying => 'Applying $_applied / $_total...',
      SyncDashboardStatus.error => 'Error',
    };
  }

  Future<void> check() async {
    if (busy) return;

    _status = SyncDashboardStatus.scanning;
    _errorMessage = null;
    _preview = null;
    _report = null;
    _applied = 0;
    _total = 0;
    _currentPath = null;
    _log.clear();
    _appendLog('Scanning both sides...');
    _notify();

    final engine = _createEngine();
    try {
      await Directory(config.localRoot).create(recursive: true);
      final preview = await engine.preview();
      _preview = preview;
      _status = SyncDashboardStatus.idle;
      _appendLog(
        'Plan: ${preview.plan.createCount} create, '
        '${preview.plan.updateCount} update, '
        '${preview.plan.deleteCount} delete, '
        '${preview.plan.conflicts.length} conflicts.',
      );
    } catch (error) {
      _fail(error);
    } finally {
      await engine.dispose();
      _notify();
    }
  }

  Future<void> sync() async {
    if (busy) return;

    _status = SyncDashboardStatus.scanning;
    _errorMessage = null;
    _report = null;
    _applied = 0;
    _total = 0;
    _currentPath = null;
    _log.clear();
    _appendLog('Scanning both sides...');
    _notify();

    final engine = _createEngine();
    try {
      await Directory(config.localRoot).create(recursive: true);
      final preview = await engine.preview();
      _preview = preview;
      _total = preview.plan.actions.length;
      _notify();

      if (_total == 0 && preview.plan.conflicts.isEmpty) {
        _status = SyncDashboardStatus.idle;
        _appendLog('Already in sync.');
        return;
      }

      _status = SyncDashboardStatus.applying;
      _notify();

      final report = await engine.execute(
        preview,
        onAction: (action) {
          _applied++;
          _currentPath = action.path;
          _appendLog(_formatAction(action));
          _notify();
        },
      );
      _report = report;
      _status = SyncDashboardStatus.idle;

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
          'Copies: ${report.conflictBackupRoot ?? config.stateDir}.',
        );
      }
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
    _notify();
  }

  SyncEngine _createEngine() {
    final ignores = IgnoreRules.defaults(extra: config.extraIgnores);
    return SyncEngine(
      a: LocalSyncSource(config.localRoot, ignores: ignores),
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
        401 =>
          'Authentication failed. Set the same token on the server and '
              'client.',
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
          'Check that the Windows server is running and that the tunnel '
          'forwards the public port to it.';
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
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
