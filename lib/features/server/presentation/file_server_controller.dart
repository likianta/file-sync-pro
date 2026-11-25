import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../sync/data/file_hash_cache.dart';
import '../../sync/domain/ignore_rules.dart';
import '../../transport/server/file_server.dart';
import '../../transport/server/file_server_config.dart';

enum FileServerStatus { stopped, running, error }

final class FileServerController extends ChangeNotifier {
  FileServerController({required this.configPath, required this.projectRoot});

  final String configPath;
  final String projectRoot;

  late FileServerConfig config;
  FileServer? _server;
  FileHashCache? _hashCache;
  FileServerStatus _status = FileServerStatus.stopped;
  String? _errorMessage;
  List<String> _addresses = const [];
  String? _selectedIp;
  bool _loaded = false;
  bool _disposed = false;

  bool get loaded => _loaded;

  FileServerStatus get status => _status;

  bool get isRunning => _server != null;

  String? get errorMessage => _errorMessage;

  List<String> get addresses => List.unmodifiable(_addresses);

  String? get selectedIp => _selectedIp;

  String get statusLabel {
    if (_status == FileServerStatus.running) {
      return 'Serving on 0.0.0.0:${config.port}';
    }
    if (_status == FileServerStatus.error) return 'Error';
    return 'Stopped';
  }

  Future<void> load() async {
    config = FileServerConfig.load(path: configPath, projectRoot: projectRoot);
    if (config.mounts.isEmpty) {
      final defaultPath = p.normalize(p.join(projectRoot, '..', 'photolens'));
      if (Directory(defaultPath).existsSync()) {
        config.mounts.add(
          FileServerMountConfig(name: 'photolens', path: defaultPath),
        );
      }
    }
    await refreshAddresses();
    _loaded = true;
    _notify();
  }

  Future<void> refreshAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: true,
      );
      final addresses = <String>[
        for (final interface in interfaces)
          for (final address in interface.addresses) address.address,
      ];
      _addresses = addresses.toSet().toList(growable: false);
      if (_addresses.isEmpty) {
        _selectedIp = null;
      } else if (_selectedIp == null || !_addresses.contains(_selectedIp)) {
        _selectedIp = _addresses.firstWhere(
          (address) => address != '127.0.0.1',
          orElse: () => _addresses.first,
        );
      }
    } catch (_) {
      _addresses = const [];
      _selectedIp = null;
    }
  }

  void selectAddress(String address) {
    _selectedIp = address;
    _notify();
  }

  void updateToken(String token) {
    config.token = token;
    _notify();
  }

  void updatePort(int port) {
    config.port = port;
    _notify();
  }

  void setAllowAnonymous(bool value) {
    config.allowAnonymous = value;
    _notify();
  }

  /// Adds a mount with the given name and path.
  ///
  /// Returns an error message when the name is already taken.
  Future<String?> addMount({required String name, required String path}) async {
    if (config.mounts.any((mount) => mount.name == name)) {
      return 'A folder named "$name" already exists.';
    }
    config.mounts.add(FileServerMountConfig(name: name, path: path));
    await save();
    _notify();
    return null;
  }

  /// Orders the shared folders by name and persists the new order.
  Future<void> sortMountsByName() async {
    if (config.mounts.length < 2) return;
    config.mounts.sort(
      (x, y) => x.name.toLowerCase().compareTo(y.name.toLowerCase()),
    );
    await save();
    _notify();
  }

  Future<void> renameMount(int index, String name) async {
    if (index < 0 || index >= config.mounts.length) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    config.mounts[index] = config.mounts[index].copyWith(name: trimmed);
    await save();
    _notify();
  }

  Future<void> updateMountPath(int index, String path) async {
    if (index < 0 || index >= config.mounts.length) return;
    config.mounts[index] = config.mounts[index].copyWith(path: path);
    await save();
    _notify();
  }

  Future<void> removeMount(int index) async {
    if (index < 0 || index >= config.mounts.length) return;
    config.mounts.removeAt(index);
    await save();
    _notify();
  }

  Future<void> save() async {
    config.host = '0.0.0.0';
    await config.save(path: configPath);
  }

  Future<void> start() async {
    if (_server != null) return;
    _errorMessage = null;

    if (config.token.trim().isEmpty && !config.allowAnonymous) {
      _status = FileServerStatus.error;
      _errorMessage = 'A token is required.';
      _notify();
      return;
    }
    final validMounts = config.mounts
        .where((mount) => mount.name.trim().isNotEmpty && mount.path.isNotEmpty)
        .toList();
    if (validMounts.isEmpty) {
      _status = FileServerStatus.error;
      _errorMessage = 'Add at least one folder to share.';
      _notify();
      return;
    }

    final ignores = IgnoreRules.defaults(extra: config.extraIgnores);
    final hashCache = _hashCache ??= FileHashCache(
      p.join(p.dirname(configPath), 'file_server.hash_cache.json'),
    );
    final server = FileServer(
      mounts: [
        for (final mount in validMounts)
          FileServerMount(
            name: mount.name.trim(),
            root: mount.path,
            ignores: ignores,
          ),
      ],
      token: config.token.trim(),
      quiet: true,
      hashCache: hashCache,
    );

    try {
      await server.start(host: '0.0.0.0', port: config.port);
      _server = server;
      _status = FileServerStatus.running;
      await save();
    } on SocketException catch (error) {
      _status = FileServerStatus.error;
      _errorMessage = 'Cannot bind 0.0.0.0:${config.port}: ${error.message}';
    } catch (error) {
      _status = FileServerStatus.error;
      _errorMessage = error.toString();
    }
    _notify();
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _status = FileServerStatus.stopped;
    await server?.close(force: true);
    _notify();
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    if (_status == FileServerStatus.error) {
      _status = FileServerStatus.stopped;
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final server = _server;
    _server = null;
    server?.close(force: true);
    super.dispose();
  }
}
