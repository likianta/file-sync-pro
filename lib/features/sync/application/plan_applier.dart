/// Applies a [SyncPlan] to two [FileStore]s.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../transport/http_transport.dart';
import '../data/file_store.dart';
import '../domain/manifest.dart';
import '../domain/sync_plan.dart';

final class ApplyReport {
  const ApplyReport({
    this.created = 0,
    this.updated = 0,
    this.deleted = 0,
    this.removedDirectories = 0,
    this.backedUpConflicts = 0,
  });

  final int created;
  final int updated;
  final int deleted;
  final int removedDirectories;
  final int backedUpConflicts;

  int get total =>
      created + updated + deleted + removedDirectories + backedUpConflicts;
}

typedef ActionCallback = void Function(SyncAction action);

final class PlanApplier {
  PlanApplier({required this.a, required this.b, required this.conflictRoot});

  final FileStore a;
  final FileStore b;

  /// Directory where conflict copies are written. Usually under the app state
  /// directory, never inside the synced roots.
  final String conflictRoot;

  Future<ApplyReport> apply(SyncPlan plan, {ActionCallback? onAction}) async {
    var created = 0;
    var updated = 0;
    var deleted = 0;
    var removedDirectories = 0;
    var backedUp = 0;

    final actions = plan.actions;

    final directoryCreates =
        actions
            .where(
              (action) =>
                  !action.isDelete &&
                  action.isDirectory &&
                  action.entry != null,
            )
            .toList()
          ..sort((x, y) => _depth(x.path).compareTo(_depth(y.path)));
    for (final action in directoryCreates) {
      final target = action.targetsRight ? b : a;
      await target.ensureDirectory(action.path);
      onAction?.call(action);
    }

    final fileWrites =
        actions
            .where(
              (action) =>
                  !action.isDelete &&
                  !action.isDirectory &&
                  action.entry != null,
            )
            .toList()
          ..sort((x, y) => x.path.compareTo(y.path));
    for (final action in fileWrites) {
      final sources = action.targetsRight ? (from: a, to: b) : (from: b, to: a);
      await _copyWithRetry(
        sources.from,
        sources.to,
        action.path,
        action.entry!,
      );
      if (action.kind == SyncActionKind.createLeft ||
          action.kind == SyncActionKind.createRight) {
        created++;
      } else {
        updated++;
      }
      onAction?.call(action);
    }

    final fileDeletes =
        actions
            .where(
              (action) =>
                  action.isDelete &&
                  !action.isDirectory &&
                  action.entry != null,
            )
            .toList()
          ..sort((x, y) => x.path.compareTo(y.path));
    for (final action in fileDeletes) {
      final target = action.targetsRight ? b : a;
      await target.deleteFile(action.path);
      deleted++;
      onAction?.call(action);
    }

    final directoryDeletes =
        actions
            .where(
              (action) =>
                  action.isDelete && action.isDirectory && action.entry != null,
            )
            .toList()
          ..sort((x, y) => _depth(y.path).compareTo(_depth(x.path)));
    for (final action in directoryDeletes) {
      final target = action.targetsRight ? b : a;
      if (await target.deleteDirectoryIfEmpty(action.path)) {
        removedDirectories++;
      }
      onAction?.call(action);
    }

    if (plan.conflicts.isNotEmpty) {
      backedUp = await _backupConflicts(plan.conflicts);
    }

    return ApplyReport(
      created: created,
      updated: updated,
      deleted: deleted,
      removedDirectories: removedDirectories,
      backedUpConflicts: backedUp,
    );
  }

  Future<void> _copyWithRetry(
    FileStore from,
    FileStore to,
    String relPath,
    ManifestEntry entry,
  ) async {
    const maxAttempts = 3;
    for (var attempt = 1; ; attempt++) {
      try {
        await _copy(from, to, relPath, entry);
        return;
      } catch (error) {
        if (attempt >= maxAttempts || !_isRetryable(error)) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
      }
    }
  }

  static bool _isRetryable(Object error) {
    if (error is SocketException ||
        error is TimeoutException ||
        error is HttpException) {
      return true;
    }
    if (error is RemoteException) {
      return error.statusCode >= 500 ||
          error.statusCode == 408 ||
          error.statusCode == 429;
    }
    return false;
  }

  Future<void> _copy(
    FileStore from,
    FileStore to,
    String relPath,
    ManifestEntry entry,
  ) async {
    final parent = p.posix.dirname(relPath);
    if (parent != '.' && parent.isNotEmpty) {
      await to.ensureDirectory(parent);
    }

    await to.writeAtomically(
      relPath,
      from.openRead(relPath),
      modified: DateTime.fromMillisecondsSinceEpoch(entry.mtimeMs),
    );

    final info = await to.stat(relPath);
    if (info.size != entry.size) {
      throw StateError(
        'Size mismatch after copying $relPath: '
        'expected ${entry.size}, got ${info.size}',
      );
    }
  }

  Future<int> _backupConflicts(List<SyncConflict> conflicts) async {
    var count = 0;
    for (final conflict in conflicts) {
      final aEntry = conflict.aEntry;
      if (aEntry != null && aEntry.isFile) {
        await _backupFile(a, conflict.path, p.join(conflictRoot, 'a'));
        count++;
      }
      final bEntry = conflict.bEntry;
      if (bEntry != null && bEntry.isFile) {
        await _backupFile(b, conflict.path, p.join(conflictRoot, 'b'));
        count++;
      }
    }
    return count;
  }

  Future<void> _backupFile(
    FileStore store,
    String relPath,
    String targetRoot,
  ) async {
    final targetPath = p.joinAll([targetRoot, ...relPath.split('/')]);
    final parent = Directory(p.dirname(targetPath));
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    final sink = File(targetPath).openWrite();
    try {
      await sink.addStream(store.openRead(relPath));
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  static int _depth(String path) => path.split('/').length;
}
