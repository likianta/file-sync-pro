/// Append-only journal for a sync session.
///
/// The journal is diagnostic today (it records completed actions and errors);
/// the recovery flow will build on the same file format later.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

final class SyncJournal {
  SyncJournal._(this.path, this._sink);

  final String path;
  final IOSink _sink;

  static Future<SyncJournal> create(String directory) async {
    final dir = Directory(directory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp('[:.]'),
      '-',
    );
    final file = File(p.join(dir.path, '$stamp.jsonl'));
    return SyncJournal._(file.path, file.openWrite(mode: FileMode.append));
  }

  void record(String event, {String? path, Map<String, Object?>? data}) {
    final entry = <String, Object?>{
      'ts': DateTime.now().toUtc().toIso8601String(),
      'event': event,
    };
    if (path != null) entry['path'] = path;
    if (data != null) entry['data'] = data;
    _sink.writeln(jsonEncode(entry));
  }

  Future<void> close() async {
    await _sink.flush();
    await _sink.close();
  }
}
