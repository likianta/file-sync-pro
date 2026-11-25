/// Reads and updates the ignore rules used by one sync pair.
///
/// Two forms are supported, mirroring `.file_sync_shot.json`:
/// - `"$gitignore"`: the editor shows `<root>/.gitignore` and saves back to it.
/// - a list of patterns: the editor shows one pattern per line and saves the
///   list inside the snapshot.
///
/// The snapshot is the single source of truth for the form, so opening the
/// editor has no side effects and editing always writes the same form back.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../transport/http_file_store.dart';
import '../../transport/http_transport.dart';
import '../data/file_store.dart';
import '../data/snapshot_store.dart';
import '../domain/sync_snapshot.dart';

/// Side that supplied the ignore rules shown by the editor.
enum IgnoresSource { local, remote }

/// How the ignore rules are stored.
enum IgnoresForm {
  /// A `"$gitignore"` marker; the rules live in `<root>/.gitignore`.
  gitignore,

  /// A plain list of patterns inside `.file_sync_shot.json`.
  builtinList,
}

final class IgnoresLoadResult {
  const IgnoresLoadResult({
    required this.form,
    required this.text,
    this.source,
    this.warning,
  });

  final IgnoresForm form;

  /// Multiline editor content: `.gitignore` lines or one pattern per line.
  final String text;

  /// Null when neither side has a snapshot yet.
  final IgnoresSource? source;

  /// Non-fatal problem such as an unreachable peer.
  final String? warning;
}

final class IgnoresSaveException implements Exception {
  const IgnoresSaveException(this.side, this.cause);

  /// `local` or `remote`.
  final String side;
  final Object cause;

  @override
  String toString() => 'Cannot update the $side ignores: $cause';
}

/// Loads and saves one pair's ignore rules without scanning any folder.
final class PairIgnoresStore {
  PairIgnoresStore({
    required this.localRoot,
    required this.remoteUrl,
    required this.token,
    this.pairName = 'pair',
    this.timeout = const Duration(seconds: 20),
  });

  static const gitignoreFile = '.gitignore';

  final String localRoot;

  /// Empty while the dialog has no remote mount yet.
  final String remoteUrl;
  final String token;
  final String pairName;
  final Duration timeout;

  /// Reads the stored form and the matching editor content.
  ///
  /// The local snapshot wins over the remote one. Nothing is migrated or
  /// rewritten here, so simply opening the dialog has no side effects.
  Future<IgnoresLoadResult> load() async {
    final problems = <String>[];

    try {
      final store = LocalFileStore(localRoot);
      final ignores = await _readIgnores(store);
      if (ignores != null) {
        return await _result(ignores, IgnoresSource.local, store, problems);
      }
    } catch (error) {
      problems.add('Cannot read the local snapshot: $error');
    }

    if (remoteUrl.isNotEmpty) {
      final transport = _transport();
      try {
        final store = HttpFileStore(transport);
        final ignores = await _readIgnores(store);
        if (ignores != null) {
          return await _result(ignores, IgnoresSource.remote, store, problems);
        }
      } catch (error) {
        problems.add('Cannot read the remote snapshot: $error');
      } finally {
        await transport.close();
      }
    }

    return IgnoresLoadResult(
      form: IgnoresForm.builtinList,
      text: '',
      warning: problems.isEmpty ? null : problems.join('\n'),
    );
  }

  /// Writes [text] back using the stored [form] on both sides.
  ///
  /// In list form the snapshot keeps its base and current entries and only
  /// `ignores` changes. In gitignore form `<root>/.gitignore` is rewritten and
  /// the snapshot keeps the `"$gitignore"` marker.
  Future<void> save({required IgnoresForm form, required String text}) async {
    final backupDir = defaultSnapshotBackupDir();

    try {
      final store = LocalFileStore(localRoot);
      await _saveSide(
        store: store,
        snapshot: SnapshotStore(
          store,
          backupDir: backupDir,
          label: '$pairName-local',
        ),
        form: form,
        text: text,
      );
    } catch (error) {
      throw IgnoresSaveException('local', error);
    }

    if (remoteUrl.isEmpty) return;
    final transport = _transport();
    try {
      final store = HttpFileStore(transport);
      await _saveSide(
        store: store,
        snapshot: SnapshotStore(
          store,
          backupDir: backupDir,
          label: '$pairName-remote',
        ),
        form: form,
        text: text,
      );
    } catch (error) {
      throw IgnoresSaveException('remote', error);
    } finally {
      await transport.close();
    }
  }

  HttpTransport _transport() {
    return HttpTransport(baseUrl: remoteUrl, token: token, timeout: timeout);
  }

  Future<IgnoresLoadResult> _result(
    SnapshotIgnores ignores,
    IgnoresSource source,
    FileStore store,
    List<String> problems,
  ) async {
    var warning = problems.isEmpty ? null : problems.join('\n');
    if (!ignores.useGitignore) {
      return IgnoresLoadResult(
        form: IgnoresForm.builtinList,
        text: ignores.patterns.join('\n'),
        source: source,
        warning: warning,
      );
    }

    var text = '';
    try {
      text = await _readText(store, gitignoreFile) ?? '';
    } catch (error) {
      warning = [?warning, 'Cannot read $gitignoreFile: $error'].join('\n');
    }
    return IgnoresLoadResult(
      form: IgnoresForm.gitignore,
      text: text,
      source: source,
      warning: warning,
    );
  }

  static Future<void> _saveSide({
    required FileStore store,
    required SnapshotStore snapshot,
    required IgnoresForm form,
    required String text,
  }) async {
    switch (form) {
      case IgnoresForm.gitignore:
        await _writeText(store, gitignoreFile, text);
        await _writeSnapshot(snapshot, const SnapshotIgnores.gitignore());
      case IgnoresForm.builtinList:
        final patterns = text
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();
        await _writeSnapshot(snapshot, SnapshotIgnores.patterns(patterns));
    }
  }

  static Future<void> _writeSnapshot(
    SnapshotStore store,
    SnapshotIgnores ignores,
  ) async {
    final loaded = await store.load();
    final existing = loaded.snapshot;
    final next = existing == null
        ? SideSnapshot(
            base: SnapshotState.empty(),
            current: SnapshotState.empty(),
            ignores: ignores,
          )
        : existing.copyWith(ignores: ignores);
    await store.save(next);
  }

  static Future<SnapshotIgnores?> _readIgnores(FileStore store) async {
    final text = await _readText(store, SnapshotStore.defaultFileName);
    if (text == null || text.trim().isEmpty) return null;
    final decoded = jsonDecode(text);
    if (decoded is! Map) return null;
    final raw = decoded['ignores'];
    return raw == null ? SnapshotIgnores.empty : SnapshotIgnores.fromJson(raw);
  }

  static Future<String?> _readText(FileStore store, String relPath) async {
    if (!await store.exists(relPath)) return null;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in store.openRead(relPath)) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    return bytes.isEmpty ? '' : utf8.decode(bytes);
  }

  static Future<void> _writeText(
    FileStore store,
    String relPath,
    String text,
  ) async {
    final normalized = text.isEmpty || text.endsWith('\n') ? text : '$text\n';
    await store.writeAtomically(
      relPath,
      Stream.value(utf8.encode(normalized)),
      modified: DateTime.now(),
    );
  }
}
