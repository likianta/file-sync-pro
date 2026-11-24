/// Fast content fingerprints for sync snapshots.
///
/// SHA-256 was accurate but slow for large media folders. This file uses
/// xxHash64 and, for large binary files, hashes only three representative
/// samples. The trade-off is intentional: changes inside the unsampled middle
/// of a large video may be missed, but the collision rate is still far lower
/// than mtime + size.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'line_endings.dart';

const String fingerprintAlgorithm = 'xxh64-v1';

const int fingerprintSampleSize = 64 * 1024;

const int fingerprintSampleThreshold = 512 * 1024;

final class FileFingerprint {
  const FileFingerprint({
    required this.hash,
    required this.textHash,
    required this.sampled,
    required this.isText,
  });

  /// Prefixed hash, for example `x64:<hex>` or `x64s:<hex>`.
  final String hash;

  /// Prefixed LF-normalized hash for text files, otherwise null.
  final String? textHash;

  final bool sampled;
  final bool isText;
}

Future<FileFingerprint> fingerprintFile(
  String path, {
  required int size,
}) async {
  final file = await File(path).open();
  try {
    final probe = await file.read(8192);
    final isText = !probe.contains(0);

    if (!isText && size >= fingerprintSampleThreshold) {
      final sampled = await _sampleFingerprint(file, size);
      return FileFingerprint(
        hash: sampled,
        textHash: null,
        sampled: true,
        isText: false,
      );
    }

    final raw = XxHash64();
    final text = isText ? XxHash64() : null;
    final normalizer = isText ? LineEndingNormalizer() : null;

    raw.add(probe);
    if (text != null) {
      final normalized = normalizer!.add(probe);
      if (normalized.isNotEmpty) text.add(normalized);
    }

    while (true) {
      final chunk = await file.read(128 * 1024);
      if (chunk.isEmpty) break;
      raw.add(chunk);
      if (text != null) {
        final normalized = normalizer!.add(chunk);
        if (normalized.isNotEmpty) text.add(normalized);
      }
    }
    if (text != null) {
      final tail = normalizer!.finish();
      if (tail.isNotEmpty) text.add(tail);
    }

    return FileFingerprint(
      hash: 'x64:${XxHash64.hex(raw.digest())}',
      textHash: text == null ? null : 'x64:${XxHash64.hex(text.digest())}',
      sampled: false,
      isText: isText,
    );
  } finally {
    await file.close();
  }
}

Future<String> _sampleFingerprint(RandomAccessFile file, int size) async {
  final hasher = XxHash64();
  hasher.add(utf8.encode('x64s-v1'));
  final header = ByteData(8)..setUint64(0, size, Endian.big);
  hasher.add(header.buffer.asUint8List());

  await _hashRange(file, 0, fingerprintSampleSize, hasher);
  final middleStart = max(0, size ~/ 2 - fingerprintSampleSize ~/ 2);
  await _hashRange(file, middleStart, fingerprintSampleSize, hasher);
  final tailStart = max(0, size - fingerprintSampleSize);
  await _hashRange(file, tailStart, fingerprintSampleSize, hasher);

  return 'x64s:${XxHash64.hex(hasher.digest())}';
}

Future<void> _hashRange(
  RandomAccessFile file,
  int start,
  int length,
  XxHash64 hasher,
) async {
  await file.setPosition(start);
  var remaining = length;
  while (remaining > 0) {
    final bytes = await file.read(remaining);
    if (bytes.isEmpty) break;
    hasher.add(bytes);
    remaining -= bytes.length;
  }
}

/// Streaming xxHash64 (seed 0).
final class XxHash64 {
  XxHash64({int seed = 0})
    : _v1 = (seed + _prime1 + _prime2) & _mask,
      _v2 = (seed + _prime2) & _mask,
      _v3 = seed & _mask,
      _v4 = (seed - _prime1) & _mask;

  static const int _mask = 0xFFFFFFFFFFFFFFFF;
  static const int _prime1 = 0x9E3779B185EBCA87;
  static const int _prime2 = 0xC2B2AE3D27D4EB4F;
  static const int _prime3 = 0x165667B19E3779F9;
  static const int _prime4 = 0x85EBCA77C2B2AE63;
  static const int _prime5 = 0x27D4EB2F165667C5;

  int _v1;
  int _v2;
  int _v3;
  int _v4;
  final List<int> _buffer = List<int>.filled(32, 0);
  int _bufferLength = 0;
  int _totalLength = 0;

  void add(List<int> data) {
    if (data.isEmpty) return;
    _totalLength += data.length;
    var offset = 0;

    if (_bufferLength > 0) {
      final need = 32 - _bufferLength;
      final take = min(need, data.length);
      _buffer.setRange(_bufferLength, _bufferLength + take, data);
      _bufferLength += take;
      offset += take;
      if (_bufferLength == 32) {
        _process(_buffer, 0);
        _bufferLength = 0;
      }
    }

    while (offset + 32 <= data.length) {
      _process(data, offset);
      offset += 32;
    }

    if (offset < data.length) {
      final remaining = data.length - offset;
      _buffer.setRange(0, remaining, data, offset);
      _bufferLength = remaining;
    }
  }

  int digest() {
    var hash = _totalLength >= 32
        ? (_rotl(_v1, 1) + _rotl(_v2, 7) + _rotl(_v3, 12) + _rotl(_v4, 18)) &
              _mask
        : 0;
    if (_totalLength >= 32) {
      hash = _mergeRound(hash, _v1);
      hash = _mergeRound(hash, _v2);
      hash = _mergeRound(hash, _v3);
      hash = _mergeRound(hash, _v4);
    } else {
      hash = _prime5;
    }
    hash = (hash + _totalLength) & _mask;

    var offset = 0;
    while (offset + 8 <= _bufferLength) {
      hash ^= _round(0, _read64(_buffer, offset));
      hash = (_rotl(hash, 27) * _prime1 + _prime4) & _mask;
      offset += 8;
    }
    if (offset + 4 <= _bufferLength) {
      hash ^= (_read32(_buffer, offset) * _prime1) & _mask;
      hash = (_rotl(hash, 23) * _prime2 + _prime3) & _mask;
      offset += 4;
    }
    while (offset < _bufferLength) {
      hash ^= (_buffer[offset] * _prime5) & _mask;
      hash = (_rotl(hash, 11) * _prime1) & _mask;
      offset++;
    }

    hash ^= hash >>> 33;
    hash = (hash * _prime2) & _mask;
    hash ^= hash >>> 29;
    hash = (hash * _prime3) & _mask;
    hash ^= hash >>> 32;
    return hash & _mask;
  }

  static String hex(int value) {
    final buffer = StringBuffer();
    for (var shift = 60; shift >= 0; shift -= 4) {
      buffer.write(((value >>> shift) & 0xF).toRadixString(16));
    }
    return buffer.toString();
  }

  void _process(List<int> data, int offset) {
    _v1 = _round(_v1, _read64(data, offset));
    _v2 = _round(_v2, _read64(data, offset + 8));
    _v3 = _round(_v3, _read64(data, offset + 16));
    _v4 = _round(_v4, _read64(data, offset + 24));
  }

  static int _round(int acc, int input) {
    return (_rotl((acc + (input * _prime2 & _mask)) & _mask, 31) * _prime1) &
        _mask;
  }

  static int _mergeRound(int acc, int value) {
    return ((acc ^ _round(0, value)) * _prime1 + _prime4) & _mask;
  }

  static int _rotl(int value, int bits) {
    return ((value << bits) | (value >>> (64 - bits))) & _mask;
  }

  static int _read64(List<int> bytes, int offset) {
    return (bytes[offset] |
            bytes[offset + 1] << 8 |
            bytes[offset + 2] << 16 |
            bytes[offset + 3] << 24 |
            bytes[offset + 4] << 32 |
            bytes[offset + 5] << 40 |
            bytes[offset + 6] << 48 |
            bytes[offset + 7] << 56) &
        _mask;
  }

  static int _read32(List<int> bytes, int offset) {
    return (bytes[offset] |
            bytes[offset + 1] << 8 |
            bytes[offset + 2] << 16 |
            bytes[offset + 3] << 24) &
        _mask;
  }
}
