/// Orchestrates snapshot loading -> plan -> apply -> snapshot update.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/file_store.dart';
import '../data/snapshot_store.dart';
import '../domain/manifest.dart';
import '../domain/sync_plan.dart';
import '../domain/sync_snapshot.dart';
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
    this.applyReport,
    this.journalPath,
    this.conflictArchiveRoot,
    this.conflictArchives = const [],
    this.aSnapshot,
    this.bSnapshot,
  });

  final SyncPreview preview;

  /// The plan that was actually executed. It can be a subtree or a one-way
  /// variant of [preview]'s full plan.
  final SyncPlan plan;
  final ApplyReport? applyReport;
  final String? journalPath;

  /// Directory that contains the archived remote copies for this run.
  final String? conflictArchiveRoot;

  /// Conflicts that were resolved with "local always wins" during this run.
  final List<ConflictArchiveEntry> conflictArchives;

  /// Snapshots after the incremental update. No tree scan happens after a
  /// sync, so these are derived from the applied actions.
  final SideSnapshot? aSnapshot;
  final SideSnapshot? bSnapshot;

  bool get hasConflicts => plan.conflicts.isNotEmpty;

  int get conflictCount => plan.conflicts.length;
}

/// One conflict resolved by keeping the local file and archiving the remote
/// copy before it was overwritten or deleted.
final class ConflictArchiveEntry {
  const ConflictArchiveEntry({
    required this.path,
    required this.localExisted,
    required this.remoteExisted,
    this.localPath,
    this.archivedRemotePath,
  });

  /// Relative POSIX path inside the sync root.
  final String path;

  final bool localExisted;
  final bool remoteExisted;

  /// Absolute path to the local winner, when the left side is a local folder.
  final String? localPath;

  /// Absolute path to the downloaded remote copy, or null when the remote
  /// entry was missing or was not a file.
  final String? archivedRemotePath;
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
    this.aSnapshot,
    this.bSnapshot,
  });

  final int resolved;
  final int remaining;
  final SideSnapshot? aSnapshot;
  final SideSnapshot? bSnapshot;
}

final class SyncEngine {
  SyncEngine({
    required this.a,
    required this.b,
    required String stateDir,
    String? conflictRoot,
    this.onAction,
  }) : _stateDir = p.normalize(p.absolute(stateDir)),
       _conflictRoot = p.normalize(
         p.absolute(conflictRoot ?? p.join(stateDir, 'conflicts')),
       );

  /// Convenience constructor for two local folders (used by tests and by
  /// "sync this Mac's folder to another local folder" scenarios).
  factory SyncEngine.local({
    required String rootA,
    required String rootB,
    required String stateDir,
    String? conflictRoot,
    String? snapshotBackupDir,
    String labelA = 'a',
    String labelB = 'b',
    SnapshotIgnores defaultIgnores = SnapshotIgnores.empty,
    ActionCallback? onAction,
  }) {
    return SyncEngine(
      a: LocalSyncSource(
        rootA,
        snapshotBackupDir: snapshotBackupDir,
        snapshotLabel: labelA,
        defaultIgnores: defaultIgnores,
      ),
      b: LocalSyncSource(
        rootB,
        snapshotBackupDir: snapshotBackupDir,
        snapshotLabel: labelB,
        defaultIgnores: defaultIgnores,
      ),
      stateDir: stateDir,
      conflictRoot: conflictRoot,
      onAction: onAction,
    );
  }

  final SyncSource a;
  final SyncSource b;
  final ActionCallback? onAction;
  final String _stateDir;
  final String _conflictRoot;

  /// Releases network resources held by the sources.
  Future<void> dispose() async {
    await a.close();
    await b.close();
  }

  /// Reads both `.file_sync_shot.json` files. No folder is scanned here.
  Future<({SnapshotLoadResult a, SnapshotLoadResult b})> loadSnapshots() async {
    final results = await Future.wait([a.loadSnapshot(), b.loadSnapshot()]);
    return (a: results[0], b: results[1]);
  }

  /// Scans only one side, either the whole root or one folder subtree.
  Future<SideSnapshot> scanSide({
    required bool left,
    String? subPath,
    bool createIfMissing = false,
    SnapshotIgnores? ignores,
    void Function(int scanned)? onProgress,
  }) {
    final source = left ? a : b;
    return source.scanSnapshot(
      subPath: subPath,
      createIfMissing: createIfMissing,
      ignores: ignores,
      onProgress: onProgress,
    );
  }

  /// Refreshes one file's snapshot entry on one side.
  Future<SideSnapshot> refreshFile({required bool left, required String path}) {
    final source = left ? a : b;
    return source.refreshFile(path);
  }

  /// Scans both roots, used when the pair has no usable snapshot yet.
  ///
  /// The remote side reuses the local snapshot's ignores when it has to create
  /// a new snapshot, so both sides agree on what is scanned.
  Future<({SideSnapshot a, SideSnapshot b})> scanBoth({
    bool createIfMissing = false,
    SnapshotIgnores defaultIgnores = SnapshotIgnores.empty,
    void Function(ScanPhase phase, int scanned)? onProgress,
  }) async {
    final aSnapshot = await scanSide(
      left: true,
      createIfMissing: createIfMissing,
      ignores: defaultIgnores,
      onProgress: (scanned) => onProgress?.call(ScanPhase.local, scanned),
    );
    final bSnapshot = await scanSide(
      left: false,
      createIfMissing: createIfMissing,
      ignores: aSnapshot.ignores,
      onProgress: (scanned) => onProgress?.call(ScanPhase.remote, scanned),
    );
    return (a: aSnapshot, b: bSnapshot);
  }

  /// Plans from snapshots only. Nothing is read from the filesystem here.
  SyncPreview planFromSnapshots(
    SideSnapshot aSnapshot,
    SideSnapshot bSnapshot, {
    String? subPath,
  }) {
    final aManifest = aSnapshot.current.toManifest(root: a.id);
    final bManifest = bSnapshot.current.toManifest(root: b.id);
    final baseA = aSnapshot.base.toManifest(root: a.id);
    final baseB = bSnapshot.base.toManifest(root: b.id);
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
      plan: _scopePlan(plan, subPath),
    );
  }

  /// Applies the plan and updates both snapshots incrementally.
  ///
  /// The folders are not scanned again. File metadata comes from the write
  /// result, and directory changes come from the plan itself.
  Future<SyncReport> execute(
    SyncPreview preview, {
    required SideSnapshot aSnapshot,
    required SideSnapshot bSnapshot,
    SyncDirection direction = SyncDirection.both,
    String? subPath,
    Set<String>? subPaths,
    ActionCallback? onAction,
  }) async {
    final plan = _planFor(
      preview,
      direction: direction,
      subPath: subPath,
      subPaths: subPaths,
    );
    final progress = onAction ?? this.onAction;

    SyncJournal? journal;
    try {
      journal = await SyncJournal.create(p.join(_stateDir, 'journal'));
    } catch (_) {
      // The journal is diagnostic; never block a sync on it.
      journal = null;
    }

    final conflicts = plan.conflicts;
    final archived = await _archiveConflicts(preview, conflicts);
    final executionPlan = SyncPlan(
      actions: [...plan.actions, ..._localWinsActions(preview, conflicts)],
      conflicts: const [],
    );
    final applier = PlanApplier(
      a: a.store,
      b: b.store,
      conflictRoot: p.join(_stateDir, 'conflicts'),
    );

    try {
      final applyReport = await applier.apply(
        executionPlan,
        onAction: (action) {
          progress?.call(action);
          journal?.record(
            'action',
            path: action.path,
            data: {'kind': action.kind.name},
          );
        },
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      final aCurrent = _applyActionsToCurrent(
        aSnapshot.current,
        executionPlan,
        applyReport.written,
        targetsRight: false,
        updatedAt: now,
      );
      final bCurrent = _applyActionsToCurrent(
        bSnapshot.current,
        executionPlan,
        applyReport.written,
        targetsRight: true,
        updatedAt: now,
      );
      final aBase = _nextBase(
        previous: aSnapshot.base,
        current: aCurrent,
        conflicts: const [],
        scope: subPath,
        subPaths: subPaths,
        updatedAt: now,
      );
      final bBase = _nextBase(
        previous: bSnapshot.base,
        current: bCurrent,
        conflicts: const [],
        scope: subPath,
        subPaths: subPaths,
        updatedAt: now,
      );

      final aAfter = SideSnapshot(
        base: aBase,
        current: aCurrent,
        ignores: aSnapshot.ignores,
      );
      final bAfter = SideSnapshot(
        base: bBase,
        current: bCurrent,
        ignores: bSnapshot.ignores,
      );
      await a.saveSnapshot(aAfter);
      await b.saveSnapshot(bAfter);

      journal?.record(
        'commit',
        data: {
          'actions': executionPlan.actions.length,
          'conflicts': conflicts.length,
          'scope': ?subPath,
          if (direction != SyncDirection.both) 'direction': direction.name,
        },
      );

      return SyncReport(
        preview: preview,
        plan: plan,
        applyReport: applyReport,
        journalPath: journal?.path,
        conflictArchiveRoot: archived.root,
        conflictArchives: archived.entries,
        aSnapshot: aAfter,
        bSnapshot: bAfter,
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
    SyncPreview preview, {
    required SideSnapshot aSnapshot,
    required SideSnapshot bSnapshot,
    required Map<String, ConflictSide> choices,
  }) async {
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

    var applyReport = const ApplyReport();
    if (actions.isNotEmpty) {
      final applier = PlanApplier(
        a: a.store,
        b: b.store,
        conflictRoot: p.join(_stateDir, 'conflicts', _timestamp()),
      );
      applyReport = await applier.apply(
        SyncPlan(actions: actions, conflicts: const []),
      );
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final plan = SyncPlan(actions: actions, conflicts: const []);
    final aCurrent = _applyActionsToCurrent(
      aSnapshot.current,
      plan,
      applyReport.written,
      targetsRight: false,
      updatedAt: now,
    );
    final bCurrent = _applyActionsToCurrent(
      bSnapshot.current,
      plan,
      applyReport.written,
      targetsRight: true,
      updatedAt: now,
    );

    final aBaseEntries = _copyFolders(aSnapshot.base.entries);
    final bBaseEntries = _copyFolders(bSnapshot.base.entries);
    for (final path in resolvedPaths) {
      _copyPath(aCurrent.entries, aBaseEntries, path);
      _copyPath(bCurrent.entries, bBaseEntries, path);
    }

    final aAfter = SideSnapshot(
      base: SnapshotState.fromEntries(aBaseEntries, updatedAt: now),
      current: aCurrent,
      ignores: aSnapshot.ignores,
    );
    final bAfter = SideSnapshot(
      base: SnapshotState.fromEntries(bBaseEntries, updatedAt: now),
      current: bCurrent,
      ignores: bSnapshot.ignores,
    );
    await a.saveSnapshot(aAfter);
    await b.saveSnapshot(bAfter);

    final remaining = conflicts.keys
        .where((path) => !resolvedPaths.contains(path))
        .toSet();

    return ConflictResolutionReport(
      resolved: resolvedPaths.length,
      remaining: remaining.length,
      aSnapshot: aAfter,
      bSnapshot: bAfter,
    );
  }

  Future<({String? root, List<ConflictArchiveEntry> entries})>
  _archiveConflicts(SyncPreview preview, List<SyncConflict> conflicts) async {
    if (conflicts.isEmpty) {
      return (root: null, entries: const <ConflictArchiveEntry>[]);
    }
    final root = p.join(_conflictRoot, _archiveTimestamp());
    await Directory(root).create(recursive: true);
    final entries = <ConflictArchiveEntry>[];
    for (final conflict in conflicts) {
      final aEntry = preview.a.entries[conflict.path];
      final bEntry = preview.b.entries[conflict.path];
      String? archivedPath;
      if (bEntry != null && bEntry.isFile) {
        archivedPath = p.joinAll([root, ...conflict.path.split('/')]);
        await _copyStoreToFile(b.store, conflict.path, archivedPath);
      }
      entries.add(
        ConflictArchiveEntry(
          path: conflict.path,
          localExisted: aEntry != null,
          remoteExisted: bEntry != null,
          localPath: aEntry == null ? null : _localPathFor(conflict.path),
          archivedRemotePath: archivedPath,
        ),
      );
    }
    return (root: root, entries: entries);
  }

  String? _localPathFor(String relPath) {
    if (!p.isAbsolute(a.id)) return null;
    return p.joinAll([a.id, ...relPath.split('/')]);
  }

  static Future<void> _copyStoreToFile(
    FileStore store,
    String relPath,
    String targetPath,
  ) async {
    final target = File(targetPath);
    await target.parent.create(recursive: true);
    final temp = File(
      '$targetPath.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      final sink = temp.openWrite();
      try {
        await sink.addStream(store.openRead(relPath));
        await sink.flush();
      } finally {
        await sink.close();
      }
      await temp.rename(targetPath);
    } finally {
      if (await temp.exists()) {
        await temp.delete();
      }
    }
  }

  /// "Local always wins": turn each conflict into an action that overwrites or
  /// deletes the remote entry. The remote copy has already been archived.
  static List<SyncAction> _localWinsActions(
    SyncPreview preview,
    List<SyncConflict> conflicts,
  ) {
    final actions = <SyncAction>[];
    for (final conflict in conflicts) {
      final aEntry = preview.a.entries[conflict.path];
      final bEntry = preview.b.entries[conflict.path];
      if (aEntry == null && bEntry == null) continue;
      if (aEntry == null) {
        actions.add(
          SyncAction(
            kind: SyncActionKind.deleteRight,
            path: conflict.path,
            reason: ActionReason.deleted,
            entry: bEntry,
          ),
        );
        continue;
      }
      if (bEntry == null) {
        actions.add(
          SyncAction(
            kind: SyncActionKind.createRight,
            path: conflict.path,
            reason: ActionReason.created,
            entry: aEntry,
          ),
        );
        continue;
      }
      if (aEntry.isDirectory != bEntry.isDirectory) {
        throw StateError(
          'Type conflict is not supported yet: ${conflict.path}',
        );
      }
      if (aEntry.isDirectory) continue;
      actions.add(
        SyncAction(
          kind: SyncActionKind.updateRight,
          path: conflict.path,
          reason: ActionReason.updated,
          entry: aEntry,
        ),
      );
    }
    return actions;
  }

  String _archiveTimestamp() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  /// Builds the plan for a run: scoped two-way, or one-way.
  static SyncPlan _planFor(
    SyncPreview preview, {
    required SyncDirection direction,
    required String? subPath,
    Set<String>? subPaths,
  }) {
    return switch (direction) {
      SyncDirection.both => _scopePlan(preview.plan, subPath, subPaths),
      SyncDirection.push => _directionalPlan(
        preview,
        toRight: true,
        subPath: subPath,
        subPaths: subPaths,
      ),
      SyncDirection.pull => _directionalPlan(
        preview,
        toRight: false,
        subPath: subPath,
        subPaths: subPaths,
      ),
    };
  }

  static SyncPlan _scopePlan(
    SyncPlan plan,
    String? subPath, [
    Set<String>? subPaths,
  ]) {
    if ((subPath == null || subPath.isEmpty) &&
        (subPaths == null || subPaths.isEmpty)) {
      return plan;
    }
    return SyncPlan(
      actions: [
        for (final action in plan.actions)
          if (_inScopeOrPaths(action.path, subPath, subPaths)) action,
      ],
      conflicts: [
        for (final conflict in plan.conflicts)
          if (_inScopeOrPaths(conflict.path, subPath, subPaths)) conflict,
      ],
    );
  }

  /// One-way copy: the source side always wins, conflicts are not reported.
  static SyncPlan _directionalPlan(
    SyncPreview preview, {
    required bool toRight,
    required String? subPath,
    Set<String>? subPaths,
  }) {
    final paths = <String>{
      ...preview.a.entries.keys,
      ...preview.b.entries.keys,
    }.toList()..sort();

    final actions = <SyncAction>[];
    for (final path in paths) {
      if (!_inScopeOrPaths(path, subPath, subPaths)) continue;
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

  /// Applies executed actions to one side's `current` snapshot.
  static SnapshotState _applyActionsToCurrent(
    SnapshotState current,
    SyncPlan plan,
    Map<String, AppliedFile> written, {
    required bool targetsRight,
    required int updatedAt,
  }) {
    final entries = _copyFolders(current.entries);
    for (final action in plan.actions) {
      if (action.targetsRight != targetsRight) continue;
      if (action.isDelete) {
        if (action.isDirectory) {
          _removeFolder(entries, action.path);
        } else {
          _removeFile(entries, action.path);
        }
        continue;
      }
      if (action.isDirectory) {
        _ensureFolder(
          entries,
          action.path,
          mtimeMs: action.entry?.mtimeMs ?? updatedAt,
        );
        continue;
      }
      final applied = written[action.path];
      if (applied == null) continue;
      _putFile(
        entries,
        action.path,
        FileSnapshot(
          size: applied.size,
          mtimeMs: applied.mtimeMs,
          hash: applied.hash,
          textHash: applied.textHash,
        ),
      );
    }
    return SnapshotState.fromEntries(entries, updatedAt: updatedAt);
  }

  /// Advances `base` to the new state, keeping conflict paths at their old
  /// baseline so they keep showing up until resolved.
  static SnapshotState _nextBase({
    required SnapshotState previous,
    required SnapshotState current,
    required List<SyncConflict> conflicts,
    required String? scope,
    Set<String>? subPaths,
    required int updatedAt,
  }) {
    final entries = _copyFolders(previous.entries);
    if (subPaths != null && subPaths.isNotEmpty) {
      for (final path in subPaths) {
        _removePath(entries, path);
        _copyPath(current.entries, entries, path);
      }
    } else if (scope == null || scope.isEmpty) {
      entries
        ..clear()
        ..addAll(_copyFolders(current.entries));
    } else {
      _removePath(entries, scope);
      _copyPath(current.entries, entries, scope);
    }

    for (final conflict in conflicts) {
      if (!_inScopeOrPaths(conflict.path, scope, subPaths)) continue;
      _removePath(entries, conflict.path);
      _restorePath(entries, previous.entries, conflict.path);
    }

    return SnapshotState.fromEntries(entries, updatedAt: updatedAt);
  }

  static Map<String, FolderSnapshot> _copyFolders(
    Map<String, FolderSnapshot> source,
  ) {
    return {
      for (final entry in source.entries)
        entry.key: entry.value.copyWith(
          dirs: [...entry.value.dirs],
          files: {...entry.value.files},
        ),
    };
  }

  static void _ensureFolder(
    Map<String, FolderSnapshot> entries,
    String path, {
    int? mtimeMs,
  }) {
    if (path.isEmpty) {
      entries.putIfAbsent('.', () => FolderSnapshot(mtimeMs: mtimeMs ?? 0));
      return;
    }
    if (entries.containsKey(path)) return;

    entries[path] = FolderSnapshot(mtimeMs: mtimeMs ?? 0);
    final parent = parentScope(path);
    _ensureFolder(entries, parent);
    final parentKey = folderKey(parent);
    final parentFolder = entries[parentKey]!;
    entries[parentKey] = parentFolder.copyWith(
      dirs: {...parentFolder.dirs, baseName(path)}.toList(),
    );
  }

  static void _putFile(
    Map<String, FolderSnapshot> entries,
    String path,
    FileSnapshot file,
  ) {
    final parent = parentScope(path);
    _ensureFolder(entries, parent);
    final parentKey = folderKey(parent);
    final folder = entries[parentKey]!;
    entries[parentKey] = folder.copyWith(
      files: {...folder.files, baseName(path): file},
    );
  }

  static void _removeFile(Map<String, FolderSnapshot> entries, String path) {
    final parentKey = folderKey(parentScope(path));
    final folder = entries[parentKey];
    if (folder == null) return;
    final files = {...folder.files}..remove(baseName(path));
    entries[parentKey] = folder.copyWith(files: files);
  }

  static void _removeFolder(Map<String, FolderSnapshot> entries, String path) {
    if (path.isEmpty) return;
    entries.removeWhere(
      (candidate, _) => candidate == path || candidate.startsWith('$path/'),
    );
    final parentKey = folderKey(parentScope(path));
    final parent = entries[parentKey];
    if (parent == null) return;
    entries[parentKey] = parent.copyWith(
      dirs: parent.dirs.where((name) => name != baseName(path)).toList(),
    );
  }

  /// Removes either a file or a folder subtree at [path].
  static void _removePath(Map<String, FolderSnapshot> entries, String path) {
    if (entries.containsKey(folderKey(path))) {
      _removeFolder(entries, path);
    } else {
      _removeFile(entries, path);
    }
  }

  /// Copies [path] from [source] into [target], preserving its kind.
  static void _copyPath(
    Map<String, FolderSnapshot> source,
    Map<String, FolderSnapshot> target,
    String path,
  ) {
    final key = folderKey(path);
    final folder = source[key];
    if (folder != null) {
      _removeFolder(target, path);
      target[key] = folder.copyWith(
        dirs: [...folder.dirs],
        files: {...folder.files},
      );
      for (final entry in source.entries) {
        if (entry.key.startsWith('$key/')) {
          target[entry.key] = entry.value.copyWith(
            dirs: [...entry.value.dirs],
            files: {...entry.value.files},
          );
        }
      }
      _linkFolder(target, path);
      return;
    }

    _removeFile(target, path);
    final parent = parentScope(path);
    final parentFolder = source[folderKey(parent)];
    final file = parentFolder?.files[baseName(path)];
    if (file == null) return;
    _putFile(target, path, file);
  }

  /// Restores the old base entry for a conflict path, if it existed.
  static void _restorePath(
    Map<String, FolderSnapshot> target,
    Map<String, FolderSnapshot> oldBase,
    String path,
  ) {
    _copyPath(oldBase, target, path);
  }

  /// Adds [path] to its parent's `dirs` list when the folder exists.
  static void _linkFolder(Map<String, FolderSnapshot> entries, String path) {
    if (path.isEmpty) return;
    final parentKey = folderKey(parentScope(path));
    final parent = entries[parentKey];
    if (parent == null) return;
    entries[parentKey] = parent.copyWith(
      dirs: {...parent.dirs, baseName(path)}.toList(),
    );
  }

  /// True when [path] is [scope] itself, or lives below it.
  static bool _inScope(String path, String? scope) {
    if (scope == null || scope.isEmpty) return true;
    return path == scope || path.startsWith('$scope/');
  }

  static bool _inScopeOrPaths(
    String path,
    String? scope,
    Set<String>? subPaths,
  ) {
    if (subPaths != null && subPaths.isNotEmpty) {
      for (final candidate in subPaths) {
        if (path == candidate || path.startsWith('$candidate/')) return true;
      }
      return false;
    }
    return _inScope(path, scope);
  }

  static String _timestamp() {
    return DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp('[:.]'),
      '-',
    );
  }
}
