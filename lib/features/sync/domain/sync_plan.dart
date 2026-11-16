/// Pure three-way planning for two manifests and a common base.
///
/// The planner never touches the disk. Both local-to-local sync and future
/// remote sync share the same decisions; only the applier changes.
library;

import 'manifest.dart';

enum SyncActionKind {
  createRight,
  updateRight,
  deleteRight,
  createLeft,
  updateLeft,
  deleteLeft,
}

enum ActionReason { created, updated, deleted }

enum ConflictReason { bothCreated, bothModified, modifiedVsDeleted }

final class SyncAction {
  const SyncAction({
    required this.kind,
    required this.path,
    required this.reason,
    this.entry,
  });

  final SyncActionKind kind;

  /// Relative POSIX path.
  final String path;

  final ActionReason reason;

  /// Source entry for create/update, or the removed entry for delete.
  final ManifestEntry? entry;

  bool get targetsRight => switch (kind) {
    SyncActionKind.createRight ||
    SyncActionKind.updateRight ||
    SyncActionKind.deleteRight => true,
    _ => false,
  };

  bool get isDelete => switch (kind) {
    SyncActionKind.deleteRight || SyncActionKind.deleteLeft => true,
    _ => false,
  };

  bool get isDirectory => entry?.isDirectory ?? false;

  @override
  String toString() => 'SyncAction(${kind.name}, $path, ${reason.name})';
}

final class SyncConflict {
  const SyncConflict({
    required this.path,
    required this.reason,
    this.aEntry,
    this.bEntry,
    this.baseEntry,
  });

  final String path;
  final ConflictReason reason;
  final ManifestEntry? aEntry;
  final ManifestEntry? bEntry;
  final ManifestEntry? baseEntry;

  bool get isDirectory => (aEntry ?? bEntry)?.isDirectory ?? false;

  @override
  String toString() => 'SyncConflict($path, ${reason.name})';
}

final class SyncPlan {
  const SyncPlan({required this.actions, required this.conflicts});

  static const empty = SyncPlan(actions: [], conflicts: []);

  final List<SyncAction> actions;
  final List<SyncConflict> conflicts;

  bool get isEmpty => actions.isEmpty && conflicts.isEmpty;

  int get createCount => actions
      .where(
        (action) =>
            action.kind == SyncActionKind.createLeft ||
            action.kind == SyncActionKind.createRight,
      )
      .length;

  int get updateCount => actions
      .where(
        (action) =>
            action.kind == SyncActionKind.updateLeft ||
            action.kind == SyncActionKind.updateRight,
      )
      .length;

  int get deleteCount => actions.where((action) => action.isDelete).length;

  @override
  String toString() {
    return 'SyncPlan(actions: ${actions.length}, conflicts: '
        '${conflicts.length})';
  }
}

final class SyncPlanner {
  const SyncPlanner._();

  /// Plans the next sync.
  ///
  /// [base] is A's snapshot and [baseB] is B's snapshot. A device that has
  /// never synced this folder has an empty snapshot; a device that already
  /// synced keeps its own copy, so change detection does not depend on which
  /// machine planned the previous run. When [baseB] is omitted, [base] is used
  /// for both sides.
  static SyncPlan plan({
    required Manifest base,
    Manifest? baseB,
    required Manifest a,
    required Manifest b,
  }) {
    final baseRight = baseB ?? base;
    final paths = <String>{
      ...base.entries.keys,
      ...baseRight.entries.keys,
      ...a.entries.keys,
      ...b.entries.keys,
    }.toList()..sort();

    final actions = <SyncAction>[];
    final conflicts = <SyncConflict>[];

    for (final path in paths) {
      final ae = a.entries[path];
      final be = b.entries[path];
      final keA = base.entries[path];
      final keB = baseRight.entries[path];
      final ke = keA ?? keB;

      if (ae == null && be == null) {
        // Deleted on both sides.
        continue;
      }

      if (ae != null && be != null) {
        if (ae.sameContent(be)) {
          // Already converged. This includes "only mtime differs" when hashes
          // are available.
          continue;
        }

        final aChanged = !ae.sameContent(keA ?? ke);
        final bChanged = !be.sameContent(keB ?? ke);

        if (aChanged && bChanged) {
          conflicts.add(
            SyncConflict(
              path: path,
              reason: ke == null
                  ? ConflictReason.bothCreated
                  : ConflictReason.bothModified,
              aEntry: ae,
              bEntry: be,
              baseEntry: ke,
            ),
          );
        } else if (aChanged) {
          actions.add(
            SyncAction(
              kind: SyncActionKind.updateRight,
              path: path,
              reason: ActionReason.updated,
              entry: ae,
            ),
          );
        } else if (bChanged) {
          actions.add(
            SyncAction(
              kind: SyncActionKind.updateLeft,
              path: path,
              reason: ActionReason.updated,
              entry: be,
            ),
          );
        } else {
          // Both sides claim to be unchanged from their own snapshot yet
          // differ. This should not happen for consistent snapshots; report
          // instead of guessing.
          conflicts.add(
            SyncConflict(
              path: path,
              reason: ConflictReason.bothModified,
              aEntry: ae,
              bEntry: be,
              baseEntry: ke,
            ),
          );
        }
        continue;
      }

      if (ae != null) {
        // B is missing.
        if (ke == null) {
          actions.add(
            SyncAction(
              kind: SyncActionKind.createRight,
              path: path,
              reason: ActionReason.created,
              entry: ae,
            ),
          );
        } else if (ae.sameContent(keA ?? ke)) {
          actions.add(
            SyncAction(
              kind: SyncActionKind.deleteLeft,
              path: path,
              reason: ActionReason.deleted,
              entry: ke,
            ),
          );
        } else {
          conflicts.add(
            SyncConflict(
              path: path,
              reason: ConflictReason.modifiedVsDeleted,
              aEntry: ae,
              baseEntry: ke,
            ),
          );
        }
        continue;
      }

      // A is missing, B exists.
      final bEntry = be!;
      if (ke == null) {
        actions.add(
          SyncAction(
            kind: SyncActionKind.createLeft,
            path: path,
            reason: ActionReason.created,
            entry: bEntry,
          ),
        );
      } else if (bEntry.sameContent(keB ?? ke)) {
        actions.add(
          SyncAction(
            kind: SyncActionKind.deleteRight,
            path: path,
            reason: ActionReason.deleted,
            entry: ke,
          ),
        );
      } else {
        conflicts.add(
          SyncConflict(
            path: path,
            reason: ConflictReason.modifiedVsDeleted,
            bEntry: bEntry,
            baseEntry: ke,
          ),
        );
      }
    }

    return SyncPlan(actions: actions, conflicts: conflicts);
  }
}
