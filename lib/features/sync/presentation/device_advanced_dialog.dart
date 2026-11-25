import 'package:flutter/material.dart';

import '../application/sync_client_config.dart';
import '../application/sync_config_store.dart';

/// Full settings for one device. Name and address live on the card; this
/// dialog holds the rarely used fields and the remove action.
Future<void> showDeviceAdvancedDialog({
  required BuildContext context,
  required SyncConfigStore store,
  required SyncDeviceEntry device,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _DeviceAdvancedDialog(store: store, device: device),
  );
}

class _DeviceAdvancedDialog extends StatefulWidget {
  const _DeviceAdvancedDialog({required this.store, required this.device});

  final SyncConfigStore store;
  final SyncDeviceEntry device;

  @override
  State<_DeviceAdvancedDialog> createState() => _DeviceAdvancedDialogState();
}

class _DeviceAdvancedDialogState extends State<_DeviceAdvancedDialog> {
  late SyncDeviceType _type = widget.device.type;

  void _save() {
    widget.store.updateDevice(widget.device.copyWith(type: _type));
    Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove device?'),
        content: Text(
          '${widget.device.name} and its ${widget.device.pairs.length} '
          'pair(s) will be removed from this config. Files are untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey<String>('devices.advanced.remove.confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    widget.store.removeDevice(widget.device.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final device = widget.device;
    return Dialog(
      key: const ValueKey<String>('devices.advanced.dialog'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.tune,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Advanced settings',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Device name and address are edited on the card. These fields '
                'are only used when the peer cannot be probed.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<SyncDeviceType>(
                key: const ValueKey<String>('devices.advanced.type'),
                initialValue: _type,
                decoration: const InputDecoration(
                  labelText: 'Device type (fallback)',
                ),
                items: [
                  for (final type in SyncDeviceType.values)
                    DropdownMenuItem(value: type, child: Text(type.label)),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _type = value);
                },
              ),
              const SizedBox(height: 14),
              _ReadOnlyField(label: 'Device id', value: device.id),
              if (device.platform != null) ...[
                const SizedBox(height: 10),
                _ReadOnlyField(
                  label: 'Reported platform',
                  value: device.platform!.label,
                ),
              ],
              const SizedBox(height: 10),
              _ReadOnlyField(
                label: 'Host type',
                value: device.isLocal ? 'Local' : 'Remote',
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  TextButton.icon(
                    key: const ValueKey<String>('devices.advanced.remove'),
                    onPressed: _remove,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Remove device'),
                  ),
                  const Spacer(),
                  TextButton(
                    key: const ValueKey<String>('devices.advanced.cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey<String>('devices.advanced.save'),
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'Menlo',
              fontFamilyFallback: const ['Consolas', 'Courier New'],
            ),
          ),
        ],
      ),
    );
  }
}
