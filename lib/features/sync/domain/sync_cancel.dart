/// Cooperative cancellation for a running sync.
library;

/// Set by the UI and polled by the applier between actions and file chunks.
final class SyncCancelToken {
  bool _canceled = false;

  bool get isCanceled => _canceled;

  void cancel() => _canceled = true;

  void throwIfCanceled() {
    if (_canceled) throw const SyncCanceledException();
  }
}

/// Thrown when the user stops a running sync.
final class SyncCanceledException implements Exception {
  const SyncCanceledException();

  @override
  String toString() => 'Sync stopped by the user.';
}
