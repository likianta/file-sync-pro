import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../application/sync_client_config.dart';
import '../application/sync_config_store.dart';
import 'device_editor_dialog.dart';
import 'device_model_3d.dart';
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
    final hostType = result.hostType;
    final type = _inferTypeFromHost(hostType, result.host);
    store.addDeviceFromInput(
      name: result.name,
      host: result.host,
      port: result.port,
      hostType: hostType,
      type: type,
    );
  }

  static SyncDeviceType _inferTypeFromHost(SyncHostType hostType, String host) {
    // Best guess from address — localhost means this machine (assume macOS
    // during development). Remote addresses stay as "windows" fallback until
    // the model is edited.
    if (hostType == SyncHostType.local) return SyncDeviceType.macos;
    return SyncDeviceType.windows;
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
            _PageHeader(onAdd: _openAddDeviceDialog),
            Expanded(
              child: devices.isEmpty
                  ? _EmptyDevices(onAdd: _openAddDeviceDialog)
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        // Each column is ~400 wide, clamped to 300..500.
                        const minColumn = 300.0;
                        const maxColumn = 500.0;
                        const spacing = 14.0;
                        final width = constraints.maxWidth;
                        final count = math.max(
                          1,
                          ((width + spacing) / (minColumn + spacing)).floor(),
                        );
                        final columnWidth =
                            (width - spacing * (count - 1)) / count;
                        final crossAxisCount = columnWidth > maxColumn
                            ? ((width + spacing) / (maxColumn + spacing))
                                  .floor()
                                  .clamp(1, 5)
                            : count;
                        return GridView.count(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: spacing,
                          crossAxisSpacing: spacing,
                          childAspectRatio: 0.72,
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
  const _DeviceCard({super.key, required this.store, required this.device});

  final SyncConfigStore store;
  final SyncDeviceEntry device;

  @override
  State<_DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<_DeviceCard> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.device.name);
  }

  @override
  void didUpdateWidget(covariant _DeviceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device.id != widget.device.id) {
      _nameController.text = widget.device.name;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
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
      showFToast(
        context: context,
        title: Text('A pair named "${result.entry.name}" already exists.'),
        icon: const Icon(FLucideIcons.circleAlert),
      );
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
      showFToast(
        context: context,
        title: Text('A pair named "${result.entry.name}" already exists.'),
        icon: const Icon(FLucideIcons.circleAlert),
      );
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

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final device = widget.device;
    final pairs = widget.store.config.pairsForDevice(device.id);

    return FCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 3D model illustration — trailing shadow extends below this
              // SizedBox into the tag row, creating the "pressing" overlap.
              SizedBox(
                height: 140,
                child: DeviceModel3D(model: device.resolvedModel),
              ),
              Transform.translate(
                offset: const Offset(0, -22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Tag row
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _CapsuleTag(
                          label: device.type.label,
                          color: _platformColor(device.type, theme),
                        ),
                        _CapsuleTag(
                          label: device.hostType == SyncHostType.local
                              ? 'Local'
                              : 'Remote',
                          color: device.hostType == SyncHostType.local
                              ? const Color(0xFF059669)
                              : const Color(0xFF2563EB),
                        ),
                        _CapsuleTag(
                          label: device.createdMonthLabel,
                          color: theme.colors.mutedForeground,
                          filled: false,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Device name (editable)
                    FTextField(
                      key: ValueKey<String>('devices.name.${device.id}'),
                      control: FTextFieldControl.managed(
                        controller: _nameController,
                        onChange: (value) =>
                            _update(device.copyWith(name: value.text)),
                      ),
                    ),
                    const SizedBox(height: 2),

                    // Device address
                    Row(
                      children: [
                        Icon(
                          FLucideIcons.globe,
                          size: 13,
                          color: theme.colors.mutedForeground,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            device.baseUrl,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.typography.body.xs.copyWith(
                              fontFamily: 'monospace',
                              color: theme.colors.mutedForeground,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(height: 1, color: theme.colors.border),
                    const SizedBox(height: 8),

                    // Pairs header
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
                          key: ValueKey<String>(
                            'devices.pair.add.${device.id}',
                          ),
                          variant: FButtonVariant.outline,
                          size: FButtonSizeVariant.sm,
                          onPress: _addPair,
                          prefix: const Icon(FLucideIcons.plus, size: 14),
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Pairs list (compact)
                    if (pairs.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No pairs yet.',
                          style: theme.typography.body.xs.copyWith(
                            color: theme.colors.mutedForeground,
                          ),
                        ),
                      )
                    else ...[
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
                    ],

                    const SizedBox(height: 10),
                    Container(height: 1, color: theme.colors.border),
                    const SizedBox(height: 8),

                    // Footer bar: model switcher + delete
                    Row(
                      children: [
                        Icon(
                          FLucideIcons.monitor,
                          size: 13,
                          color: theme.colors.mutedForeground,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: _ModelDropdown(
                            model: device.resolvedModel,
                            onChanged: (value) {
                              _update(device.copyWith(model: value));
                            },
                          ),
                        ),
                        FButton.icon(
                          key: ValueKey<String>('devices.delete.${device.id}'),
                          variant: FButtonVariant.ghost,
                          onPress: _deleteDevice,
                          semanticsTooltip: 'Remove device',
                          child: Icon(
                            FLucideIcons.trash2,
                            size: 14,
                            color: theme.colors.destructive,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CapsuleTag extends StatelessWidget {
  const _CapsuleTag({
    required this.label,
    required this.color,
    this.filled = true,
  });

  final String label;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: filled ? null : Border.all(color: theme.colors.border),
      ),
      child: Text(
        label,
        style: theme.typography.body.xs.copyWith(
          fontWeight: FontWeight.w600,
          color: filled ? color : theme.colors.mutedForeground,
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
    final theme = context.theme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colors.muted.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            FLucideIcons.folder,
            size: 14,
            color: theme.colors.mutedForeground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              pair.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.body.sm.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          FButton.icon(
            key: ValueKey<String>('devices.pair.edit.$deviceId.${pair.name}'),
            variant: FButtonVariant.ghost,
            onPress: onEdit,
            semanticsTooltip: 'Edit pair',
            child: const Icon(FLucideIcons.settings, size: 14),
          ),
          FButton.icon(
            key: ValueKey<String>('devices.pair.delete.$deviceId.${pair.name}'),
            variant: FButtonVariant.ghost,
            onPress: onDelete,
            semanticsTooltip: 'Delete pair',
            child: Icon(
              FLucideIcons.trash2,
              size: 14,
              color: theme.colors.destructive,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelDropdown extends StatelessWidget {
  const _ModelDropdown({required this.model, required this.onChanged});

  final SyncDeviceModel model;
  final ValueChanged<SyncDeviceModel> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return FButton(
      variant: FButtonVariant.ghost,
      size: FButtonSizeVariant.sm,
      onPress: () async {
        final selected = await showFDialog<SyncDeviceModel>(
          context: context,
          builder: (context, style, animation) => FDialog(
            animation: animation,
            constraints: const BoxConstraints(minWidth: 260, maxWidth: 300),
            builder: (context, style) => Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Device model', style: style.titleTextStyle),
                  const SizedBox(height: 12),
                  for (final m in SyncDeviceModel.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: FButton(
                        variant: m == model
                            ? FButtonVariant.secondary
                            : FButtonVariant.outline,
                        onPress: () => Navigator.of(context).pop(m),
                        child: Text(m.label),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
        if (selected != null) onChanged(selected);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              model.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.body.xs.copyWith(
                color: theme.colors.mutedForeground,
              ),
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            FLucideIcons.chevronsUpDown,
            size: 12,
            color: theme.colors.mutedForeground,
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

Color _platformColor(SyncDeviceType type, FThemeData theme) {
  return switch (type) {
    SyncDeviceType.windows => const Color(0xFF3B82F6),
    SyncDeviceType.macos => const Color(0xFF6B7280),
    SyncDeviceType.linux => const Color(0xFF10B981),
    SyncDeviceType.android => const Color(0xFF4ADE80),
    SyncDeviceType.ios => const Color(0xFF0EA5E9),
    SyncDeviceType.ipad => const Color(0xFF0284C7),
  };
}
