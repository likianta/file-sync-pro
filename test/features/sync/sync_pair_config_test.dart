import 'dart:io';

import 'package:file_sync_pro/features/sync/application/sync_pair_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('filesync-pair-config-');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('finds the project root from a nested executable path', () {
    final root = Directory(p.join(temp.path, 'project'))..createSync();
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: demo');
    Directory(p.join(root.path, 'tool')).createSync();
    final executable = p.join(
      root.path,
      'build',
      'macos',
      'Build',
      'Products',
      'Debug',
      'app',
    );
    Directory(p.dirname(executable)).createSync(recursive: true);
    File(executable).writeAsStringSync('');

    expect(
      SyncPairConfig.findProjectRoot(executablePath: executable),
      root.path,
    );
  });
}
