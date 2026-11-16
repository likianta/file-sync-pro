import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/ui.dart';
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        if (_loadError != null) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: AppErrorBanner(
                  message: 'Cannot read server config: $_loadError',
                ),
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
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  'Loading settings...',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildConnectionCard(context),
                        if (_controller.errorMessage != null) ...[
                          const SizedBox(height: 12),
                          AppErrorBanner(
                            message:
                                'File server error: '
                                '${_controller.errorMessage}',
                            onDismiss: _controller.clearError,
                          ),
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
    final theme = Theme.of(context);
    final running = _controller.status == FileServerStatus.running;
    final color = _controller.status == FileServerStatus.error
        ? theme.colorScheme.error
        : running
        ? const Color(0xFF2EA121)
        : theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.dns_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'File server',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Share folders with other devices over HTTP on the LAN.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            key: const ValueKey<String>('server.run'),
            onPressed: _controller.isRunning
                ? _controller.stop
                : _controller.start,
            icon: Icon(
              _controller.isRunning ? Icons.stop : Icons.play_arrow,
              size: 17,
            ),
            label: Text(
              _controller.isRunning ? 'Stop server' : 'Run file server',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.settings_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 7),
                Text(
                  'Connection',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Bind address and the token every client must send.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey<String>('server.token'),
              controller: _tokenController,
              enabled: !_controller.isRunning,
              obscureText: _obscureToken,
              decoration: InputDecoration(
                labelText: 'Input token',
                helperText:
                    'Clients must use the same token. It is required '
                    'before the server starts.',
                suffixIcon: IconButton(
                  tooltip: _obscureToken ? 'Show token' : 'Hide token',
                  onPressed: () =>
                      setState(() => _obscureToken = !_obscureToken),
                  icon: Icon(
                    _obscureToken ? Icons.visibility_off : Icons.visibility,
                    size: 17,
                  ),
                ),
              ),
              onChanged: (value) => _controller.updateToken(value),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 3,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Local IPv4',
                      helperText: 'Shown for reference; binding uses 0.0.0.0.',
                      isDense: true,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value:
                            _controller.addresses.contains(
                              _controller.selectedIp,
                            )
                            ? _controller.selectedIp
                            : null,
                        isDense: true,
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(10),
                        hint: const Text('No IPv4 address found'),
                        items: [
                          for (final address in _controller.addresses)
                            DropdownMenuItem<String>(
                              value: address,
                              child: Text(address),
                            ),
                        ],
                        onChanged: _controller.isRunning
                            ? null
                            : (value) {
                                if (value == null) return;
                                _controller.selectAddress(value);
                                _ipController.text = value;
                              },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: TextField(
                    key: const ValueKey<String>('server.port'),
                    controller: _portController,
                    enabled: !_controller.isRunning,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Port'),
                    onChanged: (value) {
                      final port = int.tryParse(value);
                      if (port != null && port > 0 && port < 65536) {
                        _controller.updatePort(port);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  key: const ValueKey<String>('server.refreshIp'),
                  onPressed: _controller.isRunning
                      ? null
                      : () async {
                          await _controller.refreshAddresses();
                          _ipController.text = _controller.selectedIp ?? '';
                        },
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Refresh IP'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'The server listens on 0.0.0.0:${_controller.config.port}. '
              'Expose this port with your own frp/tunnel. Do not expose it '
              'without a token.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMountsCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
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
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Each folder is exposed as a named mount.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  key: const ValueKey<String>('server.addMount'),
                  onPressed: _controller.isRunning ? null : _addMount,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add folder'),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          if (_controller.config.mounts.isEmpty)
            Padding(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: Text(
                  'No folders yet. Click "Add folder" to share one.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            Column(
              children: [
                for (
                  var index = 0;
                  index < _controller.config.mounts.length;
                  index++
                )
                  _mountRow(context, index),
              ],
            ),
        ],
      ),
    );
  }

  Widget _mountRow(BuildContext context, int index) {
    final theme = Theme.of(context);
    final mount = _controller.config.mounts[index];
    final editing = _editingIndex == index;
    final nameEditable = !_controller.isRunning;

    return Container(
      key: ValueKey<String>('server.mount.$index'),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        border: Border(
          top: index == 0
              ? BorderSide.none
              : BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.folder_outlined,
            size: 17,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                editing
                    ? Row(
                        children: [
                          SizedBox(
                            width: 200,
                            child: TextField(
                              key: ValueKey<String>(
                                'server.mount.nameField.$index',
                              ),
                              controller: _nameController,
                              autofocus: true,
                              decoration: const InputDecoration(isDense: true),
                              onSubmitted: (_) => _commitName(index),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            key: ValueKey<String>('server.mount.nameOk.$index'),
                            tooltip: 'Save name',
                            onPressed: () => _commitName(index),
                            icon: const Icon(Icons.check, size: 16),
                          ),
                          IconButton(
                            key: ValueKey<String>(
                              'server.mount.nameCancel.$index',
                            ),
                            tooltip: 'Cancel',
                            onPressed: () =>
                                setState(() => _editingIndex = null),
                            icon: const Icon(Icons.close, size: 16),
                          ),
                        ],
                      )
                    : Text(
                        mount.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                const SizedBox(height: 2),
                Text(
                  mount.path.isEmpty ? 'Choose a folder...' : mount.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey<String>('server.mount.edit.$index'),
            tooltip: 'Rename',
            onPressed: nameEditable
                ? () {
                    _nameController.text = mount.name;
                    setState(() => _editingIndex = index);
                  }
                : null,
            icon: const Icon(Icons.edit_outlined, size: 16),
          ),
          IconButton(
            key: ValueKey<String>('server.mount.browse.$index'),
            tooltip: 'Browse',
            onPressed: _controller.isRunning ? null : () => _browse(index),
            icon: const Icon(Icons.folder_open_outlined, size: 16),
          ),
          IconButton(
            key: ValueKey<String>('server.mount.delete.$index'),
            tooltip: 'Remove',
            onPressed: _controller.isRunning
                ? null
                : () => _controller.removeMount(index),
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
