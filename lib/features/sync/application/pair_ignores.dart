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
  /// The local snapshot wins over the remote one. When the local folder has no
  /// `.gitignore` but the peer has one, the peer file is copied into the local
  /// folder before it is shown. Nothing else is migrated or rewritten here, so
  /// opening the editor has no other side effects.
  Future<IgnoresLoadResult> load() async {
    final problems = <String>[];
    final localStore = LocalFileStore(localRoot);

    String? localGitignore;
    try {
      localGitignore = await _readText(localStore, gitignoreFile);
    } catch (error) {
      problems.add('Cannot read $gitignoreFile: $error');
    }

    SnapshotIgnores? localIgnores;
    try {
      localIgnores = await _readIgnores(localStore);
    } catch (error) {
      problems.add('Cannot read the local snapshot: $error');
    }

    if (localIgnores != null && !localIgnores.useGitignore) {
      return IgnoresLoadResult(
        form: IgnoresForm.builtinList,
        text: localIgnores.patterns.join('\n'),
        source: IgnoresSource.local,
        warning: _warning(problems),
      );
    }

    if (localGitignore != null) {
      return IgnoresLoadResult(
        form: IgnoresForm.gitignore,
        text: localGitignore,
        source: IgnoresSource.local,
        warning: _warning(problems),
      );
    }

    // The local side has no .gitignore (and either no snapshot or a
    // "$gitignore" marker). Ask the peer and mirror its file locally.
    if (remoteUrl.isNotEmpty) {
      final transport = _transport();
      try {
        final remoteStore = HttpFileStore(transport);
        String? remoteGitignore;
        try {
          remoteGitignore = await _readText(remoteStore, gitignoreFile);
        } catch (error) {
          problems.add('Cannot read the remote $gitignoreFile: $error');
        }
        if (remoteGitignore != null) {
          try {
            await _writeText(localStore, gitignoreFile, remoteGitignore);
          } catch (error) {
            problems.add('Cannot save $gitignoreFile locally: $error');
          }
          return IgnoresLoadResult(
            form: IgnoresForm.gitignore,
            text: remoteGitignore,
            source: IgnoresSource.remote,
            warning: _warning(problems),
          );
        }

        if (localIgnores == null) {
          final remoteIgnores = await _readIgnores(remoteStore);
          if (remoteIgnores != null) {
            return IgnoresLoadResult(
              form: remoteIgnores.useGitignore
                  ? IgnoresForm.gitignore
                  : IgnoresForm.builtinList,
              text: remoteIgnores.useGitignore
                  ? ''
                  : remoteIgnores.patterns.join('\n'),
              source: IgnoresSource.remote,
              warning: _warning(problems),
            );
          }
        }
      } catch (error) {
        problems.add('Cannot read the remote snapshot: $error');
      } finally {
        await transport.close();
      }
    }

    if (localIgnores != null) {
      return IgnoresLoadResult(
        form: IgnoresForm.gitignore,
        text: '',
        source: IgnoresSource.local,
        warning: _warning(problems),
      );
    }

    return IgnoresLoadResult(
      form: IgnoresForm.builtinList,
      text: '',
      warning: _warning(problems),
    );
  }

  static String? _warning(List<String> problems) {
    return problems.isEmpty ? null : problems.join('\n');
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
