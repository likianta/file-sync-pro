import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../transport/http_transport.dart';
import '../application/sync_client_config.dart';
import '../application/sync_config_store.dart';
import 'device_advanced_dialog.dart';
import 'device_editor_dialog.dart';
import 'pair_editor_dialog.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key, required this.store});

  final SyncConfigStore store;

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  Future<void> _openAddDeviceDialog() async {
    final store = widget.store;
    final result = await showDeviceEditorDialog(
      context: context,
      existingNames: store.devices.map((d) => d.name).toSet(),
    );
    if (result == null) return;
    store.addDeviceFromInput(
      name: result.name,
      host: result.host,
      port: result.port,
      hostType: result.hostType,
      type: result.platform ?? SyncDeviceType.unknown,
      platform: result.platform,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final theme = Theme.of(context);
        if (!widget.store.loaded) {
          return Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  'Loading devices...',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }
        final devices = widget.store.devices;
        return Column(
          children: [
            _PageHeader(onAdd: _openAddDeviceDialog),
            Expanded(
              child: devices.isEmpty
                  ? _EmptyDevices(onAdd: _openAddDeviceDialog)
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        const spacing = 16.0;
                        const minCardWidth = 280.0;
                        const maxCardWidth = 400.0;
                        final available = math.max(
                          0.0,
                          constraints.maxWidth - 40,
                        );
                        final columnCount = math.max(
                          1,
                          ((available + spacing) / (minCardWidth + spacing))
                              .floor(),
                        );
                        var cardWidth =
                            (available - spacing * (columnCount - 1)) /
                            columnCount;
                        if (cardWidth > maxCardWidth) cardWidth = maxCardWidth;

                        return SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          child: _MasonryFlow(
                            crossAxisCount: columnCount,
                            spacing: spacing,
                            cardWidth: cardWidth,
                            children: [
                              for (final device in devices)
                                _DeviceCard(
                                  key: ValueKey<String>(
                                    'devices.card.${device.id}',
                                  ),
                                  store: widget.store,
                                  device: device,
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Devices',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Peer devices are stored as cards as below. The online '
                  'status is not auto-detected; check it before pairing, '
                  'scanning, or syncing with them.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            key: const ValueKey<String>('devices.add'),
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add device'),
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatefulWidget {
  const _DeviceCard({super.key, required this.store, required this.device});

  final SyncConfigStore store;
  final SyncDeviceEntry device;

  @override
  State<_DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<_DeviceCard> {
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final FocusNode _nameFocus;
  late final FocusNode _addressFocus;

  bool _testing = false;
  bool? _online;
  String? _testDetail;

  SyncDeviceEntry get _device => widget.device;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.device.name);
    _address = TextEditingController(text: _addressText(widget.device));
    _nameFocus = FocusNode()..addListener(_onNameFocusChanged);
    _addressFocus = FocusNode()..addListener(_onAddressFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _DeviceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_nameFocus.hasFocus && _name.text != widget.device.name) {
      _name.text = widget.device.name;
    }
    final address = _addressText(widget.device);
    if (!_addressFocus.hasFocus && _address.text != address) {
      _address.text = address;
    }
  }

  @override
  void dispose() {
    _nameFocus.dispose();
    _addressFocus.dispose();
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  static String _addressText(SyncDeviceEntry device) {
    return '${device.resolvedHost}:${device.port}';
  }

  static List<String> _rememberAddress(List<String> history, String address) {
    final next = [address, ...history.where((item) => item != address)];
    if (next.length > 8) next.removeRange(8, next.length);
    return next;
  }

  void _onNameFocusChanged() {
    if (!_nameFocus.hasFocus) _commitName();
  }

  void _onAddressFocusChanged() {
    if (!_addressFocus.hasFocus) _commitAddress();
  }

  void _commitName() {
    final value = _name.text.trim();
    final device = _latestDevice;
    if (value.isEmpty) {
      _name.text = device.name;
      return;
    }
    if (value == device.name) return;
    widget.store.updateDevice(device.copyWith(name: value));
  }

  void _commitAddress() {
    final raw = _address.text.trim();
    final device = _latestDevice;
    if (raw.isEmpty) {
      _address.text = _addressText(device);
      return;
    }
    final (host, port) = SyncDeviceEntry.parseAddress(raw);
    if (host.isEmpty) {
      _address.text = _addressText(device);
      return;
    }
    final address = '$host:$port';
    if (_address.text != address) _address.text = address;
    if (host == device.host && port == device.port) return;
    setState(() {
      _online = null;
      _testDetail = null;
    });
    _applyAddress(device: device, host: host, port: port);
  }

  void _applyAddress({
    required SyncDeviceEntry device,
    required String host,
    required int port,
    SyncDeviceType? platform,
  }) {
    final address = '$host:$port';
    widget.store.updateDevice(
      device.copyWith(
        host: host,
        port: port,
        type: platform,
        platform: platform,
        addresses: _rememberAddress(device.addresses, address),
      ),
    );
  }

  void _selectAddress(String address) {
    _address.text = address;
    _commitAddress();
  }

  Future<void> _testReachability() async {
    if (_testing) return;
    final (host, port) = SyncDeviceEntry.parseAddress(_address.text);
    if (host.isEmpty) {
      _toast('Enter an address first.');
      return;
    }
    final address = '$host:$port';
    _address.text = address;

    setState(() {
      _testing = true;
      _testDetail = null;
    });
    final transport = HttpTransport(
      baseUrl: 'http://$address',
      token: widget.store.config.token,
      timeout: const Duration(seconds: 10),
    );
    try {
      final json = await transport.getJson('');
      final mounts = json['mounts'] is List
          ? (json['mounts'] as List).whereType<String>().toList()
          : const <String>[];
      var platform = SyncDeviceType.tryParse(json['platform']);
      if (platform == null && mounts.isNotEmpty) {
        final info = await transport.getJson('/${mounts.first}');
        platform = SyncDeviceType.tryParse(info['platform']);
      }
      if (!mounted) return;
      final detail = [
        'Online',
        if (platform != null) platform.label,
        '${mounts.length} mount${mounts.length == 1 ? '' : 's'}',
      ].join(' · ');
      setState(() {
        _online = true;
        _testDetail = detail;
      });
      _applyAddress(
        device: _latestDevice,
        host: host,
        port: port,
        platform: platform,
      );
      _toast('${_device.name}: $detail');
    } catch (error) {
      if (!mounted) return;
      final detail = error is RemoteException
          ? '${error.statusCode}: ${error.message}'
          : error.toString();
      setState(() {
        _online = false;
        _testDetail = detail;
      });
      _toast('Cannot reach $address: $detail');
    } finally {
      await transport.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  SyncDeviceEntry get _latestDevice {
    for (final device in widget.store.config.devices) {
      if (device.id == _device.id) return device;
    }
    return _device;
  }

  /// Applies pending inline edits before opening another surface, so dialogs
  /// never operate on stale name or address values.
  SyncDeviceEntry _commitInlineEdits() {
    _commitName();
    _commitAddress();
    return _latestDevice;
  }

  Future<void> _openAdvancedSettings() async {
    final device = _commitInlineEdits();
    await showDeviceAdvancedDialog(
      context: context,
      store: widget.store,
      device: device,
    );
  }

  Future<void> _addPair() async {
    final device = _commitInlineEdits();
    final result = await showPairEditorDialog(
      context: context,
      projectRoot: widget.store.projectRoot,
      device: device,
      token: widget.store.config.token,
    );
    if (result == null || !mounted) return;
    if (widget.store.config
        .pairsForDevice(device.id)
        .any((pair) => pair.name == result.entry.name)) {
      _toast('A pair named "${result.entry.name}" already exists.');
      return;
    }
    widget.store.upsertPair(result.entry);
  }

  Future<void> _editPair(SyncPairEntry pair) async {
    final device = _commitInlineEdits();
    final result = await showPairEditorDialog(
      context: context,
      projectRoot: widget.store.projectRoot,
      device: device,
      token: widget.store.config.token,
      entry: pair,
    );
    if (result == null || !mounted) return;
    if (result.entry.name != pair.name &&
        widget.store.config
            .pairsForDevice(device.id)
            .any((entry) => entry.name == result.entry.name)) {
      _toast('A pair named "${result.entry.name}" already exists.');
      return;
    }
    widget.store.upsertPair(result.entry, previousName: pair.name);
  }

  Future<void> _deletePair(SyncPairEntry pair) async {
    final confirmed = await _confirm(
      context,
      title: 'Delete sync pair?',
      message:
          'Remove "${pair.name}" from this device. Files are not deleted; '
          'only the pair configuration and its state remain on disk.',
      confirmLabel: 'Delete',
      confirmKey: ValueKey<String>('devices.pair.deleteConfirm.${pair.name}'),
    );
    if (confirmed) {
      widget.store.removePair(_device.id, pair.id);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final device = _device;
    final pairs = widget.store.config.pairsForDevice(device.id);
    final history = [
      for (final address in device.addresses)
        if (address != '${device.resolvedHost}:${device.port}') address,
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.devices,
                    size: 17,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                _CapsuleTag(
                  label: device.isLocal ? 'Local' : 'Remote',
                  color: const Color(0xFF2563EB),
                  tint: const Color(0xFFDBEAFE),
                ),
                const SizedBox(width: 6),
                _CapsuleTag(
                  label: _platformLabel(device),
                  color: device.platform == null
                      ? const Color(0xFF64748B)
                      : const Color(0xFF0F766E),
                  tint: device.platform == null
                      ? const Color(0xFFE2E8F0)
                      : const Color(0xFFCCFBF1),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey<String>('devices.name.${device.id}'),
                    controller: _name,
                    focusNode: _nameFocus,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Device name',
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    onSubmitted: (_) => _commitName(),
                  ),
                ),
                IconButton(
                  key: ValueKey<String>('devices.advanced.${device.id}'),
                  tooltip: 'Advanced settings',
                  onPressed: _openAdvancedSettings,
                  icon: const Icon(Icons.tune, size: 17),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey<String>('devices.address.${device.id}'),
                    controller: _address,
                    focusNode: _addressFocus,
                    keyboardType: TextInputType.url,
                    style: _monospace(theme, 12),
                    decoration: const InputDecoration(
                      hintText: 'host:port',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    onSubmitted: (_) => _commitAddress(),
                  ),
                ),
                PopupMenuButton<String>(
                  key: ValueKey<String>('devices.address.history.${device.id}'),
                  tooltip: 'Recent addresses',
                  enabled: history.isNotEmpty,
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.arrow_drop_down,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  onSelected: _selectAddress,
                  itemBuilder: (context) => [
                    if (history.isEmpty)
                      const PopupMenuItem<String>(
                        enabled: false,
                        child: Text('No recent addresses'),
                      )
                    else
                      for (final address in history)
                        PopupMenuItem<String>(
                          value: address,
                          child: Text(address),
                        ),
                  ],
                ),
                IconButton(
                  key: ValueKey<String>('devices.test.${device.id}'),
                  tooltip: _testDetail ?? 'Test reachability',
                  onPressed: _testing ? null : _testReachability,
                  icon: _testing
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _online == null
                              ? Icons.wifi_tethering
                              : (_online!
                                    ? Icons.check_circle_outline
                                    : Icons.error_outline),
                          size: 18,
                          color: _online == null
                              ? theme.colorScheme.onSurfaceVariant
                              : (_online!
                                    ? const Color(0xFF059669)
                                    : theme.colorScheme.error),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Divider(height: 20, color: theme.colorScheme.outlineVariant),
            if (pairs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'No pairs yet.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final pair in pairs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _PairRow(
                    key: ValueKey<String>(
                      'devices.pair.${device.id}.${pair.name}',
                    ),
                    deviceId: device.id,
                    pair: pair,
                    onEdit: () => _editPair(pair),
                    onDelete: () => _deletePair(pair),
                  ),
                ),
            InkWell(
              key: ValueKey<String>('devices.pair.add.${device.id}'),
              borderRadius: BorderRadius.circular(6),
              onTap: _addPair,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.add, size: 15, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Add pair',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _platformLabel(SyncDeviceEntry device) {
    if (device.isLocal) {
      final current = SyncDeviceType.tryParse(Platform.operatingSystem);
      return (current ?? SyncDeviceType.unknown).label;
    }
    return (device.platform ?? device.type).label;
  }

  static TextStyle? _monospace(ThemeData theme, double size) {
    return theme.textTheme.bodySmall?.copyWith(
      fontSize: size,
      fontFamily: defaultTargetPlatform == TargetPlatform.macOS
          ? 'Menlo'
          : 'monospace',
      fontFamilyFallback: const [
        'SF Mono',
        'Menlo',
        'Consolas',
        'Courier New',
        'Roboto Mono',
        'Droid Sans Mono',
        'PingFang SC',
        'Noto Sans CJK SC',
        'Noto Sans SC',
      ],
    );
  }
}

class _CapsuleTag extends StatelessWidget {
  const _CapsuleTag({required this.label, required this.color, this.tint});

  final String label;
  final Color color;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = (tint ?? color).withValues(alpha: tint != null ? 0.55 : 0.14);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _PairRow extends StatelessWidget {
  const _PairRow({
    super.key,
    required this.deviceId,
    required this.pair,
    required this.onEdit,
    required this.onDelete,
  });

  final String deviceId;
  final SyncPairEntry pair;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 2, 2, 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            Icons.folder_outlined,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              pair.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            key: ValueKey<String>('devices.pair.edit.$deviceId.${pair.name}'),
            tooltip: 'Edit pair',
            onPressed: onEdit,
            icon: const Icon(Icons.settings_outlined, size: 16),
          ),
          IconButton(
            key: ValueKey<String>('devices.pair.delete.$deviceId.${pair.name}'),
            tooltip: 'Delete pair',
            onPressed: onDelete,
            icon: Icon(
              Icons.delete_outline,
              size: 16,
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDevices extends StatelessWidget {
  const _EmptyDevices({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.devices,
              size: 24,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No peer devices yet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add a device to describe the peer and the mounts it shares.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const ValueKey<String>('devices.emptyAdd'),
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add device'),
          ),
        ],
      ),
    );
  }
}

/// Shows a Material confirmation dialog.
Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  Key? confirmKey,
}) async {
  final theme = Theme.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message, style: theme.textTheme.bodyMedium),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: confirmKey,
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result == true;
}

/// Zero-dependency masonry (Pinterest-style) layout.
/// Each child is placed at the bottom of the shortest column.
class _MasonryFlow extends StatefulWidget {
  const _MasonryFlow({
    required this.crossAxisCount,
    required this.spacing,
    required this.cardWidth,
    required this.children,
  });

  final int crossAxisCount;
  final double spacing;
  final double cardWidth;
  final List<Widget> children;

  @override
  State<_MasonryFlow> createState() => _MasonryFlowState();
}

class _MasonryFlowState extends State<_MasonryFlow> {
  double _totalHeight = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty) return const SizedBox.shrink();
    return Flow(
      delegate: _MasonryFlowDelegate(
        crossAxisCount: widget.crossAxisCount,
        spacing: widget.spacing,
        cardWidth: widget.cardWidth,
        cachedHeight: _totalHeight,
        onHeightChanged: (h) {
          if ((h - _totalHeight).abs() <= 0.5) return;
          // The height is measured while painting. Updating state here would
          // schedule a build during paint, so wait for the next frame.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || (h - _totalHeight).abs() <= 0.5) return;
            setState(() => _totalHeight = h);
          });
        },
      ),
      children: widget.children,
    );
  }
}

class _MasonryFlowDelegate extends FlowDelegate {
  _MasonryFlowDelegate({
    required this.crossAxisCount,
    required this.spacing,
    required this.cardWidth,
    required this.cachedHeight,
    required this.onHeightChanged,
  });

  final int crossAxisCount;
  final double spacing;
  final double cardWidth;
  final double cachedHeight;
  final ValueChanged<double> onHeightChanged;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) {
    return BoxConstraints(
      minWidth: cardWidth,
      maxWidth: cardWidth,
      minHeight: 0,
      maxHeight: double.infinity,
    );
  }

  @override
  Size getSize(BoxConstraints constraints) {
    final totalWidth =
        crossAxisCount * cardWidth + (crossAxisCount - 1) * spacing;
    return Size(totalWidth, cachedHeight);
  }

  @override
  void paintChildren(FlowPaintingContext context) {
    final colTops = List<double>.filled(crossAxisCount, 0.0);

    for (var i = 0; i < context.childCount; i++) {
      final childSize = context.getChildSize(i) ?? Size.zero;

      var shortestCol = 0;
      for (var c = 1; c < crossAxisCount; c++) {
        if (colTops[c] < colTops[shortestCol]) shortestCol = c;
      }

      final x = shortestCol * (cardWidth + spacing);
      final y = colTops[shortestCol];
      context.paintChild(i, transform: Matrix4.translationValues(x, y, 0));
      colTops[shortestCol] += childSize.height + spacing;
    }

    var maxHeight = 0.0;
    for (final top in colTops) {
      if (top > maxHeight) maxHeight = top;
    }
    if (maxHeight > spacing) maxHeight -= spacing;
    onHeightChanged(maxHeight);
  }

  @override
  bool shouldRelayout(covariant _MasonryFlowDelegate oldDelegate) {
    // The size comes from [cachedHeight], which is measured during paint, so a
    // changed height must trigger a layout pass. Otherwise the Flow keeps its
    // initial zero height and cannot be hit tested.
    return crossAxisCount != oldDelegate.crossAxisCount ||
        spacing != oldDelegate.spacing ||
        cardWidth != oldDelegate.cardWidth ||
        cachedHeight != oldDelegate.cachedHeight;
  }

  @override
  bool shouldRepaint(covariant _MasonryFlowDelegate oldDelegate) {
    return crossAxisCount != oldDelegate.crossAxisCount ||
        spacing != oldDelegate.spacing ||
        cardWidth != oldDelegate.cardWidth ||
        cachedHeight != oldDelegate.cachedHeight;
  }
}
