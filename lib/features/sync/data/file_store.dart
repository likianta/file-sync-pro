/// Filesystem operations used by the sync applier.
///
/// The same interface will later be implemented by a remote store speaking the
/// LAN protocol; keeping it free of local-only assumptions is intentional.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

final class FileInfo {
  const FileInfo({
    required this.isDirectory,
    required this.size,
    required this.mtimeMs,
  });

  final bool isDirectory;
  final int size;
  final int mtimeMs;
}

abstract interface class FileStore {
  String get root;

  Future<bool> exists(String relPath);

  Future<FileInfo> stat(String relPath);

  Stream<List<int>> openRead(String relPath);

  Future<void> writeAtomically(
    String relPath,
    Stream<List<int>> data, {
    required DateTime modified,
  });

  Future<void> deleteFile(String relPath);

  Future<void> ensureDirectory(String relPath);

  /// Returns true when the directory existed and was removed.
  Future<bool> deleteDirectoryIfEmpty(String relPath);
}

final class LocalFileStore implements FileStore {
  LocalFileStore(String root) : root = p.normalize(p.absolute(root));

  @override
  final String root;

  @override
  Future<bool> exists(String relPath) async {
    return await FileSystemEntity.type(_abs(relPath)) !=
        FileSystemEntityType.notFound;
  }

  @override
  Future<FileInfo> stat(String relPath) async {
    final stat = await FileStat.stat(_abs(relPath));
    if (stat.type == FileSystemEntityType.notFound) {
      throw FileSystemException('Path not found', _abs(relPath));
    }
    return FileInfo(
      isDirectory: stat.type == FileSystemEntityType.directory,
      size: stat.size,
      mtimeMs: stat.modified.millisecondsSinceEpoch,
    );
  }

  @override
  Stream<List<int>> openRead(String relPath) => File(_abs(relPath)).openRead();

  @override
  Future<void> writeAtomically(
    String relPath,
    Stream<List<int>> data, {
    required DateTime modified,
  }) async {
    final targetPath = _abs(relPath);
    final parent = Directory(p.dirname(targetPath));
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final temp = File(
      p.join(
        parent.path,
        '.${p.basename(targetPath)}.filesync-'
        '${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );

    try {
      final sink = temp.openWrite();
      try {
        await sink.addStream(data);
        await sink.flush();
      } finally {
        await sink.close();
      }

      final target = File(targetPath);
      try {
        await temp.rename(targetPath);
      } on FileSystemException {
        // Windows does not replace an existing file on rename.
        if (await target.exists()) {
          await target.delete();
        }
        await temp.rename(targetPath);
      }
      await target.setLastModified(modified);
    } finally {
      if (await temp.exists()) {
        await temp.delete();
      }
    }
  }

  @override
  Future<void> deleteFile(String relPath) async {
    final file = File(_abs(relPath));
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<void> ensureDirectory(String relPath) async {
    if (relPath.isEmpty || relPath == '.') return;
    final dir = Directory(_abs(relPath));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  @override
  Future<bool> deleteDirectoryIfEmpty(String relPath) async {
    final dir = Directory(_abs(relPath));
    if (!await dir.exists()) return false;
    final isEmpty = await dir.list(followLinks: false).isEmpty;
    if (!isEmpty) return false;
    await dir.delete();
    return true;
  }

  String _abs(String relPath) {
    if (relPath.isEmpty || relPath == '.') return root;
    return p.joinAll([root, ...relPath.split('/')]);
  }
}
