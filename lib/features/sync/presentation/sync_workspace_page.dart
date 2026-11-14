import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../application/sync_client_config.dart';
import '../application/sync_config_store.dart';
import '../application/sync_pair_config.dart';
import 'sync_dashboard_controller.dart';
import 'sync_dashboard_page.dart';

class SyncWorkspacePage extends StatefulWidget {
  const SyncWorkspacePage({super.key, required this.store});

  final SyncConfigStore store;

  @override
  State<SyncWorkspacePage> createState() => _SyncWorkspacePageState();
}

class _SyncWorkspacePageState extends State<SyncWorkspacePage> {
  String? _deviceId;
  String? _pairName;
  SyncDashboardController? _controller;
  String? _controllerKey;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_syncSelection);
    _syncSelection();
  }

  @override
  void dispose() {
    widget.store.removeListener(_syncSelection);
    _controller?.dispose();
    super.dispose();
  }

  /// Keeps the device/pair selection and the dashboard controller in sync with
  /// the shared config.
  void _syncSelection() {
    if (!widget.store.loaded) return;

    final devices = widget.store.devices;
    var deviceId = _deviceId;
    if (deviceId == null || !devices.any((device) => device.id == deviceId)) {
      deviceId = devices.isEmpty ? null : devices.first.id;
    }

    final pairs = deviceId == null
        ? const <SyncPairEntry>[]
        : widget.store.config.pairsForDevice(deviceId);
    var pairName = _pairName;
    if (pairName == null || !pairs.any((pair) => pair.name == pairName)) {
      pairName = pairs.isEmpty ? null : pairs.first.name;
    }

    final runtime = pairName == null
        ? null
        : widget.store.config.runtimeFor(pairName);
    final key = runtime == null ? null : _keyOf(runtime);

    var changed = deviceId != _deviceId || pairName != _pairName;
    _deviceId = deviceId;
    _pairName = pairName;

    if (key != _controllerKey) {
      _controller?.dispose();
      _controller = runtime == null
          ? null
          : SyncDashboardController(config: runtime);
      _controllerKey = key;
      changed = true;
    }

    if (changed && mounted) {
      setState(() {});
    }
  }

  static String _keyOf(SyncPairConfig config) {
    return [
      config.localRoot,
      config.remoteUrl,
      config.token,
      config.timeoutSeconds,
      config.stateDir,
      config.extraIgnores.join('\u0000'),
    ].join('\u0001');
  }

  void _selectDevice(String deviceId) {
    if (deviceId == _deviceId) return;
    _deviceId = deviceId;
    _pairName = null;
    _syncSelection();
  }

  void _selectPair(String name) {
    if (name == _pairName) return;
    _pairName = name;
    _syncSelection();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final theme = context.theme;
        if (!store.loaded) {
          return Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: FCircularProgress(),
                ),
                const SizedBox(width: 10),
                Text(
                  'Loading sync pairs...',
                  style: theme.typography.body.sm.copyWith(
                    color: theme.colors.mutedForeground,
                  ),
                ),
              ],
            ),
          );
        }

        if (store.error != null) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: FAlert(
                variant: FAlertVariant.destructive,
                title: const Text('Cannot read sync config'),
                subtitle: Text(store.error!),
                icon: const Icon(FLucideIcons.circleAlert),
              ),
            ),
          );
        }

        final config = store.config;
        final devices = config.devices;
        final selectedDevice = _deviceId == null
            ? null
            : config.deviceById(_deviceId!);
        final pairs = selectedDevice == null
            ? const <SyncPairEntry>[]
            : config.pairsForDevice(selectedDevice.id);
        SyncPairEntry? pair;
        for (final entry in pairs) {
          if (entry.name == _pairName) {
            pair = entry;
            break;
          }
        }
        final controller = _controller;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: _DevicePairStrip(
                device: selectedDevice,
                localRoot: pair?.localRoot,
                devices: devices,
                onSelectDevice: _selectDevice,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: _PairTabs(
                pairs: pairs,
                selected: _pairName,
                onSelect: _selectPair,
              ),
            ),
            Expanded(
              child: controller == null
                  ? _EmptyPairs(hasDevice: selectedDevice != null)
                  : ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: SyncPreviewArea(controller: controller),
                          ),
                          SyncBottomBar(controller: controller),
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _DevicePairStrip extends StatelessWidget {
  const _DevicePairStrip({
    required this.device,
    required this.localRoot,
    required this.devices,
    required this.onSelectDevice,
  });

  final SyncDeviceEntry? device;
  final String? localRoot;
  final List<SyncDeviceEntry> devices;
  final ValueChanged<String> onSelectDevice;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return FCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Endpoint(
                icon: FLucideIcons.computer,
                overline: 'THIS MACHINE',
                title: _localMachineName(),
                subtitle: localRoot ?? 'Choose a pair on the right.',
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Padding(
                padding: const EdgeInsets.only(top: 22),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: theme.colors.muted,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    FLucideIcons.arrowRightLeft,
                    size: 14,
                    color: theme.colors.mutedForeground,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _PeerEndpoint(
                device: device,
                devices: devices,
                onSelectDevice: onSelectDevice,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _localMachineName() {
    final hostname = Platform.localHostname;
    return hostname.isEmpty ? _platformName() : hostname;
  }

  static String _platformName() {
    return switch (Platform.operatingSystem) {
      'macos' => 'This Mac',
      'windows' => 'This PC',
      'linux' => 'This machine',
      _ => 'This device',
    };
  }
}

class _Endpoint extends StatelessWidget {
  const _Endpoint({
    required this.icon,
    required this.overline,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String overline;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colors.muted.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: theme.colors.mutedForeground),
              const SizedBox(width: 6),
              Text(
                overline,
                style: theme.typography.body.xs.copyWith(
                  color: theme.colors.mutedForeground,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.typography.body.sm.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.typography.body.xs.copyWith(
              fontFamily: 'monospace',
              color: theme.colors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

class _PeerEndpoint extends StatelessWidget {
  const _PeerEndpoint({
    required this.device,
    required this.devices,
    required this.onSelectDevice,
  });

  final SyncDeviceEntry? device;
  final List<SyncDeviceEntry> devices;
  final ValueChanged<String> onSelectDevice;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final selected = device;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colors.muted.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FLucideIcons.router,
                size: 14,
                color: theme.colors.mutedForeground,
              ),
              const SizedBox(width: 6),
              Text(
                'PEER DEVICE',
                style: theme.typography.body.xs.copyWith(
                  color: theme.colors.mutedForeground,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              if (selected != null)
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF2EA121),
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (devices.isEmpty)
            Text(
              'No devices yet. Add one in Devices.',
              style: theme.typography.body.xs.copyWith(
                color: theme.colors.mutedForeground,
              ),
            )
          else
            FSelect<String>(
              key: const ValueKey<String>('sync.device.select'),
              control: FSelectControl<String>.lifted(
                value: selected?.name,
                onChange: (value) {
                  if (value == null) return;
                  final device = devices.firstWhere(
                    (entry) => entry.name == value,
                  );
                  onSelectDevice(device.id);
                },
              ),
              items: {for (final entry in devices) entry.name: entry.name},
              hint: 'Select a peer device',
            ),
          if (selected != null) ...[
            const SizedBox(height: 6),
            Text(
              selected.baseUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.body.xs.copyWith(
                fontFamily: 'monospace',
                color: theme.colors.mutedForeground,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PairTabs extends StatelessWidget {
  const _PairTabs({
    required this.pairs,
    required this.selected,
    required this.onSelect,
  });

  final List<SyncPairEntry> pairs;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          if (pairs.isEmpty)
            Text(
              'No pairs for this device.',
              style: theme.typography.body.sm.copyWith(
                color: theme.colors.mutedForeground,
              ),
            )
          else
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final pair in pairs)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FButton(
                        key: ValueKey<String>('sync.pair.tab.${pair.name}'),
                        variant: pair.name == selected
                            ? FButtonVariant.secondary
                            : FButtonVariant.ghost,
                        size: FButtonSizeVariant.sm,
                        onPress: () => onSelect(pair.name),
                        child: Text(pair.name),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyPairs extends StatelessWidget {
  const _EmptyPairs({required this.hasDevice});

  final bool hasDevice;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: theme.colors.muted,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              FLucideIcons.folderOpen,
              size: 24,
              color: theme.colors.mutedForeground,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            hasDevice ? 'No pairs for this device.' : 'No devices yet.',
            style: theme.typography.body.md.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hasDevice
                ? 'Add a pair in Devices to choose a local folder and a mount.'
                : 'Add a device in Devices, then add a pair to it.',
            style: theme.typography.body.sm.copyWith(
              color: theme.colors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}
