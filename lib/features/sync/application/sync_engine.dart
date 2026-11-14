/// Orchestrates scan -> plan -> apply -> commit for a sync pair.
library;

import 'package:path/path.dart' as p;

import '../data/sync_state_store.dart';
import '../domain/ignore_rules.dart';
import '../domain/manifest.dart';
import '../domain/sync_plan.dart';
import 'plan_applier.dart';
import 'sync_journal.dart';
import 'sync_source.dart';

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

enum ConflictSide { left, right }

final class ConflictResolutionReport {
  const ConflictResolutionReport({
    required this.resolved,
    required this.remaining,
  });

  final int resolved;
  final int remaining;
}

final class SyncEngine {
  SyncEngine({
    required this.a,
    required this.b,
    required String stateDir,
    this.onAction,
  }) : _stateDir = p.normalize(p.absolute(stateDir)) {
    _state = SyncStateStore(p.join(_stateDir, 'pair_state.json'));
  }

  /// Convenience constructor for two local folders (used by tests and by
  /// "sync this Mac's folder to another local folder" scenarios).
  factory SyncEngine.local({
    required String rootA,
    required String rootB,
    required String stateDir,
    IgnoreRules? ignores,
    bool computeHashes = true,
    ActionCallback? onAction,
  }) {
    return SyncEngine(
      a: LocalSyncSource(rootA, ignores: ignores, computeHashes: computeHashes),
      b: LocalSyncSource(rootB, ignores: ignores, computeHashes: computeHashes),
      stateDir: stateDir,
      onAction: onAction,
    );
  }

  final SyncSource a;
  final SyncSource b;
  final ActionCallback? onAction;
  final String _stateDir;

  late final SyncStateStore _state;

  /// Releases network resources held by the sources.
  Future<void> dispose() async {
    await a.close();
    await b.close();
  }

  /// Scans both sides and builds a plan without touching the disk.
  Future<SyncPreview> preview() async {
    final state = await _loadState();
    final aManifest = await a.scan();
    final bManifest = await b.scan();
    final plan = SyncPlanner.plan(base: state.base, a: aManifest, b: bManifest);
    return SyncPreview(
      base: state.base,
      a: aManifest,
      b: bManifest,
      plan: plan,
    );
  }

  /// Applies the plan and commits a new shared base.
  ///
  /// Conflicting paths are left untouched on both sides and their old base
  /// entries are preserved, so they keep showing up until resolved.
  Future<SyncReport> sync({
    bool dryRun = false,
    ActionCallback? onAction,
  }) async {
    final preview = await this.preview();
    if (dryRun) {
      return SyncReport(preview: preview, dryRun: true);
    }
    return execute(preview, onAction: onAction);
  }

  /// Executes a previously computed preview without scanning again.
  Future<SyncReport> execute(
    SyncPreview preview, {
    ActionCallback? onAction,
  }) async {
    final progress = onAction ?? this.onAction;

    SyncJournal? journal;
    try {
      journal = await SyncJournal.create(p.join(_stateDir, 'journal'));
    } catch (_) {
      // The journal is diagnostic; never block a sync on it.
      journal = null;
    }

    final conflictRoot = p.join(_stateDir, 'conflicts', _timestamp());
    final applier = PlanApplier(
      a: a.store,
      b: b.store,
      conflictRoot: conflictRoot,
    );

    try {
      final applyReport = await applier.apply(
        preview.plan,
        onAction: (action) {
          progress?.call(action);
          journal?.record(
            'action',
            path: action.path,
            data: {'kind': action.kind.name},
          );
        },
      );

      final aAfter = await a.scan();
      final bAfter = await b.scan();
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
          rootA: a.id,
          rootB: b.id,
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

  /// Resolves selected conflicts by copying one side over the other.
  ///
  /// The unselected side's content is already preserved in the conflict
  /// backup folder created by the previous sync.
  Future<ConflictResolutionReport> resolveConflicts(
    SyncPreview preview,
    Map<String, ConflictSide> choices,
  ) async {
    final conflicts = {
      for (final conflict in preview.plan.conflicts) conflict.path: conflict,
    };
    final resolvedPaths = <String>{};
    final actions = <SyncAction>[];

    for (final choice in choices.entries) {
      final path = choice.key;
      if (!conflicts.containsKey(path)) continue;

      final aEntry = preview.a.entries[path];
      final bEntry = preview.b.entries[path];

      switch (choice.value) {
        case ConflictSide.left:
          if (aEntry == null) {
            if (bEntry != null) {
              actions.add(
                SyncAction(
                  kind: SyncActionKind.deleteRight,
                  path: path,
                  reason: ActionReason.deleted,
                  entry: bEntry,
                ),
              );
            }
          } else {
            actions.add(
              SyncAction(
                kind: SyncActionKind.updateRight,
                path: path,
                reason: ActionReason.updated,
                entry: aEntry,
              ),
            );
          }
        case ConflictSide.right:
          if (bEntry == null) {
            if (aEntry != null) {
              actions.add(
                SyncAction(
                  kind: SyncActionKind.deleteLeft,
                  path: path,
                  reason: ActionReason.deleted,
                  entry: aEntry,
                ),
              );
            }
          } else {
            actions.add(
              SyncAction(
                kind: SyncActionKind.updateLeft,
                path: path,
                reason: ActionReason.updated,
                entry: bEntry,
              ),
            );
          }
      }
      resolvedPaths.add(path);
    }

    if (actions.isNotEmpty) {
      final applier = PlanApplier(
        a: a.store,
        b: b.store,
        conflictRoot: p.join(_stateDir, 'conflicts', _timestamp()),
      );
      await applier.apply(SyncPlan(actions: actions, conflicts: const []));
    }

    final aAfter = await a.scan();
    final bAfter = await b.scan();
    final remaining = conflicts.keys
        .where((path) => !resolvedPaths.contains(path))
        .toSet();
    _verifyConvergence(aAfter, bAfter, remaining);

    final nextBase = _nextBase(
      after: aAfter,
      previous: preview.base,
      conflicts: preview.plan.conflicts
          .where((conflict) => remaining.contains(conflict.path))
          .toList(),
    );
    await _state.save(
      SyncState(
        rootA: a.id,
        rootB: b.id,
        base: nextBase,
        committedAt: DateTime.now(),
      ),
    );

    return ConflictResolutionReport(
      resolved: resolvedPaths.length,
      remaining: remaining.length,
    );
  }

  Future<SyncState> _loadState() async {
    final state = await _state.load();
    if (state != null &&
        p.equals(state.rootA, a.id) &&
        p.equals(state.rootB, b.id)) {
      return state;
    }
    return SyncState(
      rootA: a.id,
      rootB: b.id,
      base: Manifest.empty(root: a.id),
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
      final aEntry = aAfter.entries[path];
      final bEntry = bAfter.entries[path];
      if (aEntry == null || bEntry == null || !aEntry.sameContent(bEntry)) {
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
