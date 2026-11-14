// ignore_for_file: avoid_print

import 'dart:io';

import 'package:file_sync_pro/features/sync/application/sync_client_config.dart';
import 'package:file_sync_pro/features/sync/application/sync_engine.dart';
import 'package:file_sync_pro/features/sync/application/sync_pair_config.dart';
import 'package:file_sync_pro/features/sync/application/sync_source.dart';
import 'package:file_sync_pro/features/sync/domain/ignore_rules.dart';
import 'package:file_sync_pro/features/sync/domain/manifest.dart';
import 'package:file_sync_pro/features/sync/domain/sync_plan.dart';
import 'package:file_sync_pro/features/transport/http_transport.dart';
import 'package:path/path.dart' as p;

/// macOS-side entry point for the photolens pair.
///
/// Usage:
///   dart run tool/sync_cli.dart --dry-run
///   dart run tool/sync_cli.dart
///
/// A local config file is loaded automatically when present:
///   tool/sync.config.json
Future<void> main(List<String> args) async {
  final projectRoot = _projectRoot();
  late final _SyncOptions options;
  try {
    options = _SyncOptions.parse(args, projectRoot);
  } catch (error) {
    stderr.writeln('Invalid arguments or config: $error');
    stderr.writeln('Run with --help for usage.');
    exitCode = 1;
    return;
  }

  if (options.showHelp) {
    _printHelp();
    return;
  }

  final config = options.config!;
  final localDir = Directory(config.localRoot);
  if (!await localDir.exists()) {
    print('Creating local folder: ${localDir.path}');
    await localDir.create(recursive: true);
  }

  final ignores = IgnoreRules.defaults(extra: config.extraIgnores);
  final local = LocalSyncSource(config.localRoot, ignores: ignores);
  final remote = RemoteSyncSource(
    baseUrl: config.remoteUrl,
    token: config.token,
    ignores: ignores,
    timeout: Duration(seconds: config.timeoutSeconds),
  );
  final engine = SyncEngine(a: local, b: remote, stateDir: config.stateDir);

  try {
    print('Local : ${local.id}');
    print('Remote: ${remote.id}');
    print('State : ${config.stateDir}');
    print('');

    stdout.write('Scanning both sides...');
    final preview = await engine.preview();
    stdout.writeln(' done.');
    _printPreviewSummary(preview);

    if (preview.plan.isEmpty) {
      print('Already in sync.');
      return;
    }

    if (options.dryRun) {
      _printActions(preview.plan.actions);
      _printConflicts(preview.plan.conflicts);
      print('');
      print('Dry run only; nothing was changed.');
      return;
    }

    print('');
    print('Applying...');
    final report = await engine.execute(preview, onAction: _printAction);
    final apply = report.applyReport!;

    print('');
    print(
      'Done: ${apply.created} uploaded/created, '
      '${apply.updated} updated, '
      '${apply.deleted} deleted, '
      '${apply.removedDirectories} dirs removed.',
    );
    _printConflicts(report.preview.plan.conflicts);
    if (report.conflictBackupRoot != null) {
      print('Conflict copies: ${report.conflictBackupRoot}');
    }
    if (report.journalPath != null) {
      print('Journal: ${report.journalPath}');
    }
    if (report.hasConflicts) {
      print('');
      print('Some files were left untouched because both sides changed.');
      exitCode = 2;
    }
  } on RemoteException catch (error) {
    stderr.writeln('Remote error: ${_describeRemoteError(error)}');
    exitCode = 1;
  } on SocketException catch (error) {
    stderr.writeln(
      'Cannot reach ${config.remoteUrl}: ${error.message}\n'
      'Check that the Windows server is running, and that the tunnel '
      'forwards the public port to it.',
    );
    exitCode = 1;
  } on SyncDivergenceException catch (error) {
    stderr.writeln('Sync finished but the two sides diverged: $error');
    exitCode = 1;
  } catch (error) {
    stderr.writeln('Sync failed: $error');
    exitCode = 1;
  } finally {
    await remote.close();
  }
}

void _printPreviewSummary(SyncPreview preview) {
  print('Local : ${_describeManifest(preview.a)}');
  print('Remote: ${_describeManifest(preview.b)}');
  print('Base  : ${_describeManifest(preview.base)}');
  print(
    'Plan  : ${preview.plan.createCount} create, '
    '${preview.plan.updateCount} update, '
    '${preview.plan.deleteCount} delete, '
    '${preview.plan.conflicts.length} conflicts.',
  );
}

String _describeManifest(Manifest manifest) {
  return '${manifest.fileCount} files, ${manifest.directoryCount} dirs';
}

void _printActions(List<SyncAction> actions) {
  if (actions.isEmpty) return;
  print('');
  print('Actions:');
  for (final action in actions) {
    _printAction(action);
  }
}

void _printAction(SyncAction action) {
  final symbol = switch (action.kind) {
    SyncActionKind.createRight => '+>',
    SyncActionKind.updateRight => '=>',
    SyncActionKind.deleteRight => '->',
    SyncActionKind.createLeft => '<+',
    SyncActionKind.updateLeft => '<=',
    SyncActionKind.deleteLeft => '<-',
  };
  final verb = switch (action.kind) {
    SyncActionKind.createRight => 'upload  ',
    SyncActionKind.updateRight => 'upload  ',
    SyncActionKind.deleteRight => 'del-remote',
    SyncActionKind.createLeft => 'download',
    SyncActionKind.updateLeft => 'download',
    SyncActionKind.deleteLeft => 'del-local ',
  };
  print('  $symbol $verb  ${action.path}');
}

void _printConflicts(List<SyncConflict> conflicts) {
  if (conflicts.isEmpty) return;
  print('');
  print('Conflicts (${conflicts.length}):');
  for (final conflict in conflicts) {
    print('  ! ${conflict.path}  (${conflict.reason.name})');
  }
}

String _describeRemoteError(RemoteException error) {
  final hint = switch (error.statusCode) {
    401 =>
      'Authentication failed. Set the same token on both sides '
          '(FILE_SYNC_TOKEN or --token).',
    404 =>
      'Mount or path not found. The remote URL must include the mount '
          'name, for example http://host:2160/photolens.',
    409 =>
      'The server refused the operation because the target is a non-empty '
          'directory or a different kind of entry.',
    _ => 'The server returned an error.',
  };
  return '${error.statusCode} ${error.message}\n$hint';
}

void _printHelp() {
  print('''
Sync a local folder with a remote file-sync-pro mount.

Options:
  --local <path>     Local folder (default: <project-root>/../photolens)
  --remote <url>     Remote mount URL (required)
  --token <token>    Shared token (or FILE_SYNC_TOKEN)
  --state <path>     State folder (default: data/sync_pairs/photolens)
  --timeout <sec>    HTTP timeout in seconds (default: 300)
  --dry-run          Show the plan without changing anything
  --config <path>    Config file (default: tool/sync.config.json)
  -h, --help         Show this help
''');
}

final class _SyncOptions {
  const _SyncOptions({
    required this.config,
    required this.dryRun,
    required this.showHelp,
  });

  factory _SyncOptions.parse(List<String> args, String projectRoot) {
    String? localArg;
    String? remoteArg;
    String? tokenArg;
    String? stateArg;
    String? pairArg;
    int? timeoutArg;
    var dryRun = false;
    var showHelp = false;
    String? configPath;

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      String next(String name) {
        if (i + 1 >= args.length) {
          throw ArgumentError('Missing value for $name');
        }
        return args[++i];
      }

      switch (arg) {
        case '-h':
        case '--help':
          showHelp = true;
        case '--pair':
          pairArg = next(arg);
        case '--local':
          localArg = next(arg);
        case '--remote':
          remoteArg = next(arg);
        case '--token':
          tokenArg = next(arg);
        case '--state':
          stateArg = next(arg);
        case '--timeout':
          timeoutArg = int.parse(next(arg));
        case '--dry-run':
          dryRun = true;
        case '--config':
          configPath = next(arg);
        default:
          throw ArgumentError('Unknown argument: $arg');
      }
    }

    if (showHelp) {
      return _SyncOptions(config: null, dryRun: dryRun, showHelp: true);
    }

    final client = SyncClientConfig.load(
      path: configPath ?? p.join(projectRoot, 'tool', 'sync.config.json'),
      projectRoot: projectRoot,
    );
    if (client.pairs.isEmpty) {
      throw ArgumentError(
        'No sync pairs configured. Add one via the desktop UI, or run the '
        'legacy --remote option.',
      );
    }

    SyncPairEntry? entry;
    for (final candidate in client.pairs) {
      if (pairArg == null || candidate.name == pairArg) {
        entry = candidate;
        break;
      }
    }
    if (entry == null) {
      throw ArgumentError('Unknown pair: $pairArg');
    }

    final config = SyncPairConfig(
      name: entry.name,
      localRoot: localArg == null
          ? entry.localRoot
          : _resolvePath(projectRoot, _expandUser(localArg)),
      remoteUrl: remoteArg ?? entry.remoteUrl,
      token: tokenArg ?? client.token,
      stateDir: stateArg == null
          ? entry.stateDir
          : _resolvePath(projectRoot, _expandUser(stateArg)),
      timeoutSeconds: timeoutArg ?? client.timeoutSeconds,
      extraIgnores: client.extraIgnores,
    );

    if (config.remoteUrl.trim().isEmpty) {
      throw ArgumentError('The selected pair has no remote URL.');
    }

    return _SyncOptions(config: config, dryRun: dryRun, showHelp: false);
  }

  final SyncPairConfig? config;
  final bool dryRun;
  final bool showHelp;
}

String _projectRoot() {
  final script = Platform.script.toFilePath();
  return p.normalize(p.dirname(p.dirname(script)));
}

String _resolvePath(String projectRoot, String path) {
  return p.normalize(p.isAbsolute(path) ? path : p.join(projectRoot, path));
}

String _expandUser(String path) {
  if (path == '~') return Platform.environment['HOME'] ?? path;
  if (path.startsWith('~/')) {
    final home = Platform.environment['HOME'] ?? '';
    return p.join(home, path.substring(2));
  }
  return path;
}
