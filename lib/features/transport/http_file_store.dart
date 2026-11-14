/// [FileStore] implementation against the LAN file server.
library;

import '../sync/data/file_store.dart';
import 'http_transport.dart';
import 'protocol.dart';

final class HttpFileStore implements FileStore {
  HttpFileStore(this._transport);

  final HttpTransport _transport;

  @override
  String get root => _transport.baseUrl;

  HttpTransport get transport => _transport;

  @override
  Future<bool> exists(String relPath) async {
    try {
      await stat(relPath);
      return true;
    } on RemoteException catch (error) {
      if (error.isNotFound) return false;
      rethrow;
    }
  }

  @override
  Future<FileInfo> stat(String relPath) async {
    final json = await _transport.getJson(
      ServerRoute.stat,
      query: {'path': relPath},
    );
    return FileInfo(
      isDirectory: json['kind'] == 'dir',
      size: (json['size'] as num?)?.toInt() ?? 0,
      mtimeMs: (json['mtime'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Stream<List<int>> openRead(String relPath) async* {
    final response = await _transport.getStream(
      ServerRoute.file,
      query: {'path': relPath},
    );
    yield* response;
  }

  @override
  Future<void> writeAtomically(
    String relPath,
    Stream<List<int>> data, {
    required DateTime modified,
  }) async {
    await _transport.putStream(
      ServerRoute.file,
      data,
      query: {
        'path': relPath,
        'mtime': modified.millisecondsSinceEpoch.toString(),
      },
    );
  }

  @override
  Future<void> deleteFile(String relPath) async {
    final status = await _transport.delete(
      ServerRoute.file,
      query: {'path': relPath},
    );
    if (status == 409) {
      throw RemoteException(409, 'Target is a directory: $relPath');
    }
  }

  @override
  Future<void> ensureDirectory(String relPath) async {
    if (relPath.isEmpty || relPath == '.') return;
    await _transport.post(ServerRoute.directory, query: {'path': relPath});
  }

  @override
  Future<bool> deleteDirectoryIfEmpty(String relPath) async {
    final status = await _transport.delete(
      ServerRoute.directory,
      query: {'path': relPath},
    );
    return status == 204;
  }
}
