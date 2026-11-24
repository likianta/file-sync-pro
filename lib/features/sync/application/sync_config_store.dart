/// Shared, mutable view of the sync client config.
///
/// The Sync and Devices pages both edit the same file, so they share one
/// [SyncConfigStore] instead of loading the JSON independently.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'sync_client_config.dart';

final class SyncConfigStore extends ChangeNotifier {
  SyncConfigStore({required this.path, required this.projectRoot});

  final String path;
  final String projectRoot;

  SyncClientConfig _config = SyncClientConfig.empty();
  bool _loaded = false;
  String? _error;
  Timer? _saveTimer;
  bool _disposed = false;

  bool get loaded => _loaded;

  String? get error => _error;

  SyncClientConfig get config => _config;

  List<SyncDeviceEntry> get devices => List.unmodifiable(_config.devices);

  List<SyncPairEntry> get pairs => List.unmodifiable(_config.pairs);

  Future<void> load() async {
    try {
      _config = SyncClientConfig.load(path: path, projectRoot: projectRoot);
      _error = null;
    } catch (error) {
      _config = SyncClientConfig.empty();
      _error = error.toString();
    }
    _loaded = true;
    _notify();
  }

  /// Persists immediately. Callers may await this to surface failures.
  Future<void> saveNow() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _config.save(path: path);
    _error = null;
  }

  void addDevice() {
    final id = SyncClientConfig.newDeviceId();
    _config.devices.add(
      SyncDeviceEntry(
        id: id,
        name: _uniqueDeviceName('New device', excludingId: id),
      ),
    );
    _scheduleSave();
    _notify();
  }

  /// Adds a device constructed from user input. Generates a unique id and
  /// ensures the device name does not collide with existing ones.
  SyncDeviceEntry addDeviceFromInput({
    required String name,
    required String host,
    required int port,
    required SyncHostType hostType,
    SyncDeviceType type = SyncDeviceType.windows,
    SyncDeviceModel? model,
  }) {
    final id = SyncClientConfig.newDeviceId();
    final entry = SyncDeviceEntry(
      id: id,
      name: _uniqueDeviceName(name, excludingId: id),
      type: type,
      model: model,
      hostType: hostType,
      host: host,
      port: port,
    );
    _config.devices.add(entry);
    _scheduleSave();
    _notify();
    return entry;
  }

  /// Returns true if a device with the given [name] already exists.
  bool hasDeviceName(String name) {
    return _config.devices.any((device) => device.name == name.trim());
  }

  void updateDevice(SyncDeviceEntry device) {
    final index = _config.devices.indexWhere((entry) => entry.id == device.id);
    if (index < 0) return;

    final name = _uniqueDeviceName(device.name, excludingId: device.id);
    _config.devices[index] = device.copyWith(name: name);
    _scheduleSave();
    _notify();
  }

  void removeDevice(String deviceId) {
    _config.devices.removeWhere((device) => device.id == deviceId);
    _scheduleSave();
    _notify();
  }

  void upsertPair(SyncPairEntry pair, {String? previousName}) {
    final device = _config.deviceById(pair.deviceId);
    if (device == null) return;
    var index = device.pairs.indexWhere((entry) => entry.id == pair.id);
    if (index < 0 && previousName != null) {
      index = device.pairs.indexWhere((entry) => entry.name == previousName);
    }
    if (index >= 0) {
      device.pairs[index] = pair;
    } else {
      device.pairs.add(pair);
    }
    _scheduleSave();
    _notify();
  }

  void removePair(String deviceId, String pairId) {
    final device = _config.deviceById(deviceId);
    if (device == null) return;
    device.pairs.removeWhere((pair) => pair.id == pairId);
    _scheduleSave();
    _notify();
  }

  void updateToken(String token) {
    if (_config.token == token) return;
    _config.token = token;
    _scheduleSave();
    _notify();
  }

  String _uniqueDeviceName(String base, {required String excludingId}) {
    final trimmed = base.trim().isEmpty ? 'Device' : base.trim();
    bool taken(String name) => _config.devices.any(
      (device) => device.id != excludingId && device.name == name,
    );
    if (!taken(trimmed)) return trimmed;
    var index = 2;
    while (taken('$trimmed $index')) {
      index++;
    }
    return '$trimmed $index';
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), () {
      _saveTimer = null;
      unawaited(_save());
    });
  }

  Future<void> _save() async {
    try {
      await _config.save(path: path);
    } catch (_) {
      // A failed background save is retried on the next edit. Explicit saves
      // from the UI surface the error instead.
    }
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    _saveTimer = null;
    super.dispose();
  }
}
