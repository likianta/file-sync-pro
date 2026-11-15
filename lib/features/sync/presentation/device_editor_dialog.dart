import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../transport/http_transport.dart';
import '../application/sync_client_config.dart';

final class DeviceEditorResult {
  const DeviceEditorResult({
    required this.name,
    required this.host,
    required this.port,
    required this.hostType,
  });

  final String name;
  final String host;
  final int port;
  final SyncHostType hostType;
}

Future<DeviceEditorResult?> showDeviceEditorDialog({
  required BuildContext context,
  required Set<String> existingNames,
}) {
  return showFDialog<DeviceEditorResult>(
    context: context,
    barrierDismissible: false,
    builder: (context, style, animation) =>
        _DeviceEditorDialog(animation: animation, existingNames: existingNames),
  );
}

class _DeviceEditorDialog extends StatefulWidget {
  const _DeviceEditorDialog({
    required this.animation,
    required this.existingNames,
  });

  final Animation<double> animation;
  final Set<String> existingNames;

  @override
  State<_DeviceEditorDialog> createState() => _DeviceEditorDialogState();
}

class _DeviceEditorDialogState extends State<_DeviceEditorDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _token = TextEditingController();

  List<String> _mounts = const [];
  bool _detecting = false;
  String? _detectError;

  static const _mountItemHeight = 36.0;
  static const _maxMountsVisible = 3;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _token.dispose();
    super.dispose();
  }

  (String host, int port) _parseAddress(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return ('', SyncDeviceEntry.defaultPort);

    final uri = Uri.tryParse(text.contains('://') ? text : 'http://$text');
    if (uri != null && uri.hasPort) {
      return (uri.host, uri.port);
    }

    // Handle host:port without scheme
    final lastColon = text.lastIndexOf(':');
    if (lastColon > 0 && !text.substring(lastColon + 1).contains(':')) {
      final port = int.tryParse(text.substring(lastColon + 1));
      if (port != null && port > 0 && port < 65536) {
        return (text.substring(0, lastColon), port);
      }
    }
    return (text, SyncDeviceEntry.defaultPort);
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
    final (host, port) = _parseAddress(value);
    if (host.isEmpty) return 'Invalid address.';
    if (port <= 0 || port > 65535) return 'Port must be between 1 and 65535.';
    return null;
  }

  bool get _canConfirm {
    return _nameError == null && _addressError == null;
  }

  Future<void> _detectAccess() async {
    if (_detecting) return;
    if (_addressError != null) {
      setState(() => _detectError = _addressError);
      return;
    }

    final (host, port) = _parseAddress(_address.text);
    final baseUrl = 'http://$host:$port';
    final token = _token.text.trim();

    setState(() {
      _detecting = true;
      _detectError = null;
    });

    final transport = HttpTransport(
      baseUrl: baseUrl,
      token: token,
      timeout: const Duration(seconds: 15),
    );

    try {
      final json = await transport.getJson('');
      if (!mounted) return;
      final mounts = json['mounts'];
      setState(() {
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
      });
    } finally {
      await transport.close();
      if (mounted) {
        setState(() => _detecting = false);
      }
    }
  }

  void _confirm() {
    final (host, port) = _parseAddress(_address.text);
    final hostType = host == '127.0.0.1' || host == 'localhost' || host == '::1'
        ? SyncHostType.local
        : SyncHostType.remote;
    Navigator.of(context).pop(
      DeviceEditorResult(
        name: _name.text.trim(),
        host: host,
        port: port,
        hostType: hostType,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final mountsHeight = _mounts.isEmpty
        ? 0.0
        : (_mounts.length > _maxMountsVisible
              ? _maxMountsVisible * _mountItemHeight
              : _mounts.length * _mountItemHeight);

    return FDialog(
      animation: widget.animation,
      constraints: const BoxConstraints(minWidth: 480, maxWidth: 560),
      builder: (context, style) => Padding(
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
                    color: theme.colors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    FLucideIcons.router,
                    size: 16,
                    color: theme.colors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Text('Add device', style: style.titleTextStyle),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Enter the peer device address and shared token. "Detect access" '
              'verifies the connection and lists its mounts.',
              style: theme.typography.body.xs.copyWith(
                color: theme.colors.mutedForeground,
              ),
            ),
            const SizedBox(height: 18),
            _Field(
              label: 'Device name',
              child: FTextField(
                key: const ValueKey<String>('device.name'),
                control: FTextFieldControl.managed(
                  controller: _name,
                  onChange: (_) => setState(() {}),
                ),
                hint: "Likianta's Windows Computer in Office",
                error: _nameError == null ? null : Text(_nameError!),
              ),
            ),
            const SizedBox(height: 14),
            _Field(
              label: 'Address',
              child: FTextField(
                key: const ValueKey<String>('device.address'),
                control: FTextFieldControl.managed(
                  controller: _address,
                  onChange: (_) {
                    setState(() {
                      _mounts = const [];
                      _detectError = null;
                    });
                  },
                ),
                hint: '47.102.108.149:2160',
                keyboardType: TextInputType.url,
                error: _addressError == null ? null : Text(_addressError!),
              ),
            ),
            const SizedBox(height: 14),
            _Field(
              label: 'Secret token',
              child: FTextField.password(
                key: const ValueKey<String>('device.token'),
                control: FTextFieldControl.managed(controller: _token),
                hint: '24a3f252df3f151002dd7261036bbbcb54c3efbf214ad04d',
              ),
            ),

            // Animated mounts list
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _mounts.isEmpty && _detectError == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_detectError != null)
                            FAlert(
                              variant: FAlertVariant.destructive,
                              title: const Text('Cannot reach device'),
                              subtitle: Text(_detectError!),
                              icon: const Icon(FLucideIcons.circleAlert),
                            ),
                          if (_mounts.isNotEmpty) ...[
                            Row(
                              children: [
                                Icon(
                                  FLucideIcons.server,
                                  size: 14,
                                  color: theme.colors.mutedForeground,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Available mounts (${_mounts.length})',
                                  style: theme.typography.body.xs.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: theme.colors.mutedForeground,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: mountsHeight,
                              child: FItemGroup(
                                divider: FItemDivider.full,
                                children: [
                                  for (final mount in _mounts)
                                    FItem(
                                      prefix: Icon(
                                        FLucideIcons.folder,
                                        size: 14,
                                        color: theme.colors.mutedForeground,
                                      ),
                                      title: Text(
                                        mount,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.typography.body.sm
                                            .copyWith(fontFamily: 'monospace'),
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

            const SizedBox(height: 22),
            Row(
              children: [
                FButton(
                  key: const ValueKey<String>('device.detect'),
                  variant: FButtonVariant.outline,
                  onPress: _detecting ? null : _detectAccess,
                  prefix: _detecting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: FCircularProgress(),
                        )
                      : Icon(
                          FLucideIcons.rss,
                          size: 14,
                          color: theme.colors.mutedForeground,
                        ),
                  child: Text(_detecting ? 'Detecting...' : 'Detect access'),
                ),
                const Spacer(),
                FButton(
                  key: const ValueKey<String>('device.cancel'),
                  variant: FButtonVariant.ghost,
                  onPress: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FButton(
                  key: const ValueKey<String>('device.confirm'),
                  onPress: _canConfirm ? _confirm : null,
                  child: const Text('Add device'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(
            label,
            style: theme.typography.body.xs.copyWith(
              color: theme.colors.mutedForeground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        child,
      ],
    );
  }
}
