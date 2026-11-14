import 'dart:io';

import 'package:file_sync_pro/features/server/presentation/file_server_controller.dart';
import 'package:file_sync_pro/features/transport/server/file_server_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late Directory shared;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('filesync-server-ui-');
    shared = Directory(p.join(temp.path, 'shared'))..createSync();
    File(p.join(shared.path, 'hello.txt')).writeAsStringSync('hello');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('starts and stops the server from the controller', () async {
    final configPath = p.join(temp.path, 'tool', 'file_server.config.json');
    final controller = FileServerController(
      configPath: configPath,
      projectRoot: temp.path,
    );

    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();

    try {
      await controller.load();
      controller.config.mounts.add(
        FileServerMountConfig(name: 'demo', path: shared.path),
      );
      controller.updateToken('test-token');
      controller.updatePort(port);

      await controller.start();

      expect(controller.isRunning, isTrue);
      expect(controller.status, FileServerStatus.running);
      expect(File(configPath).existsSync(), isTrue);

      final saved = FileServerConfig.load(
        path: configPath,
        projectRoot: temp.path,
      );
      expect(saved.token, 'test-token');
      expect(saved.port, port);
      expect(saved.host, '0.0.0.0');
      expect(saved.mounts.single.name, 'demo');
      expect(saved.mounts.single.path, shared.path);

      await controller.stop();
      expect(controller.isRunning, isFalse);
      expect(controller.status, FileServerStatus.stopped);
    } finally {
      controller.dispose();
    }
  });

  test('refuses to start without a token', () async {
    final controller = FileServerController(
      configPath: p.join(temp.path, 'tool', 'file_server.config.json'),
      projectRoot: temp.path,
    );
    try {
      await controller.load();
      controller.config.mounts.add(
        FileServerMountConfig(name: 'demo', path: shared.path),
      );
      await controller.start();

      expect(controller.isRunning, isFalse);
      expect(controller.status, FileServerStatus.error);
      expect(controller.errorMessage, contains('token'));
    } finally {
      controller.dispose();
    }
  });
}
