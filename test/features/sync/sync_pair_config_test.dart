import 'dart:convert';
import 'dart:io';

import 'package:file_sync_pro/features/sync/application/sync_pair_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('filesync-config-');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  String writeConfig(Map<String, Object?> json) {
    final path = p.join(temp.path, 'tool', 'sync.config.json');
    Directory(p.dirname(path)).createSync(recursive: true);
    File(path).writeAsStringSync(jsonEncode(json));
    return path;
  }

  test('loads relative paths against the project root', () {
    final path = writeConfig({
      'localRoot': '../photolens',
      'remoteUrl': 'http://example.com:2160/photolens',
      'token': 'secret',
      'stateDir': 'data/sync_pairs/photolens',
      'timeoutSeconds': 42,
      'ignores': ['.venv/', '*.tmp'],
    });

    final config = SyncPairConfig.load(
      configPath: path,
      projectRoot: temp.path,
    )!;

    expect(config.localRoot, p.normalize(p.join(temp.path, '..', 'photolens')));
    expect(
      config.stateDir,
      p.join(temp.path, 'data', 'sync_pairs', 'photolens'),
    );
    expect(config.remoteUrl, 'http://example.com:2160/photolens');
    expect(config.token, 'secret');
    expect(config.timeoutSeconds, 42);
    expect(config.extraIgnores, ['.venv/', '*.tmp']);
    expect(config.pairName, 'photolens');
  });

  test('returns null when remoteUrl is missing', () {
    final path = writeConfig({'localRoot': 'data'});
    expect(
      SyncPairConfig.load(configPath: path, projectRoot: temp.path),
      isNull,
    );
  });

  test('explicit values override the config file', () {
    final path = writeConfig({
      'localRoot': 'from-config',
      'remoteUrl': 'http://config:2160/pair',
      'token': 'config-token',
      'stateDir': 'state-config',
      'timeoutSeconds': 10,
    });

    final config = SyncPairConfig.load(
      configPath: path,
      projectRoot: temp.path,
      localRoot: 'from-cli',
      remoteUrl: 'http://cli:2160/pair',
      token: 'cli-token',
      stateDir: 'state-cli',
      timeoutSeconds: 20,
    )!;

    expect(config.localRoot, p.join(temp.path, 'from-cli'));
    expect(config.remoteUrl, 'http://cli:2160/pair');
    expect(config.token, 'cli-token');
    expect(config.stateDir, p.join(temp.path, 'state-cli'));
    expect(config.timeoutSeconds, 20);
  });

  test('uses defaults when the file is absent', () {
    final config = SyncPairConfig.load(
      configPath: p.join(temp.path, 'missing.json'),
      projectRoot: temp.path,
      remoteUrl: 'http://example:2160/photolens',
    )!;

    expect(config.localRoot, p.normalize(p.join(temp.path, '..', 'photolens')));
    expect(
      config.stateDir,
      p.join(temp.path, 'data', 'sync_pairs', 'photolens'),
    );
    expect(config.timeoutSeconds, 300);
    expect(config.extraIgnores, isEmpty);
  });

  test('pair name falls back to sync for a bare URL', () {
    final config = SyncPairConfig.load(
      configPath: p.join(temp.path, 'missing.json'),
      projectRoot: temp.path,
      remoteUrl: 'http://example:2160/',
    )!;
    expect(config.pairName, 'sync');
  });

  test('finds the project root from a nested executable path', () {
    final root = Directory(p.join(temp.path, 'project'))
      ..createSync(recursive: true);
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: demo');
    Directory(p.join(root.path, 'tool')).createSync();

    final executable = p.join(
      root.path,
      'build',
      'macos',
      'Build',
      'Products',
      'Debug',
      'demo.app',
      'Contents',
      'MacOS',
      'demo',
    );

    expect(
      SyncPairConfig.findProjectRoot(executablePath: executable),
      root.path,
    );
  });
}
