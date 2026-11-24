import 'dart:io';

import 'package:file_sync_pro/features/sync/domain/file_fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('xxHash64 matches known vectors', () {
    String hashOf(List<int> bytes) {
      final hasher = XxHash64()..add(bytes);
      return XxHash64.hex(hasher.digest());
    }

    expect(hashOf(const []), 'ef46db3751d8e999');
    expect(hashOf(const [0x61]), 'd24ec4f1a98c6e5b');
    expect(hashOf(const [0x61, 0x62, 0x63]), '44bc2cf5ad770999');
  });

  test('long input stays stable across chunk boundaries', () {
    final bytes = List<int>.generate(100000, (index) => index & 0xFF);
    final single = XxHash64()..add(bytes);
    final chunked = XxHash64();
    for (var offset = 0; offset < bytes.length; offset += 37) {
      chunked.add(bytes.sublist(offset, (offset + 37).clamp(0, bytes.length)));
    }
    expect(XxHash64.hex(chunked.digest()), XxHash64.hex(single.digest()));
  });

  test('text files use a full hash and a normalized text hash', () async {
    final temp = await Directory.systemTemp.createTemp('filesync-fp-');
    addTearDown(() => temp.delete(recursive: true));
    final file = File(p.join(temp.path, 'note.txt'))
      ..writeAsStringSync('hello\r\nworld\r\n');

    final fingerprint = await fingerprintFile(
      file.path,
      size: file.lengthSync(),
    );

    expect(fingerprint.isText, isTrue);
    expect(fingerprint.sampled, isFalse);
    expect(fingerprint.hash, startsWith('x64:'));
    expect(fingerprint.textHash, startsWith('x64:'));
    expect(fingerprint.textHash, isNot(fingerprint.hash));
  });

  test('large binary files use a sampled fingerprint', () async {
    final temp = await Directory.systemTemp.createTemp('filesync-fp-');
    addTearDown(() => temp.delete(recursive: true));
    final bytes = List<int>.generate(
      fingerprintSampleThreshold + 4096,
      (index) => index & 0xFF,
    );
    bytes[0] = 0;
    final file = File(p.join(temp.path, 'video.bin'))..writeAsBytesSync(bytes);

    final fingerprint = await fingerprintFile(
      file.path,
      size: file.lengthSync(),
    );

    expect(fingerprint.isText, isFalse);
    expect(fingerprint.sampled, isTrue);
    expect(fingerprint.hash, startsWith('x64s:'));
    expect(fingerprint.textHash, isNull);
  });

  test('small binary files use a full hash', () async {
    final temp = await Directory.systemTemp.createTemp('filesync-fp-');
    addTearDown(() => temp.delete(recursive: true));
    final file = File(p.join(temp.path, 'small.bin'))
      ..writeAsBytesSync(const [0, 1, 2, 3, 4]);

    final fingerprint = await fingerprintFile(
      file.path,
      size: file.lengthSync(),
    );

    expect(fingerprint.isText, isFalse);
    expect(fingerprint.sampled, isFalse);
    expect(fingerprint.hash, startsWith('x64:'));
  });
}
