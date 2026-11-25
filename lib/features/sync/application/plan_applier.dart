/// Applies a [SyncPlan] to two [FileStore]s.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../transport/http_transport.dart';
import '../data/file_store.dart';
import '../domain/line_endings.dart';
import '../domain/manifest.dart';
import '../domain/sync_cancel.dart';
import '../domain/sync_plan.dart';

/// Metadata of a file after it was written to the target side.
final class AppliedFile {
  const AppliedFile({
    required this.size,
    required this.mtimeMs,
    required this.hash,
    this.textHash,
  });

  final int size;
  final int mtimeMs;
  final String hash;
  final String? textHash;
}

final class ApplyReport {
  const ApplyReport({
    this.created = 0,
    this.updated = 0,
    this.deleted = 0,
    this.removedDirectories = 0,
    this.written = const {},
  });

  final int created;
  final int updated;
  final int deleted;
  final int removedDirectories;

  /// Files written to either side, keyed by path. Used to update snapshots
  /// without scanning the tree again.
  final Map<String, AppliedFile> written;

  int get total => created + updated + deleted + removedDirectories;
}

typedef ActionCallback = void Function(SyncAction action);

final class PlanApplier {
  PlanApplier({required this.a, required this.b});

  final FileStore a;
  final FileStore b;

  /// Files at or above this size are copied on a single lane: their duration
  /// is dominated by bandwidth, so extra lanes only add interleaving.
  static const int _parallelThresholdBytes = 8 * 1024 * 1024;

  /// Maximum number of small files copied at the same time. The peer serves
  /// requests from one isolate, so more lanes mostly add memory pressure.
  static const int _parallelLanes = 4;

  Future<ApplyReport> apply(
    SyncPlan plan, {
    ActionCallback? onAction,
    SyncCancelToken? cancelToken,
  }) async {
    var created = 0;
    var updated = 0;
    var deleted = 0;
    var removedDirectories = 0;
    final written = <String, AppliedFile>{};

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
      cancelToken?.throwIfCanceled();
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
          ..sort((x, y) => y.entry!.size.compareTo(x.entry!.size));

    Future<void> copyFile(SyncAction action) async {
      cancelToken?.throwIfCanceled();
      final sources = action.targetsRight ? (from: a, to: b) : (from: b, to: a);
      final applied = await _copyWithRetry(
        sources.from,
        sources.to,
        action.path,
        action.entry!,
        cancelToken,
      );
      written[action.path] = applied;
      if (action.kind == SyncActionKind.createLeft ||
          action.kind == SyncActionKind.createRight) {
        created++;
      } else {
        updated++;
      }
      onAction?.call(action);
    }

    // The list is sorted large-first, so the heaviest transfers start early and
    // small files fill the remaining bandwidth. Files below the threshold run
    // on several lanes to hide their per-file round trips.
    final bulkWrites = fileWrites
        .where((action) => action.entry!.size >= _parallelThresholdBytes)
        .toList();
    final smallWrites = fileWrites
        .where((action) => action.entry!.size < _parallelThresholdBytes)
        .toList();
    final failure = _CopyFailure();
    await Future.wait([
      _runPool(bulkWrites, 1, copyFile, failure),
      _runPool(smallWrites, _parallelLanes, copyFile, failure),
    ]);
    final copyError = failure.error;
    if (copyError != null) {
      Error.throwWithStackTrace(copyError, failure.stackTrace!);
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
      cancelToken?.throwIfCanceled();
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
      cancelToken?.throwIfCanceled();
      final target = action.targetsRight ? b : a;
      if (await target.deleteDirectoryIfEmpty(action.path)) {
        removedDirectories++;
      }
      onAction?.call(action);
    }

    if (plan.conflicts.isNotEmpty) {
      throw StateError('Conflicts must be resolved before applying a plan.');
    }

    return ApplyReport(
      created: created,
      updated: updated,
      deleted: deleted,
      removedDirectories: removedDirectories,
      written: written,
    );
  }

  /// Runs [run] over [items] with at most [lanes] in flight.
  ///
  /// The first failure recorded in [failure] stops both pools from starting new
  /// copies, but in-flight copies are still awaited so that no write is left
  /// dangling when the error propagates.
  static Future<void> _runPool<T>(
    List<T> items,
    int lanes,
    Future<void> Function(T item) run,
    _CopyFailure failure,
  ) async {
    if (items.isEmpty) return;

    var next = 0;
    Future<void> worker() async {
      while (failure.error == null && next < items.length) {
        final item = items[next++];
        try {
          await run(item);
        } catch (error, stack) {
          failure.error ??= error;
          failure.stackTrace ??= stack;
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < lanes && i < items.length; i++) worker(),
    ]);
  }

  Future<AppliedFile> _copyWithRetry(
    FileStore from,
    FileStore to,
    String relPath,
    ManifestEntry entry,
    SyncCancelToken? cancelToken,
  ) async {
    const maxAttempts = 3;
    for (var attempt = 1; ; attempt++) {
      try {
        return await _copy(from, to, relPath, entry, cancelToken);
      } catch (error) {
        if (error is SyncCanceledException) rethrow;
        if (attempt >= maxAttempts || !_isRetryable(error)) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
      }
    }
  }

  /// Forwards [source]'s chunks but stops the copy as soon as the user cancels.
  /// Throwing from the stream makes `writeAtomically` remove its temp file, so
  /// a partial file never becomes visible on the target side.
  static Stream<List<int>> _cancellable(
    Stream<List<int>> source,
    SyncCancelToken? cancelToken,
  ) async* {
    if (cancelToken == null) {
      yield* source;
      return;
    }
    await for (final chunk in source) {
      cancelToken.throwIfCanceled();
      yield chunk;
    }
    cancelToken.throwIfCanceled();
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

  Future<AppliedFile> _copy(
    FileStore from,
    FileStore to,
    String relPath,
    ManifestEntry entry,
    SyncCancelToken? cancelToken,
  ) async {
    final parent = p.posix.dirname(relPath);
    if (parent != '.' && parent.isNotEmpty) {
      await to.ensureDirectory(parent);
    }

    final modified = DateTime.fromMillisecondsSinceEpoch(entry.mtimeMs);
    final textHash = entry.textHash;
    final reader = _cancellable(from.openRead(relPath), cancelToken);

    if (textHash == null) {
      await to.writeAtomically(relPath, reader, modified: modified);
      final info = await to.stat(relPath);
      if (info.size != entry.size) {
        throw StateError(
          'Size mismatch after copying $relPath: '
          'expected ${entry.size}, got ${info.size}',
        );
      }
      // The copy is byte-identical, so the source fingerprint still applies.
      return AppliedFile(
        size: info.size,
        mtimeMs: info.mtimeMs,
        hash: entry.hash ?? '',
      );
    }

    // Text files are normalized to LF on the destination so CRLF copies are
    // gradually replaced every time they are overwritten. The normalized hash
    // is identical on both sides, which keeps later comparisons stable.
    var written = 0;
    await to.writeAtomically(
      relPath,
      _normalizeText(reader, (bytes) => written += bytes),
      modified: modified,
    );

    final info = await to.stat(relPath);
    if (info.size != written) {
      throw StateError(
        'Size mismatch after normalizing $relPath: '
        'expected $written, got ${info.size}',
      );
    }
    return AppliedFile(
      size: info.size,
      mtimeMs: info.mtimeMs,
      hash: textHash,
      textHash: textHash,
    );
  }

  static Stream<List<int>> _normalizeText(
    Stream<List<int>> input,
    void Function(int) onBytes,
  ) async* {
    final normalizer = LineEndingNormalizer();
    await for (final chunk in input) {
      final bytes = normalizer.add(chunk);
      if (bytes.isNotEmpty) {
        onBytes(bytes.length);
        yield bytes;
      }
    }
    final tail = normalizer.finish();
    if (tail.isNotEmpty) {
      onBytes(tail.length);
      yield tail;
    }
  }

  static int _depth(String path) => path.split('/').length;
}

/// First copy error shared by all lanes of one apply pass.
final class _CopyFailure {
  Object? error;
  StackTrace? stackTrace;
}
