/// Multi-pair client configuration.
///
/// Version 4 layout:
/// {
///   "version": 4,
///   "token": "...",
///   "timeoutSeconds": 300,
///   "devices": [
///     {
///       "id": "d-...",
///       "name": "OnePlus 11",
///       "type": "android",
///       "model": "androidPhone",
///       "host_type": "remote",
///       "host": "192.168.71.52",
///       "port": 2160,
///       "pairs": [
///         {
///           "id": "p-...",
///           "name": "gitbook",
///           "local_root": "/Users/Likianta/Desktop/documents/gitbook",
///           "remote_root": "/gitbook"
///         }
///       ]
///     }
///   ]
/// }
///
/// Version 3 files (devices plus a separate top-level "pairs" list) are
/// migrated in memory and written back in the new shape on the next save.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'sync_pair_config.dart';

enum SyncDeviceType {
  windows,
  macos,
  linux,
  android,
  ios,
  ipad;

  static SyncDeviceType parse(Object? value) {
    return switch (value) {
      'macos' => SyncDeviceType.macos,
      'linux' => SyncDeviceType.linux,
      'android' => SyncDeviceType.android,
      'ios' => SyncDeviceType.ios,
      'ipad' => SyncDeviceType.ipad,
      _ => SyncDeviceType.windows,
    };
  }

  String get id => name;

  String get label => switch (this) {
    SyncDeviceType.windows => 'Windows',
    SyncDeviceType.macos => 'macOS',
    SyncDeviceType.linux => 'Linux',
    SyncDeviceType.android => 'Android',
    SyncDeviceType.ios => 'iOS',
    SyncDeviceType.ipad => 'iPadOS',
  };
}

/// Physical device form factor used for the 3D illustration.
enum SyncDeviceModel {
  macbook,
  windowsLaptop,
  linuxDesktop,
  iphone,
  androidPhone;

  static SyncDeviceModel parse(Object? value) {
    return switch (value) {
      'macbook' => SyncDeviceModel.macbook,
      'windowsLaptop' || 'windowsDesktop' => SyncDeviceModel.windowsLaptop,
      'linuxDesktop' => SyncDeviceModel.linuxDesktop,
      'iphone' || 'ipad' => SyncDeviceModel.iphone,
      'androidPhone' => SyncDeviceModel.androidPhone,
      _ => SyncDeviceModel.windowsLaptop,
    };
  }

  static SyncDeviceModel fallbackOf(SyncDeviceType type) {
    return switch (type) {
      SyncDeviceType.windows => SyncDeviceModel.windowsLaptop,
      SyncDeviceType.macos => SyncDeviceModel.macbook,
      SyncDeviceType.linux => SyncDeviceModel.linuxDesktop,
      SyncDeviceType.android => SyncDeviceModel.androidPhone,
      SyncDeviceType.ios || SyncDeviceType.ipad => SyncDeviceModel.iphone,
    };
  }

  String get id => name;

  String get label => switch (this) {
    SyncDeviceModel.macbook => 'macOS',
    SyncDeviceModel.windowsLaptop => 'Windows',
    SyncDeviceModel.linuxDesktop => 'Linux',
    SyncDeviceModel.iphone => 'iOS & iPadOS',
    SyncDeviceModel.androidPhone => 'Android',
  };
}

enum SyncHostType {
  local,
  remote;

  static SyncHostType parse(Object? value) {
    return value == 'local' ? SyncHostType.local : SyncHostType.remote;
  }

  String get id => name;
}

/// A peer device that exposes one or more file-server mounts.
final class SyncDeviceEntry {
  SyncDeviceEntry({
    required this.id,
    required this.name,
    this.type = SyncDeviceType.windows,
    this.model,
    this.hostType = SyncHostType.remote,
    this.host = '',
    this.port = defaultPort,
    List<SyncPairEntry> pairs = const [],
  }) : pairs = List.of(pairs);

  static const defaultPort = 2160;

  /// Unique and immutable. Format: `d-<[a-z0-9]+>`.
  final String id;
  final String name;
  final SyncDeviceType type;
  final SyncDeviceModel? model;
  final SyncHostType hostType;
  final String host;
  final int port;
  final List<SyncPairEntry> pairs;

  SyncDeviceModel get resolvedModel =>
      model ?? SyncDeviceModel.fallbackOf(type);

  bool get isLocal => hostType == SyncHostType.local;

  /// The host used to build URLs. Local devices always talk to loopback.
  String get resolvedHost =>
      isLocal || host.trim().isEmpty ? '127.0.0.1' : host.trim();

  String get authority => '$resolvedHost:$port';

  String get baseUrl => 'http://$authority';

  SyncDeviceEntry copyWith({
    String? id,
    String? name,
    SyncDeviceType? type,
    SyncDeviceModel? model,
    bool clearModel = false,
    SyncHostType? hostType,
    String? host,
    int? port,
    List<SyncPairEntry>? pairs,
  }) {
    return SyncDeviceEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      model: clearModel ? null : (model ?? this.model),
      hostType: hostType ?? this.hostType,
      host: host ?? this.host,
      port: port ?? this.port,
      pairs: pairs ?? this.pairs,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.id,
      if (model != null) 'model': model!.id,
      'host_type': hostType.id,
      'host': host,
      'port': port,
      'pairs': [for (final pair in pairs) pair.toJson()],
    };
  }

  factory SyncDeviceEntry.fromJson(
    Map<String, Object?> json, {
    required String projectRoot,
  }) {
    final host = json['host'] as String? ?? '';
    final port = (json['port'] as num?)?.toInt() ?? defaultPort;
    final rawId = json['id'] as String?;
    final id = SyncClientConfig._validDeviceId(rawId)
        ? rawId!
        : SyncClientConfig.newDeviceId(seed: rawId ?? '$host-$port');
    final rawPairs = json['pairs'];
    final pairs = <SyncPairEntry>[];
    if (rawPairs is List) {
      for (final raw in rawPairs) {
        if (raw is! Map) continue;
        pairs.add(
          SyncPairEntry.fromJson(
            raw.cast<String, Object?>(),
            deviceId: id,
            projectRoot: projectRoot,
          ),
        );
      }
    }
    return SyncDeviceEntry(
      id: id,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : (host.isEmpty ? 'Device' : host),
      type: SyncDeviceType.parse(json['type']),
      model: json['model'] == null
          ? null
          : SyncDeviceModel.parse(json['model']),
      hostType: SyncHostType.parse(json['host_type'] ?? json['hostType']),
      host: host,
      port: port,
      pairs: pairs,
    );
  }
}

final class SyncPairEntry {
  SyncPairEntry({
    required this.id,
    required this.name,
    required this.localRoot,
    required this.remoteRoot,
    this.deviceId = '',
    String? stateDir,
  }) : stateDir = stateDir ?? '';

  /// Unique and immutable. Format: `p-<[a-z0-9]+>`.
  final String id;
  final String name;
  final String localRoot;

  /// Mount path on the peer, for example `/gitbook`.
  final String remoteRoot;

  /// The [SyncDeviceEntry.id] this pair belongs to.
  final String deviceId;

  /// Runtime-only state folder; never serialized.
  final String stateDir;

  SyncPairEntry copyWith({
    String? id,
    String? name,
    String? localRoot,
    String? remoteRoot,
    String? deviceId,
    String? stateDir,
  }) {
    return SyncPairEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      localRoot: localRoot ?? this.localRoot,
      remoteRoot: remoteRoot ?? this.remoteRoot,
      deviceId: deviceId ?? this.deviceId,
      stateDir: stateDir ?? this.stateDir,
    );
  }

  String remoteUrlFor(SyncDeviceEntry device) {
    final root = remoteRoot.startsWith('/') ? remoteRoot : '/$remoteRoot';
    return '${device.baseUrl}$root';
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'local_root': localRoot,
      'remote_root': remoteRoot,
    };
  }

  factory SyncPairEntry.fromJson(
    Map<String, Object?> json, {
    required String deviceId,
    required String projectRoot,
  }) {
    final rawId = json['id'] as String?;
    final name = (json['name'] as String?)?.trim().isNotEmpty == true
        ? (json['name'] as String).trim()
        : 'pair';
    final id = SyncClientConfig._validPairId(rawId)
        ? rawId!
        : SyncClientConfig.newPairId(seed: name);
    final remoteRoot = SyncClientConfig._normalizeRemoteRoot(
      json['remote_root'] as String? ?? json['remoteRoot'] as String? ?? '/',
    );
    final localRoot = SyncClientConfig._resolve(
      projectRoot,
      SyncClientConfig._expandUser(
        json['local_root'] as String? ??
            json['localRoot'] as String? ??
            p.join(projectRoot, '..', 'photolens'),
      ),
    );
    final rawState = json['stateDir'] as String?;
    return SyncPairEntry(
      id: id,
      name: name,
      localRoot: localRoot,
      remoteRoot: remoteRoot,
      deviceId: deviceId,
      stateDir: rawState == null || rawState.trim().isEmpty
          ? p.join(projectRoot, 'data', 'sync_pairs', id)
          : SyncClientConfig._resolve(
              projectRoot,
              SyncClientConfig._expandUser(rawState),
            ),
    );
  }
}

final class SyncClientConfig {
  SyncClientConfig({
    required this.token,
    required this.timeoutSeconds,
    required List<SyncDeviceEntry> devices,
  }) : devices = List.of(devices);

  String token;
  int timeoutSeconds;
  final List<SyncDeviceEntry> devices;

  static const schemaVersion = 4;

  static SyncClientConfig load({
    required String path,
    required String projectRoot,
  }) {
    final file = File(path);
    if (!file.existsSync()) return empty();

    final text = file.readAsStringSync();
    if (text.trim().isEmpty) return empty();

    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw FormatException('Config must be a JSON object: $path');
    }
    final json = decoded.cast<String, Object?>();
    final token =
        Platform.environment['FILE_SYNC_TOKEN'] ??
        json['token'] as String? ??
        '';
    final timeoutSeconds = (json['timeoutSeconds'] as num?)?.toInt() ?? 300;

    final devices = <SyncDeviceEntry>[];
    final seenDeviceIds = <String>{};
    final legacyDevicesById = <String, SyncDeviceEntry>{};
    final rawDevices = json['devices'];
    if (rawDevices is List) {
      for (final raw in rawDevices) {
        if (raw is! Map) continue;
        final map = raw.cast<String, Object?>();
        final oldId = map['id'] as String?;
        final device = SyncDeviceEntry.fromJson(map, projectRoot: projectRoot);
        if (oldId != null && oldId.isNotEmpty) {
          legacyDevicesById[oldId] = device;
        }
        if (seenDeviceIds.add(device.id)) {
          devices.add(device);
        }
      }
    }

    // Version 3 kept pairs in a separate top-level list. Move them under their
    // devices and drop the old list on the next save.
    final rawPairs = json['pairs'];
    if (rawPairs is List) {
      for (final raw in rawPairs) {
        if (raw is! Map) continue;
        final pairJson = raw.cast<String, Object?>();
        final oldDeviceId = pairJson['deviceId'] as String? ?? '';
        var device = legacyDevicesById[oldDeviceId];
        device ??= _deviceFromLegacyPair(pairJson);
        if (device == null) continue;
        if (!devices.contains(device)) devices.add(device);
        final pair = _pairFromLegacy(pairJson, device, projectRoot);
        if (pair == null) continue;
        device.pairs.removeWhere(
          (item) => item.id == pair.id || item.name == pair.name,
        );
        device.pairs.add(pair);
      }
    }

    _ensurePairState(devices, projectRoot);
    return SyncClientConfig(
      token: token,
      timeoutSeconds: timeoutSeconds,
      devices: devices,
    );
  }

  static SyncClientConfig empty() {
    return SyncClientConfig(
      token: Platform.environment['FILE_SYNC_TOKEN'] ?? '',
      timeoutSeconds: 300,
      devices: const [],
    );
  }

  /// Every pair across all devices, flattened for runtime lookups.
  List<SyncPairEntry> get pairs => [
    for (final device in devices) ...device.pairs,
  ];

  SyncDeviceEntry? deviceById(String id) {
    for (final device in devices) {
      if (device.id == id) return device;
    }
    return null;
  }

  SyncDeviceEntry? deviceForPair(SyncPairEntry pair) {
    return deviceById(pair.deviceId);
  }

  List<SyncPairEntry> pairsForDevice(String deviceId) {
    return deviceById(deviceId)?.pairs ?? const [];
  }

  Future<void> save({required String path}) async {
    final file = File(path);
    final parent = Directory(p.dirname(file.path));
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final data = <String, Object?>{
      'version': schemaVersion,
      'token': token,
      'timeoutSeconds': timeoutSeconds,
      'devices': [for (final device in devices) device.toJson()],
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

  SyncPairConfig? runtimeFor(String deviceId, String pairName) {
    final device = deviceById(deviceId);
    if (device == null) return null;
    SyncPairEntry? pair;
    for (final entry in device.pairs) {
      if (entry.name == pairName) {
        pair = entry;
        break;
      }
    }
    return pair == null ? null : _runtimeFor(device, pair);
  }

  SyncPairConfig? runtimeForPairId(String pairId) {
    for (final device in devices) {
      for (final pair in device.pairs) {
        if (pair.id == pairId) return _runtimeFor(device, pair);
      }
    }
    return null;
  }

  SyncPairConfig? get firstRuntime {
    for (final device in devices) {
      if (device.pairs.isNotEmpty) {
        return _runtimeFor(device, device.pairs.first);
      }
    }
    return null;
  }

  SyncPairConfig _runtimeFor(SyncDeviceEntry device, SyncPairEntry pair) {
    return SyncPairConfig(
      name: pair.name,
      localRoot: pair.localRoot,
      remoteUrl: pair.remoteUrlFor(device),
      token: token,
      stateDir: pair.stateDir,
      timeoutSeconds: timeoutSeconds,
    );
  }

  String uniqueDeviceName(String base) {
    final trimmed = base.trim().isEmpty ? 'Device' : base.trim();
    if (!devices.any((device) => device.name == trimmed)) return trimmed;
    var index = 2;
    while (devices.any((device) => device.name == '$trimmed $index')) {
      index++;
    }
    return '$trimmed $index';
  }

  String uniquePairName(String deviceId, String base) {
    final trimmed = base.trim().isEmpty ? 'pair' : base.trim();
    final names = pairsForDevice(deviceId).map((pair) => pair.name).toSet();
    if (!names.contains(trimmed)) return trimmed;
    var index = 2;
    while (names.contains('$trimmed $index')) {
      index++;
    }
    return '$trimmed $index';
  }

  static String newDeviceId({String? seed}) {
    return 'd-${_uniqueSuffix(seed)}';
  }

  static String newPairId({String? seed}) {
    return 'p-${_uniqueSuffix(seed)}';
  }

  static String _uniqueSuffix(String? seed) {
    final base = seed == null ? '' : _slug(seed);
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final salt = Random().nextInt(1296).toRadixString(36).padLeft(2, '0');
    final prefix = base.isEmpty
        ? ''
        : '${base.substring(0, min(base.length, 8))}-';
    return '$prefix$stamp$salt';
  }

  static String _slug(String value) {
    final slug = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    return slug.isEmpty ? 'x' : slug;
  }

  static bool _validDeviceId(String? id) {
    return id != null && RegExp(r'^d-[a-z0-9]+$').hasMatch(id);
  }

  static bool _validPairId(String? id) {
    return id != null && RegExp(r'^p-[a-z0-9]+$').hasMatch(id);
  }

  static void _ensurePairState(
    List<SyncDeviceEntry> devices,
    String projectRoot,
  ) {
    final seenPairIds = <String>{};
    for (final device in devices) {
      final nextPairs = <SyncPairEntry>[];
      for (final pair in device.pairs) {
        var id = pair.id;
        if (!seenPairIds.add(id)) {
          id = newPairId(seed: pair.name);
          seenPairIds.add(id);
        }
        nextPairs.add(
          pair.copyWith(
            id: id,
            deviceId: device.id,
            stateDir: pair.stateDir.isEmpty
                ? p.join(projectRoot, 'data', 'sync_pairs', id)
                : pair.stateDir,
          ),
        );
      }
      device.pairs
        ..clear()
        ..addAll(nextPairs);
    }
  }

  static SyncDeviceEntry? _deviceFromLegacyPair(Map<String, Object?> json) {
    final remoteUrl = json['remoteUrl'] as String? ?? '';
    final uri = Uri.tryParse(remoteUrl);
    if (uri == null || uri.host.isEmpty) return null;
    return SyncDeviceEntry(
      id: newDeviceId(seed: '${uri.host}-${uri.port}'),
      name: uri.host,
      hostType: uri.host == '127.0.0.1' || uri.host == 'localhost'
          ? SyncHostType.local
          : SyncHostType.remote,
      host: uri.host,
      port: uri.hasPort ? uri.port : SyncDeviceEntry.defaultPort,
    );
  }

  static SyncPairEntry? _pairFromLegacy(
    Map<String, Object?> json,
    SyncDeviceEntry device,
    String projectRoot,
  ) {
    final remoteUrl = json['remoteUrl'] as String? ?? '';
    final uri = Uri.tryParse(remoteUrl);
    if (uri == null) return null;
    final path = uri.path.isEmpty ? '/' : uri.path;
    final name = (json['name'] as String?)?.trim().isNotEmpty == true
        ? (json['name'] as String).trim()
        : (path == '/' ? 'pair' : p.posix.basename(path));
    final rawState = json['stateDir'] as String?;
    return SyncPairEntry(
      id: newPairId(seed: name),
      name: name,
      localRoot: _resolve(
        projectRoot,
        _expandUser(
          json['localRoot'] as String? ??
              p.join(projectRoot, '..', 'photolens'),
        ),
      ),
      remoteRoot: _normalizeRemoteRoot(path),
      deviceId: device.id,
      stateDir: rawState == null || rawState.trim().isEmpty
          ? ''
          : _resolve(projectRoot, _expandUser(rawState)),
    );
  }

  static String _normalizeRemoteRoot(String value) {
    var root = value.trim().replaceAll('\\', '/');
    if (!root.startsWith('/')) root = '/$root';
    while (root.length > 1 && root.endsWith('/')) {
      root = root.substring(0, root.length - 1);
    }
    return root;
  }

  static String _resolve(String projectRoot, String path) {
    return p.normalize(p.isAbsolute(path) ? path : p.join(projectRoot, path));
  }

  static String _expandUser(String path) {
    if (path == '~') return Platform.environment['HOME'] ?? path;
    if (path.startsWith('~/')) {
      final home = Platform.environment['HOME'] ?? '';
      return p.join(home, path.substring(2));
    }
    return path;
  }
}
