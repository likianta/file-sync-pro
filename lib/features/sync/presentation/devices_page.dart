import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../application/sync_client_config.dart';
import '../application/sync_config_store.dart';
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final theme = context.theme;
        if (!widget.store.loaded) {
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
                  'Loading devices...',
                  style: theme.typography.body.sm.copyWith(
                    color: theme.colors.mutedForeground,
                  ),
                ),
              ],
            ),
          );
        }
        final devices = widget.store.devices;
        return Column(
          children: [
            _PageHeader(store: widget.store, onAdd: _openAddDeviceDialog),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: devices.isEmpty
                      ? _EmptyDevices(onAdd: _openAddDeviceDialog)
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          children: [
                            for (final device in devices)
                              Padding(
                                key: ValueKey<String>(
                                  'devices.card.${device.id}',
                                ),
                                padding: const EdgeInsets.only(bottom: 14),
                                child: _DeviceCard(
                                  store: widget.store,
                                  device: device,
                                ),
                              ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.store, required this.onAdd});

  final SyncConfigStore store;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.colors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Devices',
                  style: theme.typography.body.xl.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Peers this machine syncs with, and the folders shared with '
                  'each of them.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.typography.body.sm.copyWith(
                    color: theme.colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          FButton(
            key: const ValueKey<String>('devices.add'),
            variant: FButtonVariant.outline,
            onPress: onAdd,
            prefix: const Icon(FLucideIcons.plus, size: 15),
            child: const Text('Add device'),
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatefulWidget {
  const _DeviceCard({required this.store, required this.device});

  final SyncConfigStore store;
  final SyncDeviceEntry device;

  @override
  State<_DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<_DeviceCard> {
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.device.name);
    _host = TextEditingController(text: widget.device.host);
    _port = TextEditingController(text: widget.device.port.toString());
  }

  @override
  void didUpdateWidget(covariant _DeviceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device.id != widget.device.id) {
      _name.text = widget.device.name;
      _host.text = widget.device.host;
      _port.text = widget.device.port.toString();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  void _update(SyncDeviceEntry next) {
    widget.store.updateDevice(next);
  }

  Future<void> _deleteDevice() async {
    final confirmed = await showFDialog<bool>(
      context: context,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        constraints: const BoxConstraints(minWidth: 380, maxWidth: 460),
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Remove device?', style: style.titleTextStyle),
              const SizedBox(height: 8),
              Text(
                '"${widget.device.name}" and its ${widget.store.config.pairsForDevice(widget.device.id).length} '
                'pair(s) will be removed from this device. Files are not '
                'deleted.',
                style: style.bodyTextStyle,
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FButton(
                    variant: FButtonVariant.outline,
                    onPress: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FButton(
                    key: const ValueKey<String>('devices.deleteConfirm'),
                    variant: FButtonVariant.destructive,
                    onPress: () => Navigator.of(context).pop(true),
                    child: const Text('Remove'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true) {
      widget.store.removeDevice(widget.device.id);
    }
  }

  Future<void> _addPair() async {
    final result = await showPairEditorDialog(
      context: context,
      projectRoot: widget.store.projectRoot,
      device: widget.device,
      token: widget.store.config.token,
    );
    if (result == null || !mounted) return;
    if (widget.store.pairs.any((pair) => pair.name == result.entry.name)) {
      _toast('A pair named "${result.entry.name}" already exists.');
      return;
    }
    widget.store.updateToken(result.token);
    widget.store.upsertPair(result.entry);
  }

  Future<void> _editPair(SyncPairEntry pair) async {
    final result = await showPairEditorDialog(
      context: context,
      projectRoot: widget.store.projectRoot,
      device: widget.device,
      token: widget.store.config.token,
      entry: pair,
    );
    if (result == null || !mounted) return;
    if (result.entry.name != pair.name &&
        widget.store.pairs.any((entry) => entry.name == result.entry.name)) {
      _toast('A pair named "${result.entry.name}" already exists.');
      return;
    }
    widget.store.updateToken(result.token);
    widget.store.upsertPair(result.entry, previousName: pair.name);
  }

  Future<void> _deletePair(SyncPairEntry pair) async {
    final confirmed = await showFDialog<bool>(
      context: context,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        constraints: const BoxConstraints(minWidth: 380, maxWidth: 460),
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Delete sync pair?', style: style.titleTextStyle),
              const SizedBox(height: 8),
              Text(
                'Remove "${pair.name}" from this device. Files are not deleted; '
                'only the pair configuration and its state remain on disk.',
                style: style.bodyTextStyle,
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FButton(
                    variant: FButtonVariant.outline,
                    onPress: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FButton(
                    key: ValueKey<String>(
                      'devices.pair.deleteConfirm.${pair.name}',
                    ),
                    variant: FButtonVariant.destructive,
                    onPress: () => Navigator.of(context).pop(true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true) {
      widget.store.removePair(pair.name);
    }
  }

  void _toast(String message) {
    showFToast(
      context: context,
      title: Text(message),
      icon: const Icon(FLucideIcons.circleAlert),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final device = widget.device;
    final pairs = widget.store.config.pairsForDevice(device.id);

    return FCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: theme.colors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _deviceIcon(device.type),
                    size: 18,
                    color: theme.colors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FTextField(
                        key: ValueKey<String>('devices.name.${device.id}'),
                        control: FTextFieldControl.managed(
                          controller: _name,
                          onChange: (value) =>
                              _update(device.copyWith(name: value.text)),
                        ),
                        hint: 'Device name',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        device.baseUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.typography.body.xs.copyWith(
                          fontFamily: 'monospace',
                          color: theme.colors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                FButton.icon(
                  key: ValueKey<String>('devices.delete.${device.id}'),
                  variant: FButtonVariant.ghost,
                  onPress: _deleteDevice,
                  semanticsTooltip: 'Remove device',
                  child: Icon(
                    FLucideIcons.trash2,
                    size: 15,
                    color: theme.colors.destructive,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _ChipRow<SyncDeviceType>(
                    label: 'DEVICE TYPE',
                    values: SyncDeviceType.values,
                    selected: device.type,
                    titleOf: _typeLabel,
                    keyOf: (type) => 'devices.type.${device.id}.${type.id}',
                    onSelect: (type) => _update(device.copyWith(type: type)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _ChipRow<SyncHostType>(
                    label: 'HOST TYPE',
                    values: SyncHostType.values,
                    selected: device.hostType,
                    titleOf: _hostTypeLabel,
                    keyOf: (type) => 'devices.host.${device.id}.${type.id}',
                    onSelect: (type) => _update(
                      device.copyWith(
                        hostType: type,
                        host: type == SyncHostType.local
                            ? '127.0.0.1'
                            : device.host,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (device.hostType == SyncHostType.remote)
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    flex: 3,
                    child: FTextField(
                      key: ValueKey<String>('devices.host.${device.id}'),
                      control: FTextFieldControl.managed(
                        controller: _host,
                        onChange: (value) =>
                            _update(device.copyWith(host: value.text.trim())),
                      ),
                      label: const Text('Host'),
                      hint: '192.168.1.10',
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 120,
                    child: FTextField(
                      key: ValueKey<String>('devices.port.${device.id}'),
                      control: FTextFieldControl.managed(
                        controller: _port,
                        onChange: (value) {
                          final port = int.tryParse(value.text);
                          if (port != null && port > 0 && port < 65536) {
                            _update(device.copyWith(port: port));
                          }
                        },
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      label: const Text('Port'),
                    ),
                  ),
                ],
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: theme.colors.muted.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      FLucideIcons.computer,
                      size: 14,
                      color: theme.colors.mutedForeground,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Runs on this machine · ${device.baseUrl}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.typography.body.xs.copyWith(
                          color: theme.colors.mutedForeground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Container(height: 1, color: theme.colors.border),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Pairs (${pairs.length})',
                  style: theme.typography.body.sm.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                FButton(
                  key: ValueKey<String>('devices.pair.add.${device.id}'),
                  variant: FButtonVariant.outline,
                  size: FButtonSizeVariant.sm,
                  onPress: _addPair,
                  prefix: const Icon(FLucideIcons.plus, size: 14),
                  child: const Text('Add pair'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (pairs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  'No pairs yet. Add one to choose a local folder and a mount.',
                  style: theme.typography.body.xs.copyWith(
                    color: theme.colors.mutedForeground,
                  ),
                ),
              )
            else
              FItemGroup(
                divider: FItemDivider.full,
                children: [
                  for (final pair in pairs)
                    FItem(
                      key: ValueKey<String>(
                        'devices.pair.${device.id}.${pair.name}',
                      ),
                      prefix: Icon(
                        FLucideIcons.folder,
                        size: 15,
                        color: theme.colors.mutedForeground,
                      ),
                      title: Text(
                        pair.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.typography.body.sm.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        pair.localRoot,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.typography.body.xs.copyWith(
                          fontFamily: 'monospace',
                          color: theme.colors.mutedForeground,
                        ),
                      ),
                      suffix: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FButton.icon(
                            key: ValueKey<String>(
                              'devices.pair.edit.${device.id}.${pair.name}',
                            ),
                            variant: FButtonVariant.ghost,
                            onPress: () => _editPair(pair),
                            semanticsTooltip: 'Edit pair',
                            child: const Icon(FLucideIcons.pencil, size: 14),
                          ),
                          FButton.icon(
                            key: ValueKey<String>(
                              'devices.pair.delete.${device.id}.${pair.name}',
                            ),
                            variant: FButtonVariant.ghost,
                            onPress: () => _deletePair(pair),
                            semanticsTooltip: 'Delete pair',
                            child: Icon(
                              FLucideIcons.trash2,
                              size: 14,
                              color: theme.colors.destructive,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ChipRow<T> extends StatelessWidget {
  const _ChipRow({
    required this.label,
    required this.values,
    required this.selected,
    required this.titleOf,
    required this.keyOf,
    required this.onSelect,
  });

  final String label;
  final List<T> values;
  final T selected;
  final String Function(T value) titleOf;
  final String Function(T value) keyOf;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.typography.body.xs.copyWith(
            color: theme.colors.mutedForeground,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final value in values)
              FButton(
                key: ValueKey<String>(keyOf(value)),
                variant: value == selected
                    ? FButtonVariant.secondary
                    : FButtonVariant.outline,
                size: FButtonSizeVariant.sm,
                mainAxisSize: MainAxisSize.min,
                onPress: () => onSelect(value),
                child: Text(titleOf(value)),
              ),
          ],
        ),
      ],
    );
  }
}

class _EmptyDevices extends StatelessWidget {
  const _EmptyDevices({required this.onAdd});

  final VoidCallback onAdd;

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
              FLucideIcons.router,
              size: 24,
              color: theme.colors.mutedForeground,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No peer devices yet.',
            style: theme.typography.body.md.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add a device to describe the peer and the mounts it shares.',
            style: theme.typography.body.sm.copyWith(
              color: theme.colors.mutedForeground,
            ),
          ),
          const SizedBox(height: 18),
          FButton(
            key: const ValueKey<String>('devices.emptyAdd'),
            onPress: onAdd,
            prefix: const Icon(FLucideIcons.plus, size: 16),
            child: const Text('Add device'),
          ),
        ],
      ),
    );
  }
}

IconData _deviceIcon(SyncDeviceType type) {
  return switch (type) {
    SyncDeviceType.windows => FLucideIcons.monitor,
    SyncDeviceType.macos => FLucideIcons.laptop,
    SyncDeviceType.linux => FLucideIcons.terminal,
    SyncDeviceType.android => FLucideIcons.smartphone,
  };
}

String _typeLabel(SyncDeviceType type) {
  return switch (type) {
    SyncDeviceType.windows => 'Windows',
    SyncDeviceType.macos => 'macOS',
    SyncDeviceType.linux => 'Linux',
    SyncDeviceType.android => 'Android',
  };
}

String _hostTypeLabel(SyncHostType type) {
  return type == SyncHostType.local ? 'Local' : 'Remote';
}
