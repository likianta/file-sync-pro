/// Persistent settings for the desktop file-server page.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

final class FileServerMountConfig {
  const FileServerMountConfig({required this.name, required this.path});

  final String name;
  final String path;

  FileServerMountConfig copyWith({String? name, String? path}) {
    return FileServerMountConfig(
      name: name ?? this.name,
      path: path ?? this.path,
    );
  }
}

final class FileServerConfig {
  FileServerConfig({
    this.host = '127.0.0.1',
    this.port = 2160,
    this.token = '',
    this.allowAnonymous = false,
    List<FileServerMountConfig> mounts = const [],
    List<String> extraIgnores = const [],
  }) : mounts = List.of(mounts),
       extraIgnores = List.of(extraIgnores);

  String host;
  int port;
  String token;
  bool allowAnonymous;
  final List<FileServerMountConfig> mounts;
  final List<String> extraIgnores;

  static FileServerConfig load({
    required String path,
    required String projectRoot,
  }) {
    final file = File(path);
    if (!file.existsSync()) {
      return FileServerConfig();
    }
    final text = file.readAsStringSync();
    if (text.trim().isEmpty) return FileServerConfig();

    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw FormatException('Config must be a JSON object: $path');
    }
    final json = decoded.cast<String, Object?>();

    final mounts = <FileServerMountConfig>[];
    final rawMounts = json['mounts'];
    if (rawMounts is Map) {
      for (final entry in rawMounts.entries) {
        final rawPath = entry.value as String;
        mounts.add(
          FileServerMountConfig(
            name: entry.key as String,
            path: _resolve(projectRoot, rawPath),
          ),
        );
      }
    }

    final ignores = json['ignores'];
    return FileServerConfig(
      host: json['host'] as String? ?? '127.0.0.1',
      port: (json['port'] as num?)?.toInt() ?? 2160,
      token: json['token'] as String? ?? '',
      allowAnonymous: json['allowAnonymous'] as bool? ?? false,
      mounts: mounts,
      extraIgnores: ignores is List
          ? ignores.whereType<String>().toList(growable: false)
          : const [],
    );
  }

  Future<void> save({required String path}) async {
    final file = File(path);
    final parent = Directory(p.dirname(file.path));
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final data = <String, Object?>{
      'host': host,
      'port': port,
      'token': token,
      'allowAnonymous': allowAnonymous,
      'mounts': {for (final mount in mounts) mount.name: mount.path},
      if (extraIgnores.isNotEmpty) 'ignores': extraIgnores,
    };

    final temp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
        flush: true,
      );
      try {
        await temp.rename(file.path);
      } on FileSystemException {
        if (await file.exists()) {
          await file.delete();
        }
        await temp.rename(file.path);
      }
    } finally {
      if (await temp.exists()) {
        await temp.delete();
      }
    }
  }

  static String _resolve(String projectRoot, String path) {
    return p.normalize(p.isAbsolute(path) ? path : p.join(projectRoot, path));
  }
}
