import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
        if (_loadError != null) {
          return Scaffold(
            body: Center(
              child: Text(
                'Cannot read server config:\n$_loadError',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!_controller.loaded) {
          return const Scaffold(
            body: Center(child: Text('Loading settings...')),
          );
        }
        return Scaffold(
          body: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildConnectionCard(context),
                          if (_controller.errorMessage != null) ...[
                            const SizedBox(height: 12),
                            _buildError(context),
                          ],
                          const SizedBox(height: 16),
                          _buildMountsCard(context),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
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
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.dns_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'File server',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Share folders with other devices on this machine',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            _controller.statusLabel,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey<String>('server.token'),
              controller: _tokenController,
              obscureText: _obscureToken,
              enabled: !_controller.isRunning,
              onChanged: _controller.updateToken,
              decoration: InputDecoration(
                labelText: 'Input token',
                helperText:
                    'Clients must use the same token. It is required before '
                    'the server starts.',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _obscureToken ? 'Show token' : 'Hide token',
                  onPressed: () =>
                      setState(() => _obscureToken = !_obscureToken),
                  icon: Icon(
                    _obscureToken ? Icons.visibility_off : Icons.visibility,
                    size: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    key: const ValueKey<String>('server.ip'),
                    controller: _ipController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Local IPv4',
                      helperText: 'Shown for reference; binding uses 0.0.0.0.',
                      border: const OutlineInputBorder(),
                      suffixIcon: PopupMenuButton<String>(
                        key: const ValueKey<String>('server.ipMenu'),
                        tooltip: 'Choose a local IPv4 address',
                        icon: const Icon(Icons.arrow_drop_down),
                        onSelected: (value) {
                          _controller.selectAddress(value);
                          _ipController.text = value;
                        },
                        itemBuilder: (context) {
                          final addresses = _controller.addresses;
                          if (addresses.isEmpty) {
                            return const [
                              PopupMenuItem<String>(
                                enabled: false,
                                child: Text('No IPv4 address found'),
                              ),
                            ];
                          }
                          return [
                            for (final address in addresses)
                              PopupMenuItem<String>(
                                value: address,
                                child: Text(address),
                              ),
                          ];
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 150,
                  child: TextField(
                    key: const ValueKey<String>('server.port'),
                    controller: _portController,
                    enabled: !_controller.isRunning,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (value) {
                      final port = int.tryParse(value);
                      if (port != null && port > 0 && port < 65536) {
                        _controller.updatePort(port);
                      }
                    },
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: OutlinedButton.icon(
                    key: const ValueKey<String>('server.refreshIp'),
                    onPressed: _controller.isRunning
                        ? null
                        : () async {
                            await _controller.refreshAddresses();
                            _ipController.text = _controller.selectedIp ?? '';
                          },
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Refresh IP'),
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: FilledButton.icon(
                    key: const ValueKey<String>('server.run'),
                    onPressed: _controller.isRunning
                        ? _controller.stop
                        : _controller.start,
                    icon: Icon(
                      _controller.isRunning ? Icons.stop : Icons.play_arrow,
                      size: 18,
                    ),
                    label: Text(
                      _controller.isRunning ? 'Stop server' : 'Run file server',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'The server listens on 0.0.0.0:${_controller.config.port}. '
              'Expose this port with your own frp/tunnel. '
              'Do not expose it without a token.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 18,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _controller.errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey<String>('server.error.dismiss'),
            onPressed: _controller.clearError,
            icon: const Icon(Icons.close, size: 16),
            color: theme.colorScheme.onErrorContainer,
            visualDensity: VisualDensity.compact,
          ),
        ],
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
            padding: const EdgeInsets.fromLTRB(18, 14, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Shared folders',
                        style: theme.textTheme.titleSmall?.copyWith(
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
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add folder'),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.dividerColor),
          if (_controller.config.mounts.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No folders yet. Click "Add folder" to share one.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else ...[
            _tableHeader(context),
            for (
              var index = 0;
              index < _controller.config.mounts.length;
              index++
            )
              _mountRow(context, index),
          ],
        ],
      ),
    );
  }

  Widget _tableHeader(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Row(
        children: [
          SizedBox(width: 220, child: Text('NAME', style: style)),
          const SizedBox(width: 12),
          Expanded(child: Text('PATH', style: style)),
          const SizedBox(width: 90),
        ],
      ),
    );
  }

  Widget _mountRow(BuildContext context, int index) {
    final theme = Theme.of(context);
    final mount = _controller.config.mounts[index];
    final editing = _editingIndex == index;

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 8, 12, 8),
      child: Row(
        children: [
          SizedBox(
            width: 220,
            child: editing
                ? Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: ValueKey<String>(
                            'server.mount.nameField.$index',
                          ),
                          controller: _nameController,
                          autofocus: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _commitName(index),
                        ),
                      ),
                      IconButton(
                        key: ValueKey<String>('server.mount.nameOk.$index'),
                        tooltip: 'Save name',
                        onPressed: () => _commitName(index),
                        icon: const Icon(Icons.check, size: 18),
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        key: ValueKey<String>('server.mount.nameCancel.$index'),
                        tooltip: 'Cancel',
                        onPressed: () => setState(() => _editingIndex = null),
                        icon: const Icon(Icons.close, size: 16),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Text(
                          mount.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      IconButton(
                        key: ValueKey<String>('server.mount.edit.$index'),
                        tooltip: 'Rename',
                        onPressed: _controller.isRunning
                            ? null
                            : () {
                                _nameController.text = mount.name;
                                setState(() => _editingIndex = index);
                              },
                        icon: const Icon(Icons.edit_outlined, size: 17),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    mount.path.isEmpty ? 'Choose a folder...' : mount.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: mount.path.isEmpty
                          ? theme.colorScheme.onSurfaceVariant
                          : null,
                    ),
                  ),
                ),
                IconButton(
                  key: ValueKey<String>('server.mount.browse.$index'),
                  tooltip: 'Browse',
                  onPressed: _controller.isRunning
                      ? null
                      : () => _browse(index),
                  icon: const Icon(Icons.folder_open, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            key: ValueKey<String>('server.mount.delete.$index'),
            tooltip: 'Remove',
            onPressed: _controller.isRunning
                ? null
                : () => _controller.removeMount(index),
            icon: const Icon(Icons.delete_outline, size: 18),
            color: theme.colorScheme.error,
            visualDensity: VisualDensity.compact,
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
