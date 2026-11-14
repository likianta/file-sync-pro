/// A sync participant: a local folder or a remote mount.
library;

import 'package:path/path.dart' as p;

import '../../transport/http_file_store.dart';
import '../../transport/http_transport.dart';
import '../../transport/remote_scanner.dart';
import '../data/file_store.dart';
import '../data/local_scanner.dart';
import '../domain/ignore_rules.dart';
import '../domain/manifest.dart';

abstract interface class SyncSource {
  /// Stable identity used to validate the saved base manifest.
  String get id;

  FileStore get store;

  Future<Manifest> scan();

  Future<void> close();
}

final class LocalSyncSource implements SyncSource {
  LocalSyncSource(
    String root, {
    IgnoreRules? ignores,
    bool computeHashes = true,
    HashCache? hashCache,
  }) : id = p.normalize(p.absolute(root)),
       _store = LocalFileStore(root),
       _scanner = LocalScanner(
         ignores: ignores,
         computeHashes: computeHashes,
         hashCache: hashCache,
       );

  @override
  final String id;

  final LocalFileStore _store;
  final LocalScanner _scanner;

  @override
  FileStore get store => _store;

  @override
  Future<Manifest> scan() => _scanner.scan(id);

  @override
  Future<void> close() async {}
}

final class RemoteSyncSource implements SyncSource {
  RemoteSyncSource({
    required String baseUrl,
    String token = '',
    IgnoreRules? ignores,
    Duration timeout = const Duration(minutes: 5),
  }) : _transport = HttpTransport(
         baseUrl: baseUrl,
         token: token,
         timeout: timeout,
       ),
       _ignores = ignores ?? IgnoreRules.defaults() {
    _store = HttpFileStore(_transport);
    _scanner = RemoteScanner(transport: _transport, ignores: _ignores);
  }

  final HttpTransport _transport;
  final IgnoreRules _ignores;
  late final HttpFileStore _store;
  late final RemoteScanner _scanner;

  @override
  String get id => _transport.baseUrl;

  @override
  FileStore get store => _store;

  HttpTransport get transport => _transport;

  @override
  Future<Manifest> scan() => _scanner.scan();

  @override
  Future<void> close() async {
    await _transport.close();
  }
}
