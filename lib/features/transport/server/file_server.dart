// ignore_for_file: avoid_print

/// HTTP file server used on the Windows side.
///
/// It intentionally exposes only primitive filesystem operations. Planning
/// stays on the client, so the server remains small and stateless.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../../sync/data/file_hash_cache.dart';
import '../../sync/data/file_store.dart';
import '../../sync/data/local_scanner.dart';
import '../../sync/data/snapshot_manager.dart';
import '../../sync/data/snapshot_store.dart';
import '../../sync/domain/ignore_rules.dart';
import '../protocol.dart';

final class FileServerMount {
  FileServerMount({
    required this.name,
    required String root,
    IgnoreRules? ignores,
  }) : root = p.normalize(p.absolute(root)),
       ignores = ignores ?? IgnoreRules.defaults();

  final String name;
  final String root;
  final IgnoreRules ignores;
}

final class FileServer {
  FileServer({
    required Iterable<FileServerMount> mounts,
    this.token = '',
    this.verbose = false,
    this.quiet = false,
    HashCache? hashCache,
  }) : _mounts = {for (final mount in mounts) mount.name: mount},
       _hashCache = hashCache ?? MemoryHashCache();

  final String token;
  final bool verbose;

  /// Suppresses startup messages (used by tests).
  final bool quiet;

  final Map<String, FileServerMount> _mounts;
  final HashCache _hashCache;
  final Random _random = Random.secure();

  HttpServer? _server;

  int get port => _server?.port ?? 0;

  InternetAddress? get address => _server?.address;

  bool get isRunning => _server != null;

  Future<void> start({
    String host = '127.0.0.1',
    int port = defaultFileServerPort,
  }) async {
    if (_server != null) {
      throw StateError('File server is already running.');
    }
    final server = await HttpServer.bind(host, port);
    _server = server;
    server.listen(_handle);

    if (quiet) return;
    print('[file-server] listening on http://$host:${server.port}');
    print('[file-server] protocol v$protocolVersion');
    for (final mount in _mounts.values) {
      final exists = Directory(mount.root).existsSync();
      print(
        '[file-server] mount /${mount.name} -> ${mount.root}'
        '${exists ? '' : ' (missing!)'}',
      );
    }
    if (token.isEmpty) {
      print(
        '[file-server] WARNING: no token configured. '
        'Anyone who can reach this port can read and write the mounts.',
      );
    }
  }

  Future<void> close({bool force = false}) async {
    final server = _server;
    _server = null;
    await server?.close(force: force);
  }

  Future<void> _handle(HttpRequest request) async {
    final watch = Stopwatch()..start();
    var status = 500;
    try {
      status = await _dispatch(request);
    } on _HttpError catch (error) {
      status = error.status;
      await _sendError(request.response, error.status, error.message);
    } catch (error) {
      await _sendError(request.response, 500, error.toString());
    } finally {
      if (verbose) {
        print(
          '[file-server] ${request.method} ${request.uri} -> '
          '$status (${watch.elapsedMilliseconds}ms)',
        );
      }
    }
  }

  Future<int> _dispatch(HttpRequest request) async {
    final segments = request.uri.pathSegments;

    if (segments.length == 1 && segments.first == ServerRoute.health) {
      return _sendJson(request, {'ok': true});
    }
    if (segments.isEmpty) {
      return _sendJson(request, {
        'app': appName,
        'protocol': protocolVersion,
        'mounts': _mounts.keys.toList(growable: false),
      });
    }

    if (!_isAuthorized(request)) {
      throw const _HttpError(401, 'Unauthorized');
    }

    final mount = _mounts[segments.first];
    if (mount == null) {
      throw const _HttpError(404, 'Mount not found');
    }

    final operation = segments.length > 1 ? segments[1] : '';
    final relPath = request.uri.queryParameters['path'] ?? '';

    switch (operation) {
      case '':
        _requireMethod(request, 'GET');
        return _sendJson(request, {
          'name': mount.name,
          'protocol': protocolVersion,
          'platform': Platform.operatingSystem,
          'root': mount.root,
        });
      case ServerRoute.manifest:
        _requireMethod(request, 'GET');
        return _manifest(request, mount, relPath);
      case ServerRoute.snapshot:
        _requireMethod(request, 'POST');
        return _snapshot(request, mount, relPath);
      case ServerRoute.file:
        return _file(request, mount, relPath);
      case ServerRoute.directory:
        return _directory(request, mount, relPath);
      case ServerRoute.stat:
        _requireMethod(request, 'GET');
        return _stat(request, mount, relPath);
      default:
        throw const _HttpError(404, 'Unknown operation');
    }
  }

  Future<int> _snapshot(
    HttpRequest request,
    FileServerMount mount,
    String relPath,
  ) async {
    await _resolve(mount, relPath, rejectLinks: true);
    final mode = request.uri.queryParameters['mode'] ?? 'refresh';
    final manager = LocalSnapshotManager(
      root: mount.root,
      store: SnapshotStore(LocalFileStore(mount.root)),
      ignores: mount.ignores,
      hashCache: _hashCache,
    );
    try {
      final snapshot = await manager.scan(
        subPath: relPath.isEmpty ? null : relPath,
        createIfMissing: mode == 'init',
      );
      return await _sendJson(request, snapshot.toJson());
    } on SnapshotLegacyException {
      throw const _HttpError(
        409,
        'Legacy snapshot must be migrated by the client',
      );
    } on SnapshotMissingException {
      throw const _HttpError(409, 'Snapshot missing');
    } on SnapshotPathException catch (error) {
      throw _HttpError(404, error.message);
    }
  }

  Future<int> _manifest(
    HttpRequest request,
    FileServerMount mount,
    String relPath,
  ) async {
    final absPath = await _resolve(mount, relPath, rejectLinks: true);
    final scanner = LocalScanner(ignores: mount.ignores, hashCache: _hashCache);
    final manifest = await scanner.scan(absPath);
    final json = manifest.toJson();
    json['root'] = mount.name;
    json['protocol'] = protocolVersion;
    if (relPath.isNotEmpty) {
      json['path'] = relPath;
    }
    return _sendJson(request, json);
  }

  Future<int> _file(
    HttpRequest request,
    FileServerMount mount,
    String relPath,
  ) async {
    final absPath = await _resolve(mount, relPath, rejectLinks: true);
    switch (request.method) {
      case 'GET':
        return _download(request, absPath, relPath);
      case 'PUT':
        return _upload(request, absPath, relPath);
      case 'DELETE':
        final file = File(absPath);
        if (!await file.exists()) {
          return _sendStatus(request, 204);
        }
        if (await FileSystemEntity.isDirectory(absPath)) {
          throw const _HttpError(409, 'Target is a directory');
        }
        await file.delete();
        _invalidateHash(absPath);
        return _sendStatus(request, 204);
      default:
        throw const _HttpError(405, 'Method not allowed');
    }
  }

  Future<int> _download(
    HttpRequest request,
    String absPath,
    String relPath,
  ) async {
    final file = File(absPath);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw _HttpError(404, 'File not found: $relPath');
    }

    final response = request.response;
    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (range != null && range.startsWith('bytes=')) {
      final spec = range.substring('bytes='.length).split('-');
      final start = int.tryParse(spec.first) ?? 0;
      final requestedEnd = spec.length > 1 && spec[1].isNotEmpty
          ? int.tryParse(spec[1])
          : null;
      if (start < 0 || start >= stat.size) {
        throw const _HttpError(416, 'Range not satisfiable');
      }
      final end = min(requestedEnd ?? stat.size - 1, stat.size - 1);
      if (end < start) {
        throw const _HttpError(416, 'Range not satisfiable');
      }
      response.statusCode = 206;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/${stat.size}',
      );
      response.contentLength = end - start + 1;
      await response.addStream(file.openRead(start, end + 1));
    } else {
      response.statusCode = 200;
      response.contentLength = stat.size;
      await response.addStream(file.openRead());
    }
    await response.close();
    return response.statusCode;
  }

  Future<int> _upload(
    HttpRequest request,
    String absPath,
    String relPath,
  ) async {
    final target = File(absPath);
    final parent = Directory(p.dirname(absPath));
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final temp = File(
      p.join(
        parent.path,
        '.${p.basename(absPath)}.fs-upload-'
        '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}'
        '.tmp',
      ),
    );

    try {
      final sink = temp.openWrite();
      try {
        await sink.addStream(request);
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (await target.exists()) {
        // Windows cannot rename over an existing file.
        await target.delete();
      }
      await temp.rename(absPath);

      final mtimeMs =
          int.tryParse(request.uri.queryParameters['mtime'] ?? '') ??
          DateTime.now().millisecondsSinceEpoch;
      await target.setLastModified(
        DateTime.fromMillisecondsSinceEpoch(mtimeMs),
      );
      _invalidateHash(absPath);

      final stat = await target.stat();
      return await _sendJson(request, {
        'path': relPath,
        'size': stat.size,
        'mtime': stat.modified.millisecondsSinceEpoch,
      });
    } finally {
      if (await temp.exists()) {
        await temp.delete();
      }
    }
  }

  Future<int> _directory(
    HttpRequest request,
    FileServerMount mount,
    String relPath,
  ) async {
    final absPath = await _resolve(mount, relPath, rejectLinks: true);
    switch (request.method) {
      case 'POST':
        await Directory(absPath).create(recursive: true);
        return _sendStatus(request, 204);
      case 'DELETE':
        final directory = Directory(absPath);
        if (!await directory.exists()) {
          return _sendStatus(request, 204);
        }
        if (await FileSystemEntity.isFile(absPath)) {
          throw const _HttpError(409, 'Target is a file');
        }
        final isEmpty = await directory.list(followLinks: false).isEmpty;
        if (!isEmpty) {
          throw const _HttpError(409, 'Directory is not empty');
        }
        await directory.delete();
        _invalidateHash(absPath, subtree: true);
        return _sendStatus(request, 204);
      default:
        throw const _HttpError(405, 'Method not allowed');
    }
  }

  Future<int> _stat(
    HttpRequest request,
    FileServerMount mount,
    String relPath,
  ) async {
    final absPath = await _resolve(mount, relPath, rejectLinks: false);
    final type = await FileSystemEntity.type(absPath, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw const _HttpError(404, 'Path not found');
    }
    if (type == FileSystemEntityType.link) {
      throw const _HttpError(403, 'Symbolic links are not supported');
    }
    final stat = await FileStat.stat(absPath);
    return _sendJson(request, {
      'path': relPath,
      'kind': stat.type == FileSystemEntityType.directory ? 'dir' : 'file',
      'size': stat.size,
      'mtime': stat.modified.millisecondsSinceEpoch,
    });
  }

  Future<String> _resolve(
    FileServerMount mount,
    String relPath, {
    required bool rejectLinks,
  }) async {
    if (relPath.contains('\\')) {
      throw const _HttpError(400, 'Backslashes are not allowed in paths');
    }
    if (relPath.startsWith('/')) {
      throw const _HttpError(400, 'Path must be relative');
    }

    final segments = relPath.isEmpty ? const <String>[] : relPath.split('/');
    for (final segment in segments) {
      if (segment.isEmpty ||
          segment == '.' ||
          segment == '..' ||
          segment.contains(':')) {
        throw const _HttpError(400, 'Invalid path');
      }
    }

    final absPath = segments.isEmpty
        ? mount.root
        : p.normalize(p.joinAll([mount.root, ...segments]));
    if (absPath != mount.root && !p.isWithin(mount.root, absPath)) {
      throw const _HttpError(403, 'Path escapes the mount root');
    }

    if (rejectLinks) {
      final type = await FileSystemEntity.type(absPath, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw const _HttpError(403, 'Symbolic links are not supported');
      }
    }
    return absPath;
  }

  bool _isAuthorized(HttpRequest request) {
    if (token.isEmpty) return true;
    return request.headers.value(tokenHeader) == token;
  }

  void _invalidateHash(String absPath, {bool subtree = false}) {
    if (!subtree) {
      _hashCache.remove(absPath);
      return;
    }
    final prefix = '$absPath${Platform.pathSeparator}';
    _hashCache.removeWhere((key) => key == absPath || key.startsWith(prefix));
  }

  static void _requireMethod(HttpRequest request, String method) {
    if (request.method != method) {
      throw const _HttpError(405, 'Method not allowed');
    }
  }

  Future<int> _sendJson(
    HttpRequest request,
    Map<String, Object?> data, {
    int status = 200,
  }) async {
    final response = request.response;
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(data));
    await response.close();
    return status;
  }

  Future<int> _sendStatus(HttpRequest request, int status) async {
    request.response.statusCode = status;
    await request.response.close();
    return status;
  }

  Future<void> _sendError(
    HttpResponse response,
    int status,
    String message,
  ) async {
    try {
      response.statusCode = status;
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode({'error': message}));
      await response.close();
    } catch (_) {
      // The response may already be closed or the client may have gone away.
    }
  }
}

final class _HttpError implements Exception {
  const _HttpError(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => 'HTTP $status: $message';
}
