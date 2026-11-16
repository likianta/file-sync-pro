import 'dart:math' as math;

import 'package:flutter/material.dart';

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
                        const minColumn = 240.0;
                        const spacing = 14.0;
                        final width = constraints.maxWidth;
                        final crossAxisCount = math.max(
                          1,
                          ((width + spacing) / (minColumn + spacing)).floor(),
                        );
                        final cardWidth =
                            (width - spacing * (crossAxisCount - 1)) /
                            crossAxisCount;

                        return SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                            child: _MasonryFlow(
                              crossAxisCount: crossAxisCount,
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
                  'Peers this machine syncs with, and the folders shared with '
                  'each of them.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
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
    final confirmed = await _confirm(
      context,
      title: 'Remove device?',
      message:
          '"${widget.device.name}" and its ${widget.store.config.pairsForDevice(widget.device.id).length} '
          'pair(s) will be removed from this device. Files are not deleted.',
      confirmLabel: 'Remove',
      confirmKey: const ValueKey<String>('devices.deleteConfirm'),
    );
    if (confirmed) {
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
      widget.store.removePair(pair.name);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final device = widget.device;
    final pairs = widget.store.config.pairsForDevice(device.id);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 140),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _CapsuleTag(
                          label: device.type.label,
                          color: const Color(0xFF2563EB),
                          tint: const Color(0xFFDBEAFE),
                        ),
                        _CapsuleTag(
                          label: device.hostType == SyncHostType.local
                              ? 'Local'
                              : 'Remote',
                          color: const Color(0xFF7C3AED),
                          tint: const Color(0xFFEDE9FE),
                        ),
                        _CapsuleTag(
                          label: device.createdMonthLabel,
                          color: const Color(0xFF059669),
                          tint: const Color(0xFFD1FAE5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: ValueKey<String>('devices.name.${device.id}'),
                      controller: _nameController,
                      style: theme.textTheme.bodyMedium,
                      decoration: const InputDecoration(
                        hintText: 'Device name',
                        isDense: true,
                      ),
                      onChanged: (value) =>
                          _update(device.copyWith(name: value)),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.language,
                          size: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            device.baseUrl,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 150,
                  child: DeviceModel3D(model: device.resolvedModel),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Pairs (${pairs.length})',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  key: ValueKey<String>('devices.pair.add.${device.id}'),
                  onPressed: _addPair,
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('Add'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Builder(
              builder: (context) {
                const maxRows = 5;
                const rowHeight = 30.0;
                final maxHeight = rowHeight * maxRows;

                if (pairs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      'No pairs yet.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }

                final column = Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                );

                if (pairs.length <= maxRows) return column;

                return SizedBox(
                  height: maxHeight,
                  child: SingleChildScrollView(child: column),
                );
              },
            ),
            const SizedBox(height: 10),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 8),
            Row(
              spacing: 6,
              children: [
                Icon(
                  Icons.monitor_outlined,
                  size: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                Expanded(
                  child: _ModelDropdown(
                    model: device.resolvedModel,
                    onChanged: (value) {
                      _update(device.copyWith(model: value));
                    },
                  ),
                ),
                IconButton(
                  key: ValueKey<String>('devices.delete.${device.id}'),
                  tooltip: 'Remove device',
                  onPressed: _deleteDevice,
                  icon: Icon(
                    Icons.delete_outline,
                    size: 17,
                    color: theme.colorScheme.error,
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

class _ModelDropdown extends StatelessWidget {
  const _ModelDropdown({required this.model, required this.onChanged});

  final SyncDeviceModel model;
  final ValueChanged<SyncDeviceModel> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: model.name,
        isDense: true,
        isExpanded: true,
        borderRadius: BorderRadius.circular(10),
        style: theme.textTheme.bodySmall,
        items: [
          for (final item in SyncDeviceModel.values)
            DropdownMenuItem<String>(
              value: item.name,
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (value) {
          if (value == null) return;
          onChanged(
            SyncDeviceModel.values.firstWhere((item) => item.name == value),
          );
        },
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
              Icons.router_outlined,
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
