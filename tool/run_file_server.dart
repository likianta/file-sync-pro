// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_sync_pro/features/sync/domain/ignore_rules.dart';
import 'package:file_sync_pro/features/transport/protocol.dart';
import 'package:file_sync_pro/features/transport/server/file_server.dart';
import 'package:path/path.dart' as p;

/// Windows-side entry point.
///
/// Usage:
///   dart run tool/run_file_server.dart
///   dart run tool/run_file_server.dart --port 2160 --token me
///   dart run tool/run_file_server.dart --mount photolens=C:/path/to/photolens
///
/// A local config file is loaded automatically when present:
///   tool/file_server.config.json
Future<void> main(List<String> args) async {
  final projectRoot = _projectRoot();
  late final _ServerOptions options;
  try {
    options = _ServerOptions.parse(args, projectRoot);
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

  final mounts = options.mounts.isEmpty
      ? _defaultMounts(projectRoot)
      : options.mounts;
  if (mounts.isEmpty) {
    stderr.writeln(
      'No mounts configured.\n'
      'Create tool/file_server.config.json (see the example), or pass '
      '--mount name=path.',
    );
    exitCode = 1;
    return;
  }

  final server = FileServer(
    mounts: mounts.values,
    token: options.token,
    verbose: options.verbose,
  );

  try {
    await server.start(host: options.host, port: options.port);
  } on SocketException catch (error) {
    stderr.writeln(
      'Cannot bind ${options.host}:${options.port}: ${error.message}',
    );
    exitCode = 1;
    return;
  }

  print('');
  print('Expose this port through your tunnel / frp, for example:');
  print('  public host:${server.port} -> 127.0.0.1:${server.port}');
  print('Client URL example:');
  for (final mount in mounts.values) {
    print('  http://<public-host>:${server.port}/${mount.name}');
  }
  print('');
  print('Press Ctrl+C to stop.');

  final signal = ProcessSignal.sigint.watch();
  signal.listen((_) async {
    print('\n[file-server] shutting down...');
    await server.close(force: true);
    exit(0);
  });

  // Keep the process alive until the signal arrives.
  await Completer<void>().future;
}

Map<String, FileServerMount> _defaultMounts(String projectRoot) {
  final candidate = p.normalize(p.join(projectRoot, '..', 'photolens'));
  if (Directory(candidate).existsSync()) {
    return {'photolens': FileServerMount(name: 'photolens', root: candidate)};
  }
  return {};
}

void _printHelp() {
  print('''
Run the file-sync-pro HTTP file server.

Options:
  --host <addr>          Bind address (default: 127.0.0.1)
  --port <port>          Bind port (default: $defaultFileServerPort)
  --token <token>        Shared token for clients (or FILE_SYNC_TOKEN)
  --mount <name=path>    Mount a folder; repeatable
  --config <path>        Config file (default: tool/file_server.config.json)
  --verbose              Log every request
  -h, --help             Show this help

Default mount when nothing is configured:
  photolens -> <project-root>/../photolens
''');
}

final class _ServerOptions {
  _ServerOptions({
    required this.host,
    required this.port,
    required this.token,
    required this.mounts,
    required this.verbose,
    required this.showHelp,
  });

  factory _ServerOptions.parse(List<String> args, String projectRoot) {
    String? hostArg;
    int? portArg;
    String? tokenArg;
    bool? verboseArg;
    var showHelp = false;
    final mounts = <String, FileServerMount>{};
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
        case '--host':
          hostArg = next(arg);
        case '--port':
          portArg = int.parse(next(arg));
        case '--token':
          tokenArg = next(arg);
        case '--mount':
          final value = next(arg);
          final index = value.indexOf('=');
          if (index <= 0) {
            throw ArgumentError('--mount expects name=path, got: $value');
          }
          final name = value.substring(0, index);
          final root = _expandUser(value.substring(index + 1));
          mounts[name] = FileServerMount(name: name, root: root);
        case '--config':
          configPath = next(arg);
        case '--verbose':
          verboseArg = true;
        default:
          throw ArgumentError('Unknown argument: $arg');
      }
    }

    final config = _loadConfig(
      configPath ?? p.join(projectRoot, 'tool', 'file_server.config.json'),
    );

    final host = hostArg ?? config?['host'] as String? ?? '127.0.0.1';
    final port =
        portArg ?? (config?['port'] as num?)?.toInt() ?? defaultFileServerPort;
    final token =
        tokenArg ??
        Platform.environment['FILE_SYNC_TOKEN'] ??
        config?['token'] as String? ??
        '';
    final verbose = verboseArg ?? config?['verbose'] as bool? ?? false;

    if (mounts.isEmpty && config != null) {
      final configuredMounts = config['mounts'];
      if (configuredMounts is Map) {
        for (final entry in configuredMounts.entries) {
          final name = entry.key as String;
          final root = _expandUser(entry.value as String);
          mounts[name] = FileServerMount(name: name, root: root);
        }
      }
    }

    if (config != null) {
      final ignores = config['ignores'];
      if (ignores is List) {
        final rules = IgnoreRules.defaults(extra: ignores.whereType<String>());
        for (final entry in mounts.entries.toList()) {
          mounts[entry.key] = FileServerMount(
            name: entry.value.name,
            root: entry.value.root,
            ignores: rules,
          );
        }
      }
    }

    return _ServerOptions(
      host: host,
      port: port,
      token: token,
      mounts: mounts,
      verbose: verbose,
      showHelp: showHelp,
    );
  }

  final String host;
  final int port;
  final String token;
  final Map<String, FileServerMount> mounts;
  final bool verbose;
  final bool showHelp;
}

Map<String, Object?>? _loadConfig(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map) {
    throw FormatException('Config must be a JSON object: $path');
  }
  return decoded.cast<String, Object?>();
}

String _projectRoot() {
  final script = Platform.script.toFilePath();
  return p.normalize(p.dirname(p.dirname(script)));
}

String _expandUser(String path) {
  if (path == '~') return Platform.environment['HOME'] ?? path;
  if (path.startsWith('~/')) {
    final home = Platform.environment['HOME'] ?? '';
    return p.join(home, path.substring(2));
  }
  return path;
}
