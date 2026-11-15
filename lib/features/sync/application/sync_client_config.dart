/// Multi-pair client configuration.
///
/// Version 3 layout:
/// {
///   "version": 3,
///   "token": "...",
///   "timeoutSeconds": 300,
///   "ignores": [...],
///   "devices": [
///     {
///       "id": "dev-192-168-1-10-2160",
///       "name": "192.168.1.10",
///       "type": "windows",
///       "hostType": "remote",
///       "host": "192.168.1.10",
///       "port": 2160
///     }
///   ],
///   "pairs": [
///     {
///       "name": "gitbook",
///       "deviceId": "dev-192-168-1-10-2160",
///       "localRoot": "...",
///       "remoteUrl": "http://192.168.1.10:2160/gitbook",
///       "stateDir": "...",
///       "ignores": [...]
///     }
///   ]
/// }
///
/// Version 2 files (a flat "pairs" list without devices) and legacy single-pair
/// files are migrated in memory: devices are derived from each pair's remote
/// URL and written back on the next save.
library;

import 'dart:convert';
import 'dart:io';

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
  windowsDesktop,
  linuxDesktop,
  iphone,
  ipad,
  androidPhone;

  static SyncDeviceModel parse(Object? value) {
    return switch (value) {
      'macbook' => SyncDeviceModel.macbook,
      'windowsLaptop' => SyncDeviceModel.windowsLaptop,
      'windowsDesktop' => SyncDeviceModel.windowsDesktop,
      'linuxDesktop' => SyncDeviceModel.linuxDesktop,
      'iphone' => SyncDeviceModel.iphone,
      'ipad' => SyncDeviceModel.ipad,
      'androidPhone' => SyncDeviceModel.androidPhone,
      _ => SyncDeviceModel.windowsLaptop,
    };
  }

  /// Best-guess model from device type.
  static SyncDeviceModel fallbackOf(SyncDeviceType type) {
    return switch (type) {
      SyncDeviceType.windows => SyncDeviceModel.windowsLaptop,
      SyncDeviceType.macos => SyncDeviceModel.macbook,
      SyncDeviceType.linux => SyncDeviceModel.linuxDesktop,
      SyncDeviceType.android => SyncDeviceModel.androidPhone,
      SyncDeviceType.ios => SyncDeviceModel.iphone,
      SyncDeviceType.ipad => SyncDeviceModel.ipad,
    };
  }

  String get id => name;

  String get label => switch (this) {
    SyncDeviceModel.macbook => 'MacBook',
    SyncDeviceModel.windowsLaptop => 'Windows Laptop',
    SyncDeviceModel.windowsDesktop => 'Windows Desktop',
    SyncDeviceModel.linuxDesktop => 'Linux Desktop',
    SyncDeviceModel.iphone => 'iPhone',
    SyncDeviceModel.ipad => 'iPad',
    SyncDeviceModel.androidPhone => 'Android Phone',
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
  const SyncDeviceEntry({
    required this.id,
    required this.name,
    this.type = SyncDeviceType.windows,
    this.model,
    this.hostType = SyncHostType.remote,
    this.host = '',
    this.port = defaultPort,
    this.createdAt,
  });

  static const defaultPort = 2160;

  final String id;
  final String name;
  final SyncDeviceType type;
  final SyncDeviceModel? model;
  final SyncHostType hostType;
  final String host;
  final int port;
  final DateTime? createdAt;

  SyncDeviceModel get resolvedModel =>
      model ?? SyncDeviceModel.fallbackOf(type);

  bool get isLocal => hostType == SyncHostType.local;

  /// The host used to build URLs. Local devices always talk to loopback.
  String get resolvedHost =>
      isLocal || host.trim().isEmpty ? '127.0.0.1' : host.trim();

  String get authority => '$resolvedHost:$port';

  String get baseUrl => 'http://$authority';

  String get createdMonthLabel {
    final when = createdAt;
    if (when == null) return '—';
    final year = when.year.toString().padLeft(4, '0');
    final month = when.month.toString().padLeft(2, '0');
    return '$year-$month';
  }

  SyncDeviceEntry copyWith({
    String? id,
    String? name,
    SyncDeviceType? type,
    SyncDeviceModel? model,
    bool clearModel = false,
    SyncHostType? hostType,
    String? host,
    int? port,
    DateTime? createdAt,
  }) {
    return SyncDeviceEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      model: clearModel ? null : (model ?? this.model),
      hostType: hostType ?? this.hostType,
      host: host ?? this.host,
      port: port ?? this.port,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.id,
      if (model != null) 'model': model!.id,
      'hostType': hostType.id,
      'host': host,
      'port': port,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    };
  }

  factory SyncDeviceEntry.fromJson(Map<String, Object?> json) {
    final host = json['host'] as String? ?? '';
    final port = (json['port'] as num?)?.toInt() ?? defaultPort;
    final createdAtRaw = json['createdAt'] as String?;
    return SyncDeviceEntry(
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? (json['id'] as String).trim()
          : legacyDeviceId(host, port),
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : host,
      type: SyncDeviceType.parse(json['type']),
      model: json['model'] == null
          ? null
          : SyncDeviceModel.parse(json['model']),
      hostType: SyncHostType.parse(json['hostType']),
      host: host,
      port: port,
      createdAt: createdAtRaw == null ? null : DateTime.tryParse(createdAtRaw),
    );
  }

  /// A deterministic id used when a device is derived from a remote URL.
  static String legacyDeviceId(String host, int port) {
    final slug = '$host-$port'.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '-');
    return 'dev-$slug';
  }
}

final class SyncPairEntry {
  const SyncPairEntry({
    required this.name,
    required this.localRoot,
    required this.remoteUrl,
    required this.stateDir,
    this.deviceId = '',
    this.ignores = const [],
  });

  final String name;
  final String localRoot;
  final String remoteUrl;
  final String stateDir;

  /// The [SyncDeviceEntry.id] this pair syncs with.
  final String deviceId;

  /// Pair-specific ignore patterns.
  ///
  /// When non-empty, these replace the config-level [SyncClientConfig.extraIgnores]
  /// for this pair.
  final List<String> ignores;

  SyncPairEntry copyWith({
    String? name,
    String? localRoot,
    String? remoteUrl,
    String? stateDir,
    String? deviceId,
    List<String>? ignores,
  }) {
    return SyncPairEntry(
      name: name ?? this.name,
      localRoot: localRoot ?? this.localRoot,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      stateDir: stateDir ?? this.stateDir,
      deviceId: deviceId ?? this.deviceId,
      ignores: ignores ?? this.ignores,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'name': name,
      'deviceId': deviceId,
      'localRoot': localRoot,
      'remoteUrl': remoteUrl,
      'stateDir': stateDir,
      'ignores': ignores,
    };
  }

  SyncPairConfig toRuntime({
    required String token,
    required int timeoutSeconds,
    required List<String> extraIgnores,
  }) {
    return SyncPairConfig(
      name: name,
      localRoot: localRoot,
      remoteUrl: remoteUrl,
      token: token,
      stateDir: stateDir,
      timeoutSeconds: timeoutSeconds,
      extraIgnores: ignores.isNotEmpty ? ignores : extraIgnores,
    );
  }
}

final class SyncClientConfig {
  SyncClientConfig({
    required this.token,
    required this.timeoutSeconds,
    required this.extraIgnores,
    required List<SyncPairEntry> pairs,
    List<SyncDeviceEntry> devices = const [],
  }) : pairs = List.of(pairs),
       devices = List.of(devices);

  String token;
  int timeoutSeconds;
  final List<String> extraIgnores;
  final List<SyncPairEntry> pairs;
  final List<SyncDeviceEntry> devices;

  static const schemaVersion = 3;

  static SyncClientConfig load({
    required String path,
    required String projectRoot,
  }) {
    final file = File(path);
    if (!file.existsSync()) {
      return empty();
    }

    final text = file.readAsStringSync();
    if (text.trim().isEmpty) {
      return empty();
    }

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
    final ignores = json['ignores'] is List
        ? (json['ignores'] as List).whereType<String>().toList(growable: false)
        : const <String>[];

    final devices = <SyncDeviceEntry>[];
    final seenDeviceIds = <String>{};
    final rawDevices = json['devices'];
    if (rawDevices is List) {
      for (final raw in rawDevices) {
        if (raw is! Map) continue;
        final device = SyncDeviceEntry.fromJson(raw.cast<String, Object?>());
        if (seenDeviceIds.add(device.id)) {
          devices.add(device);
        }
      }
    }

    final pairs = <SyncPairEntry>[];
    final rawPairs = json['pairs'];
    if (rawPairs is List && rawPairs.isNotEmpty) {
      for (final raw in rawPairs) {
        if (raw is! Map) continue;
        pairs.add(
          _entryFromJson(raw.cast<String, Object?>(), projectRoot: projectRoot),
        );
      }
    } else {
      // Legacy single-pair layout.
      final remoteUrl = json['remoteUrl'] as String? ?? '';
      if (remoteUrl.isNotEmpty) {
        final name = _defaultPairName(remoteUrl);
        pairs.add(
          SyncPairEntry(
            name: name,
            localRoot: _resolve(
              projectRoot,
              _expandUser(
                json['localRoot'] as String? ??
                    p.join(projectRoot, '..', 'photolens'),
              ),
            ),
            remoteUrl: remoteUrl,
            stateDir: _resolve(
              projectRoot,
              _expandUser(
                json['stateDir'] as String? ??
                    p.join(projectRoot, 'data', 'sync_pairs', name),
              ),
            ),
          ),
        );
      }
    }

    final normalized = _ensureDevices(devices: devices, pairs: pairs);
    return SyncClientConfig(
      token: token,
      timeoutSeconds: timeoutSeconds,
      extraIgnores: ignores,
      devices: normalized.devices,
      pairs: normalized.pairs,
    );
  }

  static SyncClientConfig empty() {
    return SyncClientConfig(
      token: Platform.environment['FILE_SYNC_TOKEN'] ?? '',
      timeoutSeconds: 300,
      extraIgnores: const [],
      pairs: const [],
      devices: const [],
    );
  }

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
    return [
      for (final pair in pairs)
        if (pair.deviceId == deviceId) pair,
    ];
  }

  Future<void> save({required String path}) async {
    final file = File(path);
    final parent = Directory(p.dirname(file.path));
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final normalized = _ensureDevices(devices: devices, pairs: pairs);
    final data = <String, Object?>{
      'version': schemaVersion,
      'token': token,
      'timeoutSeconds': timeoutSeconds,
      'ignores': extraIgnores,
      'devices': [for (final device in normalized.devices) device.toJson()],
      'pairs': [for (final pair in normalized.pairs) pair.toJson()],
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

  SyncPairConfig? runtimeFor(String name) {
    SyncPairEntry? pair;
    for (final entry in pairs) {
      if (entry.name == name) {
        pair = entry;
        break;
      }
    }
    return pair?.toRuntime(
      token: token,
      timeoutSeconds: timeoutSeconds,
      extraIgnores: extraIgnores,
    );
  }

  SyncPairConfig? get firstRuntime {
    if (pairs.isEmpty) return null;
    return pairs.first.toRuntime(
      token: token,
      timeoutSeconds: timeoutSeconds,
      extraIgnores: extraIgnores,
    );
  }

  /// Returns a device name that does not collide with an existing one.
  String uniqueDeviceName(String base) {
    final trimmed = base.trim().isEmpty ? 'Device' : base.trim();
    if (!devices.any((device) => device.name == trimmed)) return trimmed;
    var index = 2;
    while (devices.any((device) => device.name == '$trimmed $index')) {
      index++;
    }
    return '$trimmed $index';
  }

  /// Returns a pair name that does not collide with an existing one.
  String uniquePairName(String base) {
    final trimmed = base.trim().isEmpty ? 'pair' : base.trim();
    if (!pairs.any((pair) => pair.name == trimmed)) return trimmed;
    var index = 2;
    while (pairs.any((pair) => pair.name == '$trimmed $index')) {
      index++;
    }
    return '$trimmed $index';
  }

  static SyncPairEntry _entryFromJson(
    Map<String, Object?> json, {
    required String projectRoot,
  }) {
    final remoteUrl = json['remoteUrl'] as String? ?? '';
    final name = (json['name'] as String?)?.trim().isNotEmpty == true
        ? (json['name'] as String).trim()
        : _defaultPairName(remoteUrl);
    final rawIgnores = json['ignores'];
    return SyncPairEntry(
      name: name,
      deviceId: json['deviceId'] as String? ?? '',
      localRoot: _resolve(
        projectRoot,
        _expandUser(
          json['localRoot'] as String? ??
              p.join(projectRoot, '..', 'photolens'),
        ),
      ),
      remoteUrl: remoteUrl,
      stateDir: _resolve(
        projectRoot,
        _expandUser(
          json['stateDir'] as String? ??
              p.join(projectRoot, 'data', 'sync_pairs', name),
        ),
      ),
      ignores: rawIgnores is List
          ? rawIgnores.whereType<String>().toList(growable: false)
          : const [],
    );
  }

  /// Attaches every pair to a device, deriving devices for legacy pairs.
  static ({List<SyncDeviceEntry> devices, List<SyncPairEntry> pairs})
  _ensureDevices({
    required List<SyncDeviceEntry> devices,
    required List<SyncPairEntry> pairs,
  }) {
    final result = List<SyncDeviceEntry>.of(devices);
    final normalizedPairs = <SyncPairEntry>[];
    for (final pair in pairs) {
      if (pair.deviceId.isNotEmpty &&
          result.any((device) => device.id == pair.deviceId)) {
        normalizedPairs.add(pair);
        continue;
      }
      final derived = _deviceFromUrl(pair.remoteUrl, result);
      var target = _matchDevice(derived, result);
      if (target == null) {
        final name = _uniqueName(derived.name, result);
        target = derived.copyWith(name: name);
        result.add(target);
      }
      normalizedPairs.add(pair.copyWith(deviceId: target.id, name: pair.name));
    }
    return (devices: result, pairs: normalizedPairs);
  }

  static SyncDeviceEntry _deviceFromUrl(
    String remoteUrl,
    List<SyncDeviceEntry> existing,
  ) {
    final uri = Uri.tryParse(remoteUrl);
    final host = uri?.host ?? '';
    final port = uri == null || !uri.hasPort
        ? SyncDeviceEntry.defaultPort
        : uri.port;
    final isLoopback =
        host == '127.0.0.1' || host == 'localhost' || host == '::1';
    return SyncDeviceEntry(
      id: SyncDeviceEntry.legacyDeviceId(host, port),
      name: host.isEmpty ? 'Unknown device' : host,
      hostType: isLoopback ? SyncHostType.local : SyncHostType.remote,
      host: host,
      port: port,
    );
  }

  static SyncDeviceEntry? _matchDevice(
    SyncDeviceEntry candidate,
    List<SyncDeviceEntry> devices,
  ) {
    for (final device in devices) {
      if (device.id == candidate.id) return device;
      if (device.port == candidate.port &&
          device.resolvedHost == candidate.resolvedHost) {
        return device;
      }
    }
    return null;
  }

  static String _uniqueName(String base, List<SyncDeviceEntry> devices) {
    if (!devices.any((device) => device.name == base)) return base;
    var index = 2;
    while (devices.any((device) => device.name == '$base $index')) {
      index++;
    }
    return '$base $index';
  }

  static String _defaultPairName(String remoteUrl) {
    final uri = Uri.tryParse(remoteUrl);
    final segments =
        uri?.pathSegments.where((segment) => segment.isNotEmpty).toList() ??
        const <String>[];
    return segments.isEmpty ? 'sync' : segments.last;
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
