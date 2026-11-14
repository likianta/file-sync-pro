import 'dart:convert';
import 'dart:io';

import 'package:file_sync_pro/features/sync/application/sync_client_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('filesync-client-config-');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  String write(Map<String, Object?> json) {
    final path = p.join(temp.path, 'tool', 'sync.config.json');
    Directory(p.dirname(path)).createSync(recursive: true);
    File(path).writeAsStringSync(jsonEncode(json));
    return path;
  }

  test('loads multiple pairs and resolves relative paths', () {
    final path = write({
      'version': 2,
      'token': 'secret',
      'timeoutSeconds': 42,
      'ignores': ['.venv/'],
      'pairs': [
        {
          'name': 'photos',
          'localRoot': '../photos',
          'remoteUrl': 'http://host:2160/photos',
          'stateDir': 'data/sync_pairs/photos',
          'ignores': ['/blog/', '**.b64.html'],
        },
        {
          'name': 'notes',
          'localRoot': '/tmp/notes',
          'remoteUrl': 'http://host:2160/notes',
          'stateDir': '/tmp/state-notes',
        },
      ],
    });

    final config = SyncClientConfig.load(path: path, projectRoot: temp.path);

    expect(config.pairs, hasLength(2));
    expect(config.token, 'secret');
    expect(config.timeoutSeconds, 42);
    expect(config.extraIgnores, ['.venv/']);

    // Devices are derived from the remote URLs of legacy configs.
    expect(config.devices, hasLength(1));
    final device = config.devices.single;
    expect(device.name, 'host');
    expect(device.port, 2160);
    expect(device.type, SyncDeviceType.windows);
    expect(device.hostType, SyncHostType.remote);
    expect(config.pairs.every((pair) => pair.deviceId == device.id), isTrue);

    expect(
      config.pairs[0].localRoot,
      p.normalize(p.join(temp.path, '..', 'photos')),
    );
    expect(
      config.pairs[0].stateDir,
      p.join(temp.path, 'data', 'sync_pairs', 'photos'),
    );
    expect(config.pairs[1].localRoot, '/tmp/notes');

    final runtime = config.runtimeFor('photos')!;
    expect(runtime.pairName, 'photos');
    expect(runtime.token, 'secret');
    expect(runtime.timeoutSeconds, 42);
    expect(runtime.extraIgnores, ['/blog/', '**.b64.html']);

    final fallback = config.runtimeFor('notes')!;
    expect(fallback.extraIgnores, ['.venv/']);
  });

  test('migrates a legacy single-pair config', () {
    final path = write({
      'localRoot': '../photolens',
      'remoteUrl': 'http://host:2160/photolens',
      'token': 'legacy',
      'stateDir': 'data/sync_pairs/photolens',
    });

    final config = SyncClientConfig.load(path: path, projectRoot: temp.path);

    expect(config.pairs, hasLength(1));
    expect(config.pairs.single.name, 'photolens');
    expect(config.devices, hasLength(1));
    expect(config.devices.single.name, 'host');
    expect(config.token, 'legacy');
    expect(config.firstRuntime!.pairName, 'photolens');
  });

  test('returns an empty config when the file is absent', () {
    final config = SyncClientConfig.load(
      path: p.join(temp.path, 'missing.json'),
      projectRoot: temp.path,
    );
    expect(config.pairs, isEmpty);
    expect(config.firstRuntime, isNull);
  });

  test('save writes version 3 with devices and round-trips', () async {
    final path = p.join(temp.path, 'tool', 'sync.config.json');
    final config = SyncClientConfig(
      token: 't',
      timeoutSeconds: 10,
      extraIgnores: const ['*.tmp'],
      devices: const [
        SyncDeviceEntry(
          id: 'dev-host-2160',
          name: 'Windows box',
          host: 'host',
          port: 2160,
        ),
      ],
      pairs: const [
        SyncPairEntry(
          name: 'demo',
          deviceId: 'dev-host-2160',
          localRoot: '/tmp/demo',
          remoteUrl: 'http://host:2160/demo',
          stateDir: '/tmp/state-demo',
          ignores: ['/blog/', '*.b64.html'],
        ),
      ],
    );

    await config.save(path: path);
    final restored = SyncClientConfig.load(path: path, projectRoot: temp.path);

    expect(restored.token, 't');
    expect(restored.devices.single.name, 'Windows box');
    expect(restored.pairs.single.name, 'demo');
    expect(restored.pairs.single.deviceId, 'dev-host-2160');
    expect(restored.pairs.single.localRoot, '/tmp/demo');
    expect(restored.pairs.single.remoteUrl, 'http://host:2160/demo');
    expect(restored.pairs.single.ignores, ['/blog/', '*.b64.html']);

    final json = jsonDecode(File(path).readAsStringSync()) as Map;
    expect(json['version'], 3);
    expect(json['devices'], hasLength(1));
  });
}
