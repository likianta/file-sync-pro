import 'package:flutter/material.dart';

import '../../transport/http_transport.dart';
import '../application/sync_client_config.dart';

final class DeviceEditorResult {
  const DeviceEditorResult({
    required this.name,
    required this.host,
    required this.port,
    required this.hostType,
    this.platform,
  });

  final String name;
  final String host;
  final int port;
  final SyncHostType hostType;

  /// Platform reported by the peer while detecting access, if any.
  final SyncDeviceType? platform;
}

Future<DeviceEditorResult?> showDeviceEditorDialog({
  required BuildContext context,
  required Set<String> existingNames,
}) {
  return showDialog<DeviceEditorResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _DeviceEditorDialog(existingNames: existingNames),
  );
}

class _DeviceEditorDialog extends StatefulWidget {
  const _DeviceEditorDialog({required this.existingNames});

  final Set<String> existingNames;

  @override
  State<_DeviceEditorDialog> createState() => _DeviceEditorDialogState();
}

class _DeviceEditorDialogState extends State<_DeviceEditorDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _token = TextEditingController();

  List<String> _mounts = const [];
  SyncDeviceType? _platform;
  bool _detecting = false;
  String? _detectError;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _token.dispose();
    super.dispose();
  }

  String? get _nameError {
    final value = _name.text.trim();
    if (value.isEmpty) return 'Device name is required.';
    if (widget.existingNames.contains(value)) {
      return 'A device with this name already exists.';
    }
    return null;
  }

  String? get _addressError {
    final value = _address.text.trim();
    if (value.isEmpty) return 'Address is required.';
    final (host, port) = SyncDeviceEntry.parseAddress(value);
    if (host.isEmpty) return 'Invalid address.';
    if (port <= 0 || port > 65535) return 'Port must be between 1 and 65535.';
    return null;
  }

  bool get _canConfirm => _nameError == null && _addressError == null;

  Future<void> _detectAccess() async {
    if (_detecting) return;
    if (_addressError != null) {
      setState(() => _detectError = _addressError);
      return;
    }

    final (host, port) = SyncDeviceEntry.parseAddress(_address.text);
    final transport = HttpTransport(
      baseUrl: 'http://$host:$port',
      token: _token.text.trim(),
      timeout: const Duration(seconds: 15),
    );

    setState(() {
      _detecting = true;
      _detectError = null;
    });

    try {
      final json = await transport.getJson('');
      if (!mounted) return;
      final mounts = json['mounts'];
      setState(() {
        _platform = SyncDeviceType.tryParse(json['platform']);
        _mounts = mounts is List
            ? mounts.whereType<String>().toList(growable: false)
            : const [];
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _detectError = error is RemoteException
            ? '${error.statusCode}: ${error.message}'
            : error.toString();
        _mounts = const [];
        _platform = null;
      });
    } finally {
      await transport.close();
      if (mounted) {
        setState(() => _detecting = false);
      }
    }
  }

  void _confirm() {
    final (host, port) = SyncDeviceEntry.parseAddress(_address.text);
    final hostType = host == '127.0.0.1' || host == 'localhost' || host == '::1'
        ? SyncHostType.local
        : SyncHostType.remote;
    Navigator.of(context).pop(
      DeviceEditorResult(
        name: _name.text.trim(),
        host: host,
        port: port,
        hostType: hostType,
        platform: _platform,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
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
                      Icons.router_outlined,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Add device',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Enter the peer device address and shared token. "Detect '
                'access" verifies the connection and lists its mounts.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                key: const ValueKey<String>('device.name'),
                controller: _name,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Device name',
                  hintText: "Likianta's Windows Computer in Office",
                  errorText: _nameError,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey<String>('device.address'),
                controller: _address,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'Address',
                  hintText: '47.102.108.149:2160',
                  errorText: _addressError,
                ),
                onChanged: (_) {
                  setState(() {
                    _mounts = const [];
                    _detectError = null;
                  });
                },
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey<String>('device.token'),
                controller: _token,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Secret token',
                  hintText: '24a3f252df3f151002dd7261036bbbcb54c3efbf214ad04d',
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _mounts.isEmpty && _detectError == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_detectError != null)
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.errorContainer
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Cannot reach device: $_detectError',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onErrorContainer,
                                  ),
                                ),
                              ),
                            if (_mounts.isNotEmpty) ...[
                              Row(
                                children: [
                                  Icon(
                                    Icons.dns_outlined,
                                    size: 14,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Available mounts (${_mounts.length})',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Container(
                                constraints: const BoxConstraints(
                                  maxHeight: 112,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: theme.colorScheme.outlineVariant,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ListView(
                                  shrinkWrap: true,
                                  padding: EdgeInsets.zero,
                                  children: [
                                    for (final mount in _mounts)
                                      ListTile(
                                        dense: true,
                                        leading: const Icon(
                                          Icons.folder_outlined,
                                          size: 16,
                                        ),
                                        title: Text(
                                          mount,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                fontFamily: 'monospace',
                                              ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey<String>('device.detect'),
                    onPressed: _detecting ? null : _detectAccess,
                    icon: _detecting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_tethering, size: 16),
                    label: Text(_detecting ? 'Detecting...' : 'Detect access'),
                  ),
                  const Spacer(),
                  TextButton(
                    key: const ValueKey<String>('device.cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey<String>('device.confirm'),
                    onPressed: _canConfirm ? _confirm : null,
                    child: const Text('Add device'),
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
