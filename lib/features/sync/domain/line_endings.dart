import 'dart:typed_data';

/// Streaming CRLF/CR to LF normalizer.
///
/// Chunks are independent: a CRLF pair split across two chunks is still
/// normalized to a single LF.
final class LineEndingNormalizer {
  var _pendingCr = false;

  /// Normalizes one chunk and returns the bytes to emit.
  List<int> add(List<int> chunk) {
    if (chunk.isEmpty) return const [];
    final out = BytesBuilder(copy: false);
    var index = 0;
    if (_pendingCr) {
      if (chunk.first == 0x0A) index = 1;
      out.addByte(0x0A);
      _pendingCr = false;
    }
    for (; index < chunk.length; index++) {
      final byte = chunk[index];
      if (byte != 0x0D) {
        out.addByte(byte);
        continue;
      }
      if (index + 1 < chunk.length) {
        if (chunk[index + 1] == 0x0A) index++;
        out.addByte(0x0A);
      } else {
        _pendingCr = true;
      }
    }
    return out.takeBytes();
  }

  /// Flushes a trailing lone CR.
  List<int> finish() {
    if (!_pendingCr) return const [];
    _pendingCr = false;
    return const [0x0A];
  }
}
