import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import 'file_server_controller.dart';

class FileServerPage extends StatefulWidget {
  const FileServerPage({
    super.key,
    required this.configPath,
    required this.projectRoot,
  });

  final String configPath;
  final String projectRoot;

  @override
  State<FileServerPage> createState() => _FileServerPageState();
}

class _FileServerPageState extends State<FileServerPage> {
  late final FileServerController _controller;
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  int? _editingIndex;
  bool _obscureToken = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _controller = FileServerController(
      configPath: widget.configPath,
      projectRoot: widget.projectRoot,
    );
    _load();
  }

  Future<void> _load() async {
    try {
      await _controller.load();
      _tokenController.text = _controller.config.token;
      _portController.text = _controller.config.port.toString();
      _ipController.text = _controller.selectedIp ?? '';
    } catch (error) {
      if (mounted) {
        setState(() => _loadError = error.toString());
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _tokenController.dispose();
    _portController.dispose();
    _ipController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (_loadError != null) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: FAlert(
                variant: FAlertVariant.destructive,
                title: const Text('Cannot read server config'),
                subtitle: Text(_loadError!),
                icon: const Icon(FLucideIcons.circleAlert),
              ),
            ),
          );
        }
        if (!_controller.loaded) {
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
                  'Loading settings...',
                  style: theme.typography.body.sm.copyWith(
                    color: theme.colors.mutedForeground,
                  ),
                ),
              ],
            ),
          );
        }
        return Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildConnectionCard(context),
                        if (_controller.errorMessage != null) ...[
                          const SizedBox(height: 12),
                          _buildError(context),
                        ],
                        const SizedBox(height: 14),
                        _buildMountsCard(context),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = context.theme;
    final running = _controller.status == FileServerStatus.running;
    final color = _controller.status == FileServerStatus.error
        ? theme.colors.destructive
        : running
        ? const Color(0xFF2EA121)
        : theme.colors.mutedForeground;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: theme.colors.background,
        border: Border(bottom: BorderSide(color: theme.colors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: theme.colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              FLucideIcons.server,
              size: 16,
              color: theme.colors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'File server',
                  style: theme.typography.body.xl.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'Share folders with other devices over HTTP on the LAN.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.typography.body.sm.copyWith(
                    color: theme.colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            _controller.statusLabel,
            style: theme.typography.body.sm.copyWith(
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 12),
          FButton(
            key: const ValueKey<String>('server.run'),
            onPress: _controller.isRunning
                ? _controller.stop
                : _controller.start,
            prefix: Icon(
              _controller.isRunning ? FLucideIcons.square : FLucideIcons.play,
              size: 15,
            ),
            child: Text(
              _controller.isRunning ? 'Stop server' : 'Run file server',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionCard(BuildContext context) {
    final theme = context.theme;
    return FCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  FLucideIcons.settings,
                  size: 15,
                  color: theme.colors.mutedForeground,
                ),
                const SizedBox(width: 7),
                Text(
                  'Connection',
                  style: theme.typography.body.md.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Bind address and the token every client must send.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.typography.body.xs.copyWith(
                      color: theme.colors.mutedForeground,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FTextField(
              key: const ValueKey<String>('server.token'),
              control: FTextFieldControl.managed(
                controller: _tokenController,
                onChange: (value) => _controller.updateToken(value.text),
              ),
              enabled: !_controller.isRunning,
              obscureText: _obscureToken,
              label: const Text('Input token'),
              description: const Text(
                'Clients must use the same token. It is required before the '
                'server starts.',
              ),
              suffixBuilder: (context, style, variants) => FButton.icon(
                variant: FButtonVariant.ghost,
                onPress: () => setState(() => _obscureToken = !_obscureToken),
                semanticsTooltip: _obscureToken ? 'Show token' : 'Hide token',
                child: Icon(
                  _obscureToken ? FLucideIcons.eye : FLucideIcons.eyeOff,
                  size: 15,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 3,
                  child: FSelect<String>(
                    key: const ValueKey<String>('server.ip'),
                    control: FSelectControl<String>.lifted(
                      value: _controller.selectedIp,
                      onChange: (value) {
                        if (value == null) return;
                        _controller.selectAddress(value);
                        _ipController.text = value;
                      },
                    ),
                    items: {
                      for (final address in _controller.addresses)
                        address: address,
                    },
                    enabled: !_controller.isRunning,
                    label: const Text('Local IPv4'),
                    description: const Text(
                      'Shown for reference; binding uses 0.0.0.0.',
                    ),
                    hint: 'No IPv4 address found',
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 116,
                  child: FTextField(
                    key: const ValueKey<String>('server.port'),
                    control: FTextFieldControl.managed(
                      controller: _portController,
                      onChange: (value) {
                        final port = int.tryParse(value.text);
                        if (port != null && port > 0 && port < 65536) {
                          _controller.updatePort(port);
                        }
                      },
                    ),
                    enabled: !_controller.isRunning,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    label: const Text('Port'),
                  ),
                ),
                const SizedBox(width: 12),
                FButton(
                  key: const ValueKey<String>('server.refreshIp'),
                  variant: FButtonVariant.outline,
                  onPress: _controller.isRunning
                      ? null
                      : () async {
                          await _controller.refreshAddresses();
                          _ipController.text = _controller.selectedIp ?? '';
                        },
                  prefix: const Icon(FLucideIcons.refreshCw, size: 15),
                  child: const Text('Refresh IP'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'The server listens on 0.0.0.0:${_controller.config.port}. '
              'Expose this port with your own frp/tunnel. Do not expose it '
              'without a token.',
              style: theme.typography.body.xs.copyWith(
                color: theme.colors.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: FAlert(
            variant: FAlertVariant.destructive,
            title: const Text('File server error'),
            subtitle: Text(_controller.errorMessage!),
            icon: const Icon(FLucideIcons.circleAlert),
          ),
        ),
        const SizedBox(width: 8),
        FButton.icon(
          key: const ValueKey<String>('server.error.dismiss'),
          variant: FButtonVariant.ghost,
          onPress: _controller.clearError,
          semanticsTooltip: 'Dismiss',
          child: const Icon(FLucideIcons.x, size: 15),
        ),
      ],
    );
  }

  Widget _buildMountsCard(BuildContext context) {
    final theme = context.theme;
    return FCard(
      style: FCardStyleDelta.delta(
        padding: EdgeInsetsGeometryDelta.value(EdgeInsets.zero),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Shared folders',
                        style: theme.typography.body.md.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Each folder is exposed as a named mount.',
                        style: theme.typography.body.xs.copyWith(
                          color: theme.colors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                FButton(
                  key: const ValueKey<String>('server.addMount'),
                  variant: FButtonVariant.outline,
                  onPress: _controller.isRunning ? null : _addMount,
                  prefix: const Icon(FLucideIcons.plus, size: 15),
                  child: const Text('Add folder'),
                ),
              ],
            ),
          ),
          Container(height: 1, color: theme.colors.border),
          if (_controller.config.mounts.isEmpty)
            Padding(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: Text(
                  'No folders yet. Click "Add folder" to share one.',
                  style: theme.typography.body.sm.copyWith(
                    color: theme.colors.mutedForeground,
                  ),
                ),
              ),
            )
          else
            FItemGroup(
              divider: FItemDivider.full,
              children: [
                for (
                  var index = 0;
                  index < _controller.config.mounts.length;
                  index++
                )
                  _mountItem(context, index),
              ],
            ),
        ],
      ),
    );
  }

  FItem _mountItem(BuildContext context, int index) {
    final theme = context.theme;
    final mount = _controller.config.mounts[index];
    final editing = _editingIndex == index;
    final nameEditable = !_controller.isRunning;

    return FItem(
      key: ValueKey<String>('server.mount.$index'),
      prefix: Icon(
        FLucideIcons.folder,
        size: 15,
        color: theme.colors.mutedForeground,
      ),
      title: editing
          ? Row(
              children: [
                SizedBox(
                  width: 200,
                  child: FTextField(
                    key: ValueKey<String>('server.mount.nameField.$index'),
                    control: FTextFieldControl.managed(
                      controller: _nameController,
                    ),
                    autofocus: true,
                    onSubmit: (_) => _commitName(index),
                  ),
                ),
                const SizedBox(width: 6),
                FButton.icon(
                  key: ValueKey<String>('server.mount.nameOk.$index'),
                  variant: FButtonVariant.ghost,
                  onPress: () => _commitName(index),
                  semanticsTooltip: 'Save name',
                  child: const Icon(FLucideIcons.check, size: 15),
                ),
                FButton.icon(
                  key: ValueKey<String>('server.mount.nameCancel.$index'),
                  variant: FButtonVariant.ghost,
                  onPress: () => setState(() => _editingIndex = null),
                  semanticsTooltip: 'Cancel',
                  child: const Icon(FLucideIcons.x, size: 15),
                ),
              ],
            )
          : Text(
              mount.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.body.sm.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
      subtitle: Text(
        mount.path.isEmpty ? 'Choose a folder...' : mount.path,
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
            key: ValueKey<String>('server.mount.edit.$index'),
            variant: FButtonVariant.ghost,
            onPress: nameEditable
                ? () {
                    _nameController.text = mount.name;
                    setState(() => _editingIndex = index);
                  }
                : null,
            semanticsTooltip: 'Rename',
            child: const Icon(FLucideIcons.pencil, size: 14),
          ),
          FButton.icon(
            key: ValueKey<String>('server.mount.browse.$index'),
            variant: FButtonVariant.ghost,
            onPress: _controller.isRunning ? null : () => _browse(index),
            semanticsTooltip: 'Browse',
            child: const Icon(FLucideIcons.folderOpen, size: 14),
          ),
          FButton.icon(
            key: ValueKey<String>('server.mount.delete.$index'),
            variant: FButtonVariant.ghost,
            onPress: _controller.isRunning
                ? null
                : () => _controller.removeMount(index),
            semanticsTooltip: 'Remove',
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

  Future<void> _addMount() async {
    await _controller.addMount();
    final index = _controller.config.mounts.length - 1;
    _nameController.text = _controller.config.mounts[index].name;
    setState(() => _editingIndex = index);
  }

  Future<void> _commitName(int index) async {
    await _controller.renameMount(index, _nameController.text);
    setState(() => _editingIndex = null);
  }

  Future<void> _browse(int index) async {
    final current = _controller.config.mounts[index].path;
    final initial = current.isNotEmpty && Directory(current).existsSync()
        ? current
        : widget.projectRoot;
    final path = await getDirectoryPath(
      initialDirectory: initial,
      confirmButtonText: 'Select folder',
    );
    if (path == null) return;
    await _controller.updateMountPath(index, path);
  }
}
