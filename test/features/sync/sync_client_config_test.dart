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

  test('loads nested device pairs and derives runtime values', () {
    final path = write({
      'version': 4,
      'token': 'secret',
      'timeoutSeconds': 42,
      'devices': [
        {
          'id': 'd-phone',
          'name': 'Phone',
          'type': 'android',
          'model': 'androidPhone',
          'host_type': 'remote',
          'host': 'host',
          'port': 2160,
          'pairs': [
            {
              'id': 'p-gitbook',
              'name': 'gitbook',
              'local_root': '../gitbook',
              'remote_root': '/gitbook',
            },
            {
              'id': 'p-notes',
              'name': 'notes',
              'local_root': '/tmp/notes',
              'remote_root': '/notes',
            },
          ],
        },
      ],
    });

    final config = SyncClientConfig.load(path: path, projectRoot: temp.path);

    expect(config.token, 'secret');
    expect(config.timeoutSeconds, 42);
    expect(config.devices, hasLength(1));
    final device = config.devices.single;
    expect(device.id, 'd-phone');
    expect(device.name, 'Phone');
    expect(device.type, SyncDeviceType.android);
    expect(device.hostType, SyncHostType.remote);
    expect(device.pairs, hasLength(2));
    expect(config.pairs, hasLength(2));

    final runtime = config.runtimeFor('d-phone', 'gitbook')!;
    expect(runtime.pairName, 'gitbook');
    expect(runtime.localRoot, p.normalize(p.join(temp.path, '..', 'gitbook')));
    expect(runtime.remoteUrl, 'http://host:2160/gitbook');
    expect(
      runtime.stateDir,
      p.join(temp.path, 'data', 'sync_pairs', 'p-gitbook'),
    );
    expect(
      config.runtimeForPairId('p-notes')!.remoteUrl,
      'http://host:2160/notes',
    );
  });

  test('migrates version 3 devices and top-level pairs', () {
    final path = write({
      'version': 3,
      'token': 'legacy',
      'devices': [
        {
          'id': 'dev-host-2160',
          'name': 'Host',
          'hostType': 'remote',
          'host': 'host',
          'port': 2160,
        },
      ],
      'pairs': [
        {
          'name': 'photos',
          'deviceId': 'dev-host-2160',
          'localRoot': '../photos',
          'remoteUrl': 'http://host:2160/photos',
          'stateDir': 'data/sync_pairs/photos',
          'ignores': ['/blog/'],
        },
      ],
    });

    final config = SyncClientConfig.load(path: path, projectRoot: temp.path);

    expect(config.token, 'legacy');
    expect(config.devices, hasLength(1));
    expect(config.devices.single.pairs, hasLength(1));
    final pair = config.pairs.single;
    expect(pair.name, 'photos');
    expect(pair.remoteRoot, '/photos');
    expect(pair.deviceId, config.devices.single.id);
    expect(pair.stateDir, p.join(temp.path, 'data', 'sync_pairs', 'photos'));
    expect(config.firstRuntime!.remoteUrl, 'http://host:2160/photos');
  });

  test('returns an empty config when the file is absent', () {
    final config = SyncClientConfig.load(
      path: p.join(temp.path, 'missing.json'),
      projectRoot: temp.path,
    );
    expect(config.pairs, isEmpty);
    expect(config.firstRuntime, isNull);
  });

  test('save writes version 4 with nested pairs and round-trips', () async {
    final path = p.join(temp.path, 'tool', 'sync.config.json');
    final config = SyncClientConfig(
      token: 't',
      timeoutSeconds: 10,
      devices: [
        SyncDeviceEntry(
          id: 'd-box',
          name: 'Windows box',
          host: 'host',
          port: 2160,
          pairs: [
            SyncPairEntry(
              id: 'p-demo',
              name: 'demo',
              localRoot: '/tmp/demo',
              remoteRoot: '/demo',
              deviceId: 'd-box',
              stateDir: '/tmp/state-demo',
            ),
          ],
        ),
      ],
    );

    await config.save(path: path);
    final restored = SyncClientConfig.load(path: path, projectRoot: temp.path);

    expect(restored.token, 't');
    expect(restored.devices.single.name, 'Windows box');
    expect(restored.devices.single.pairs.single.name, 'demo');
    expect(restored.pairs.single.deviceId, 'd-box');
    expect(restored.pairs.single.localRoot, '/tmp/demo');
    expect(restored.pairs.single.remoteRoot, '/demo');

    final json = jsonDecode(File(path).readAsStringSync()) as Map;
    expect(json['version'], 4);
    expect(json['devices'], hasLength(1));
    expect(json.containsKey('pairs'), isFalse);
    final device = (json['devices'] as List).single as Map;
    expect(device.containsKey('host_type'), isTrue);
    expect(device['pairs'], hasLength(1));
  });

  test('pair names may repeat across devices', () {
    final path = write({
      'version': 4,
      'token': '',
      'devices': [
        {
          'id': 'd-one',
          'name': 'One',
          'host': 'one',
          'port': 2160,
          'pairs': [
            {
              'id': 'p-a',
              'name': 'pictures',
              'local_root': '/tmp/a',
              'remote_root': '/pictures',
            },
          ],
        },
        {
          'id': 'd-two',
          'name': 'Two',
          'host': 'two',
          'port': 2160,
          'pairs': [
            {
              'id': 'p-b',
              'name': 'pictures',
              'local_root': '/tmp/b',
              'remote_root': '/pictures',
            },
          ],
        },
      ],
    });

    final config = SyncClientConfig.load(path: path, projectRoot: temp.path);
    expect(config.pairsForDevice('d-one').single.name, 'pictures');
    expect(config.pairsForDevice('d-two').single.name, 'pictures');
    expect(config.uniquePairName('d-one', 'pictures'), 'pictures 2');
    expect(config.uniquePairName('d-two', 'family'), 'family');
  });
}
