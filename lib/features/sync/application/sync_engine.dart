/// Orchestrates scan -> plan -> apply -> commit for a sync pair.
library;

import 'package:path/path.dart' as p;

import '../data/snapshot_store.dart';
import '../domain/ignore_rules.dart';
import '../domain/manifest.dart';
import '../domain/sync_plan.dart';
import 'plan_applier.dart';
import 'sync_journal.dart';
import 'sync_source.dart';

final class SyncPreview {
  const SyncPreview({
    required this.baseA,
    required this.baseB,
    required this.a,
    required this.b,
    required this.plan,
  });

  /// A's snapshot, i.e. what A looked like at the end of the last sync.
  final Manifest baseA;

  /// B's snapshot, i.e. what B looked like at the end of the last sync.
  final Manifest baseB;

  final Manifest a;
  final Manifest b;
  final SyncPlan plan;
}

final class SyncReport {
  const SyncReport({
    required this.preview,
    required this.plan,
    required this.dryRun,
    this.applyReport,
    this.journalPath,
    this.conflictBackupRoot,
  });

  final SyncPreview preview;

  /// The plan that was actually executed. It can be a subtree or a one-way
  /// variant of [preview]'s full plan.
  final SyncPlan plan;
  final bool dryRun;
  final ApplyReport? applyReport;
  final String? journalPath;
  final String? conflictBackupRoot;

  bool get hasConflicts => plan.conflicts.isNotEmpty;

  int get conflictCount => plan.conflicts.length;
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

/// The direction in which a one-way sync copies files.
enum SyncDirection {
  /// Copy only from left to right.
  push,

  /// Copy only from right to left.
  pull,

  /// Two-way sync with conflict detection.
  both,
}

enum ScanPhase { local, remote }

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
  }) : _stateDir = p.normalize(p.absolute(stateDir));

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

  /// Per-side snapshots, stored inside each synced folder so any device that
  /// can reach the folder can reuse them.
  late final SnapshotStore _snapshotA = SnapshotStore(a.store);
  late final SnapshotStore _snapshotB = SnapshotStore(b.store);

  /// Releases network resources held by the sources.
  Future<void> dispose() async {
    await a.close();
    await b.close();
  }

  /// Scans both sides and builds a plan without touching the disk.
  ///
  /// When [subPath] is set, only that node's subtree is scanned and compared.
  Future<SyncPreview> preview({
    String? subPath,
    void Function(ScanPhase phase, int scanned)? onProgress,
  }) async {
    final scope = subPath == null || subPath.isEmpty ? null : subPath;
    final snapshots = await _loadSnapshots();
    final aManifest = await a.scan(
      subPath: scope,
      onProgress: (scanned) => onProgress?.call(ScanPhase.local, scanned),
    );
    final bManifest = await b.scan(
      subPath: scope,
      onProgress: (scanned) => onProgress?.call(ScanPhase.remote, scanned),
    );
    final baseA = _scopeSnapshot(snapshots.a, scope);
    final baseB = _scopeSnapshot(snapshots.b, scope);
    final plan = SyncPlanner.plan(
      base: baseA,
      baseB: baseB,
      a: aManifest,
      b: bManifest,
    );
    return SyncPreview(
      baseA: baseA,
      baseB: baseB,
      a: aManifest,
      b: bManifest,
      plan: plan,
    );
  }

  /// Applies the plan and writes a snapshot into each synced folder.
  ///
  /// Conflicting paths are left untouched on both sides and their old snapshot
  /// entries are preserved, so they keep showing up until resolved.
  ///
  /// [subPath] restricts the run to one node's subtree (a folder or a file).
  /// [direction] turns the run into a one-way copy, ignoring conflicts.
  Future<SyncReport> sync({
    bool dryRun = false,
    SyncDirection direction = SyncDirection.both,
    String? subPath,
    ActionCallback? onAction,
  }) async {
    final preview = await this.preview();
    if (dryRun) {
      return SyncReport(
        preview: preview,
        plan: _planFor(preview, direction: direction, subPath: subPath),
        dryRun: true,
      );
    }
    return execute(
      preview,
      direction: direction,
      subPath: subPath,
      onAction: onAction,
    );
  }

  /// Executes a previously computed preview without scanning again.
  Future<SyncReport> execute(
    SyncPreview preview, {
    SyncDirection direction = SyncDirection.both,
    String? subPath,
    ActionCallback? onAction,
  }) async {
    final plan = _planFor(preview, direction: direction, subPath: subPath);
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
        plan,
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
        for (final conflict in plan.conflicts) conflict.path,
      };
      _verifyConvergence(aAfter, bAfter, conflictPaths, subPath: subPath);

      final committedAt = DateTime.now();
      await _saveSnapshots(
        aAfter: aAfter,
        bAfter: bAfter,
        preview: preview,
        conflicts: plan.conflicts,
        scope: subPath,
        committedAt: committedAt,
      );
      journal?.record(
        'commit',
        data: {
          'actions': plan.actions.length,
          'conflicts': plan.conflicts.length,
          'scope': ?subPath,
          if (direction != SyncDirection.both) 'direction': direction.name,
        },
      );

      return SyncReport(
        preview: preview,
        plan: plan,
        dryRun: false,
        applyReport: applyReport,
        journalPath: journal?.path,
        conflictBackupRoot: plan.conflicts.isEmpty ? null : conflictRoot,
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

    final unresolved = preview.plan.conflicts
        .where((conflict) => remaining.contains(conflict.path))
        .toList();
    await _saveSnapshots(
      aAfter: aAfter,
      bAfter: bAfter,
      preview: preview,
      conflicts: unresolved,
      scope: null,
      committedAt: DateTime.now(),
    );

    return ConflictResolutionReport(
      resolved: resolvedPaths.length,
      remaining: remaining.length,
    );
  }

  Future<({Manifest a, Manifest b})> _loadSnapshots() async {
    final snapshotA = await _snapshotA.load();
    final snapshotB = await _snapshotB.load();
    return (
      a: snapshotA ?? Manifest.empty(root: a.id),
      b: snapshotB ?? Manifest.empty(root: b.id),
    );
  }

  /// Writes each side's snapshot after a successful sync.
  ///
  /// Unlike a shared base, each snapshot is expressed in that device's own
  /// manifest terms (hashes, mtimes and line endings as that device sees
  /// them). Unresolved conflicts keep their old snapshot entries so they keep
  /// showing up until resolved.
  Future<void> _saveSnapshots({
    required Manifest aAfter,
    required Manifest bAfter,
    required SyncPreview preview,
    required List<SyncConflict> conflicts,
    required String? scope,
    required DateTime committedAt,
  }) async {
    await _snapshotA.save(
      _nextSnapshot(
        after: aAfter,
        previous: preview.baseA,
        conflicts: conflicts,
        scope: scope,
      ),
      committedAt: committedAt,
    );
    await _snapshotB.save(
      _nextSnapshot(
        after: bAfter,
        previous: preview.baseB,
        conflicts: conflicts,
        scope: scope,
      ),
      committedAt: committedAt,
    );
  }

  /// Builds the next snapshot for one side.
  ///
  /// When [scope] is set only that subtree is replaced; entries outside it are
  /// kept from the previous snapshot, because a partial sync must not mark
  /// unrelated local changes as already synced.
  Manifest _nextSnapshot({
    required Manifest after,
    required Manifest previous,
    required List<SyncConflict> conflicts,
    required String? scope,
  }) {
    final entries = Map<String, ManifestEntry>.of(previous.entries);
    entries.removeWhere((path, _) => _inScope(path, scope));
    for (final entry in after.entries.entries) {
      if (_inScope(entry.key, scope)) {
        entries[entry.key] = entry.value;
      }
    }
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
    Set<String> conflictPaths, {
    String? subPath,
  }) {
    final paths = <String>{...aAfter.entries.keys, ...bAfter.entries.keys}
      ..removeWhere(conflictPaths.contains)
      ..removeWhere((path) => !_inScope(path, subPath));

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

  /// Builds the plan for a run: scoped two-way, or one-way.
  static SyncPlan _planFor(
    SyncPreview preview, {
    required SyncDirection direction,
    required String? subPath,
  }) {
    return switch (direction) {
      SyncDirection.both => _scopePlan(preview.plan, subPath),
      SyncDirection.push => _directionalPlan(
        preview,
        toRight: true,
        subPath: subPath,
      ),
      SyncDirection.pull => _directionalPlan(
        preview,
        toRight: false,
        subPath: subPath,
      ),
    };
  }

  static SyncPlan _scopePlan(SyncPlan plan, String? subPath) {
    if (subPath == null || subPath.isEmpty) return plan;
    return SyncPlan(
      actions: [
        for (final action in plan.actions)
          if (_inScope(action.path, subPath)) action,
      ],
      conflicts: [
        for (final conflict in plan.conflicts)
          if (_inScope(conflict.path, subPath)) conflict,
      ],
    );
  }

  /// One-way copy: the source side always wins, conflicts are not reported.
  static SyncPlan _directionalPlan(
    SyncPreview preview, {
    required bool toRight,
    required String? subPath,
  }) {
    final paths = <String>{
      ...preview.a.entries.keys,
      ...preview.b.entries.keys,
    }.toList()..sort();

    final actions = <SyncAction>[];
    for (final path in paths) {
      if (!_inScope(path, subPath)) continue;
      final ae = preview.a.entries[path];
      final be = preview.b.entries[path];
      if (ae == null && be == null) continue;
      if (ae != null && be != null && ae.sameContent(be)) continue;

      if (toRight) {
        if (ae == null) {
          actions.add(
            SyncAction(
              kind: SyncActionKind.deleteRight,
              path: path,
              reason: ActionReason.deleted,
              entry: be,
            ),
          );
        } else {
          actions.add(
            SyncAction(
              kind: be == null
                  ? SyncActionKind.createRight
                  : SyncActionKind.updateRight,
              path: path,
              reason: be == null ? ActionReason.created : ActionReason.updated,
              entry: ae,
            ),
          );
        }
      } else {
        if (be == null) {
          actions.add(
            SyncAction(
              kind: SyncActionKind.deleteLeft,
              path: path,
              reason: ActionReason.deleted,
              entry: ae,
            ),
          );
        } else {
          actions.add(
            SyncAction(
              kind: ae == null
                  ? SyncActionKind.createLeft
                  : SyncActionKind.updateLeft,
              path: path,
              reason: ae == null ? ActionReason.created : ActionReason.updated,
              entry: be,
            ),
          );
        }
      }
    }
    return SyncPlan(actions: actions, conflicts: const []);
  }

  /// True when [path] is [scope] itself, or lives below it.
  static bool _inScope(String path, String? scope) {
    if (scope == null || scope.isEmpty) return true;
    return path == scope || path.startsWith('$scope/');
  }

  static Manifest _scopeSnapshot(Manifest manifest, String? scope) {
    if (scope == null) return manifest;
    return Manifest(
      root: manifest.root,
      scannedAt: manifest.scannedAt,
      entries: {
        for (final entry in manifest.entries.entries)
          if (_inScope(entry.key, scope)) entry.key: entry.value,
      },
    );
  }

  static String _timestamp() {
    return DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp('[:.]'),
      '-',
    );
  }
}
