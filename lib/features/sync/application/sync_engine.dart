/// Orchestrates scan -> plan -> apply -> commit for a sync pair.
library;

import 'package:path/path.dart' as p;

import '../data/file_store.dart';
import '../data/local_scanner.dart';
import '../data/sync_state_store.dart';
import '../domain/ignore_rules.dart';
import '../domain/manifest.dart';
import '../domain/sync_plan.dart';
import 'plan_applier.dart';
import 'sync_journal.dart';

final class SyncPreview {
  const SyncPreview({
    required this.base,
    required this.a,
    required this.b,
    required this.plan,
  });

  final Manifest base;
  final Manifest a;
  final Manifest b;
  final SyncPlan plan;
}

final class SyncReport {
  const SyncReport({
    required this.preview,
    required this.dryRun,
    this.applyReport,
    this.journalPath,
    this.conflictBackupRoot,
  });

  final SyncPreview preview;
  final bool dryRun;
  final ApplyReport? applyReport;
  final String? journalPath;
  final String? conflictBackupRoot;

  bool get hasConflicts => preview.plan.conflicts.isNotEmpty;

  int get conflictCount => preview.plan.conflicts.length;
}

final class SyncDivergenceException implements Exception {
  SyncDivergenceException(this.paths);

  final List<String> paths;

  @override
  String toString() {
    final preview = paths.take(10).join(', ');
    final suffix = paths.length > 10 ? '...' : '';
    return 'SyncDivergenceException(${paths.length} paths): '
        '$preview$suffix';
  }
}

final class SyncEngine {
  SyncEngine({
    required String rootA,
    required String rootB,
    required String stateDir,
    IgnoreRules? ignores,
    bool computeHashes = true,
  }) : rootA = p.normalize(p.absolute(rootA)),
       rootB = p.normalize(p.absolute(rootB)),
       _stateDir = p.normalize(p.absolute(stateDir)) {
    _a = LocalFileStore(this.rootA);
    _b = LocalFileStore(this.rootB);
    _scanner = LocalScanner(ignores: ignores, computeHashes: computeHashes);
    _state = SyncStateStore(p.join(_stateDir, 'pair_state.json'));
  }

  final String rootA;
  final String rootB;
  final String _stateDir;

  late final FileStore _a;
  late final FileStore _b;
  late final LocalScanner _scanner;
  late final SyncStateStore _state;

  /// Scans both sides and builds a plan without touching the disk.
  Future<SyncPreview> preview() async {
    final state = await _loadState();
    final a = await _scanner.scan(rootA);
    final b = await _scanner.scan(rootB);
    final plan = SyncPlanner.plan(base: state.base, a: a, b: b);
    return SyncPreview(base: state.base, a: a, b: b, plan: plan);
  }

  /// Applies the plan and commits a new shared base.
  ///
  /// Conflicting paths are left untouched on both sides and their old base
  /// entries are preserved, so they keep showing up until resolved.
  Future<SyncReport> sync({bool dryRun = false}) async {
    final preview = await this.preview();
    if (dryRun) {
      return SyncReport(preview: preview, dryRun: true);
    }

    SyncJournal? journal;
    try {
      journal = await SyncJournal.create(p.join(_stateDir, 'journal'));
    } catch (_) {
      // The journal is diagnostic; never block a sync on it.
      journal = null;
    }

    final conflictRoot = p.join(_stateDir, 'conflicts', _timestamp());
    final applier = PlanApplier(a: _a, b: _b, conflictRoot: conflictRoot);

    try {
      final applyReport = await applier.apply(
        preview.plan,
        onAction: (action) {
          journal?.record(
            'action',
            path: action.path,
            data: {'kind': action.kind.name},
          );
        },
      );

      final aAfter = await _scanner.scan(rootA);
      final bAfter = await _scanner.scan(rootB);
      final conflictPaths = {
        for (final conflict in preview.plan.conflicts) conflict.path,
      };
      _verifyConvergence(aAfter, bAfter, conflictPaths);

      final nextBase = _nextBase(
        after: aAfter,
        previous: preview.base,
        conflicts: preview.plan.conflicts,
      );
      await _state.save(
        SyncState(
          rootA: rootA,
          rootB: rootB,
          base: nextBase,
          committedAt: DateTime.now(),
        ),
      );
      journal?.record(
        'commit',
        data: {
          'actions': preview.plan.actions.length,
          'conflicts': preview.plan.conflicts.length,
        },
      );

      return SyncReport(
        preview: preview,
        dryRun: false,
        applyReport: applyReport,
        journalPath: journal?.path,
        conflictBackupRoot: preview.plan.conflicts.isEmpty
            ? null
            : conflictRoot,
      );
    } catch (error) {
      journal?.record('error', data: {'message': error.toString()});
      rethrow;
    } finally {
      try {
        await journal?.close();
      } catch (_) {
        // Ignore journal close failures.
      }
    }
  }

  Future<SyncState> _loadState() async {
    final state = await _state.load();
    if (state != null &&
        p.equals(state.rootA, rootA) &&
        p.equals(state.rootB, rootB)) {
      return state;
    }
    return SyncState(
      rootA: rootA,
      rootB: rootB,
      base: Manifest.empty(root: rootA),
    );
  }

  Manifest _nextBase({
    required Manifest after,
    required Manifest previous,
    required List<SyncConflict> conflicts,
  }) {
    final entries = Map<String, ManifestEntry>.of(after.entries);
    for (final conflict in conflicts) {
      final old = previous.entries[conflict.path];
      if (old == null) {
        entries.remove(conflict.path);
      } else {
        entries[conflict.path] = old;
      }
    }
    return Manifest(
      root: after.root,
      scannedAt: DateTime.now(),
      entries: entries,
    );
  }

  void _verifyConvergence(
    Manifest aAfter,
    Manifest bAfter,
    Set<String> conflictPaths,
  ) {
    final paths = <String>{...aAfter.entries.keys, ...bAfter.entries.keys}
      ..removeWhere(conflictPaths.contains);

    final diverged = <String>[];
    for (final path in paths) {
      final a = aAfter.entries[path];
      final b = bAfter.entries[path];
      if (a == null || b == null || !a.sameContent(b)) {
        diverged.add(path);
      }
    }
    if (diverged.isNotEmpty) {
      throw SyncDivergenceException(diverged..sort());
    }
  }

  static String _timestamp() {
    return DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp('[:.]'),
      '-',
    );
  }
}
