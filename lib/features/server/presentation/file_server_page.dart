import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../app/ui.dart';
import '../../transport/server/file_server_config.dart';
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
  bool _showDraftMount = false;
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
                TextButton.icon(
                  key: const ValueKey<String>('server.sortMounts'),
                  onPressed: _controller.config.mounts.length > 1
                      ? _sortMounts
                      : null,
                  icon: const Icon(Icons.sort_by_alpha, size: 16),
                  label: const Text('Sort by name'),
                ),
                const SizedBox(width: 4),
                OutlinedButton.icon(
                  key: const ValueKey<String>('server.addMount'),
                  onPressed: _controller.isRunning || _showDraftMount
                      ? null
                      : _startDraftMount,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add folder'),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          if (_controller.config.mounts.isEmpty && !_showDraftMount)
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
                  _MountRow(
                    key: ValueKey<String>(
                      'server.mount.row.'
                      '${_controller.config.mounts[index].name}',
                    ),
                    index: index,
                    mount: _controller.config.mounts[index],
                    enabled: !_controller.isRunning,
                    onRename: (name) => _renameMount(index, name),
                    onChangePath: (path) => _changeMountPath(index, path),
                    onBrowse: () => _browseMount(index),
                    onDelete: () => _controller.removeMount(index),
                  ),
                if (_showDraftMount)
                  _NewMountRow(
                    key: const ValueKey<String>('server.mount.newRow'),
                    enabled: !_controller.isRunning,
                    onCreate: _createMount,
                    onCancel: () => setState(() => _showDraftMount = false),
                    pickFolder: _pickFolder,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  void _startDraftMount() {
    setState(() => _showDraftMount = true);
  }

  Future<void> _sortMounts() async {
    await _controller.sortMountsByName();
  }

  Future<String?> _renameMount(int index, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Name is required.';
    final mounts = _controller.config.mounts;
    if (index < 0 || index >= mounts.length) return null;
    if (mounts[index].name == trimmed) return null;
    if (mounts.any((mount) => mount.name == trimmed)) {
      return 'This name is already used.';
    }
    await _controller.renameMount(index, trimmed);
    return null;
  }

  Future<String?> _changeMountPath(int index, String path) async {
    final normalized = _normalizeFolderPath(path);
    if (normalized.isEmpty) return 'Choose a folder.';
    final problem = await _folderPathProblem(normalized);
    if (problem != null) return problem;
    final mounts = _controller.config.mounts;
    if (index < 0 || index >= mounts.length) return null;
    if (mounts[index].path == normalized) return null;
    await _controller.updateMountPath(index, normalized);
    return null;
  }

  Future<String?> _createMount(String name, String path) async {
    final normalized = _normalizeFolderPath(path);
    final problem = await _folderPathProblem(normalized);
    if (problem != null) return problem;
    final error = await _controller.addMount(name: name, path: normalized);
    if (error != null) return error;
    if (mounted) setState(() => _showDraftMount = false);
    return null;
  }

  Future<void> _browseMount(int index) async {
    final current = _controller.config.mounts[index].path;
    final path = await _pickFolder(current);
    if (path == null) return;
    await _controller.updateMountPath(index, path);
  }

  Future<String?> _pickFolder(String current) async {
    final initial = current.isNotEmpty && Directory(current).existsSync()
        ? current
        : widget.projectRoot;
    final path = await getDirectoryPath(
      initialDirectory: initial,
      confirmButtonText: 'Select folder',
    );
    return path == null ? null : _normalizeFolderPath(path);
  }
}

/// Normalizes a user-typed folder path to forward slashes.
String _normalizeFolderPath(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  return p.normalize(trimmed).replaceAll(r'\', '/');
}

/// Returns a message when [path] is not an existing folder.
Future<String?> _folderPathProblem(String path) async {
  if (path.isEmpty) return 'Choose a folder.';
  final type = await FileSystemEntity.type(path);
  return switch (type) {
    FileSystemEntityType.notFound => 'Folder not found.',
    FileSystemEntityType.file => 'This is a file, not a folder.',
    _ => null,
  };
}

/// One created shared folder: both fields stay editable in place.
class _MountRow extends StatefulWidget {
  const _MountRow({
    super.key,
    required this.index,
    required this.mount,
    required this.enabled,
    required this.onRename,
    required this.onChangePath,
    required this.onBrowse,
    required this.onDelete,
  });

  final int index;
  final FileServerMountConfig mount;
  final bool enabled;
  final Future<String?> Function(String name) onRename;
  final Future<String?> Function(String path) onChangePath;
  final Future<void> Function() onBrowse;
  final VoidCallback onDelete;

  @override
  State<_MountRow> createState() => _MountRowState();
}

class _MountRowState extends State<_MountRow> {
  late final TextEditingController _name;
  late final TextEditingController _path;
  late final FocusNode _nameFocus;
  late final FocusNode _pathFocus;
  String? _error;
  bool _committing = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.mount.name);
    _path = TextEditingController(text: widget.mount.path);
    _nameFocus = FocusNode()..addListener(_handleFocusChange);
    _pathFocus = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _name.dispose();
    _path.dispose();
    _nameFocus.dispose();
    _pathFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _MountRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_nameFocus.hasFocus && _name.text != widget.mount.name) {
      _name.text = widget.mount.name;
    }
    if (!_pathFocus.hasFocus && _path.text != widget.mount.path) {
      _path.text = widget.mount.path;
    }
  }

  void _handleFocusChange() {
    if (!_nameFocus.hasFocus && !_pathFocus.hasFocus) {
      _commit();
    }
  }

  Future<void> _commit() async {
    if (_committing || !widget.enabled) return;
    final name = _name.text.trim();
    final path = _normalizeFolderPath(_path.text);
    if (name == widget.mount.name && path == widget.mount.path) {
      if (_error != null && mounted) setState(() => _error = null);
      return;
    }

    _committing = true;
    try {
      var error = name == widget.mount.name
          ? null
          : await widget.onRename(name);
      if (error == null && path != widget.mount.path) {
        error = await widget.onChangePath(path);
      }
      if (!mounted) return;
      if (error == null) {
        _name.text = name;
        _path.text = path;
      }
      setState(() => _error = error);
    } finally {
      _committing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: ValueKey<String>('server.mount.${widget.index}'),
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(
        border: Border(
          top: widget.index == 0
              ? BorderSide.none
              : BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: ValueKey<String>('server.mount.name.${widget.index}'),
                  controller: _name,
                  focusNode: _nameFocus,
                  enabled: widget.enabled,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Folder name',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(6)),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                  ),
                  onSubmitted: (_) => _commit(),
                ),
                const SizedBox(height: 6),
                TextField(
                  key: ValueKey<String>('server.mount.path.${widget.index}'),
                  controller: _path,
                  focusNode: _pathFocus,
                  enabled: widget.enabled,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                  decoration: const InputDecoration(
                    hintText: '/path/to/folder',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(6)),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                  ),
                  onSubmitted: (_) => _commit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            key: ValueKey<String>('server.mount.browse.${widget.index}'),
            tooltip: 'Browse',
            onPressed: widget.enabled ? widget.onBrowse : null,
            icon: const Icon(Icons.folder_open_outlined, size: 16),
          ),
          IconButton(
            key: ValueKey<String>('server.mount.delete.${widget.index}'),
            tooltip: 'Remove',
            onPressed: widget.enabled ? widget.onDelete : null,
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

/// Draft row shown after "Add folder". The path field starts focused and the
/// name follows the folder name until the user edits it.
class _NewMountRow extends StatefulWidget {
  const _NewMountRow({
    super.key,
    required this.enabled,
    required this.onCreate,
    required this.onCancel,
    required this.pickFolder,
  });

  final bool enabled;
  final Future<String?> Function(String name, String path) onCreate;
  final VoidCallback onCancel;
  final Future<String?> Function(String currentPath) pickFolder;

  @override
  State<_NewMountRow> createState() => _NewMountRowState();
}

class _NewMountRowState extends State<_NewMountRow> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _path = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _pathFocus = FocusNode();
  bool _nameTouched = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pathFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _path.dispose();
    _nameFocus.dispose();
    _pathFocus.dispose();
    super.dispose();
  }

  void _syncNameFromPath(String rawPath) {
    if (_nameTouched) return;
    final normalized = _normalizeFolderPath(rawPath);
    if (normalized.isEmpty) return;
    final name = p.basename(normalized);
    if (name.isEmpty) return;
    _name.text = name;
  }

  Future<void> _browse() async {
    final picked = await widget.pickFolder(_path.text.trim());
    if (picked == null || !mounted) return;
    setState(() => _path.text = picked);
    _syncNameFromPath(picked);
  }

  Future<void> _submit() async {
    if (!widget.enabled || _submitting) return;

    final path = _normalizeFolderPath(_path.text);
    if (path.isEmpty) {
      setState(() => _error = 'Choose a folder first.');
      _pathFocus.requestFocus();
      return;
    }
    final problem = await _folderPathProblem(path);
    if (!mounted) return;
    if (problem != null) {
      setState(() => _error = problem);
      _pathFocus.requestFocus();
      return;
    }

    var name = _name.text.trim();
    if (name.isEmpty) {
      name = 'Untitled';
      _name.text = name;
    }

    setState(() {
      _submitting = true;
      _error = null;
      _path.text = path;
    });
    final error = await widget.onCreate(name, path);
    if (!mounted || error == null) return;
    setState(() {
      _submitting = false;
      _error = error;
    });
    _nameFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editable = widget.enabled && !_submitting;
    return Container(
      key: const ValueKey<String>('server.mount.new'),
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.04),
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey<String>('server.mount.new.name'),
                  controller: _name,
                  focusNode: _nameFocus,
                  enabled: editable,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Folder name',
                    helperText: 'Auto-filled from the folder path',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(6)),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                  ),
                  onChanged: (_) => _nameTouched = true,
                  onSubmitted: (_) => _pathFocus.requestFocus(),
                ),
                const SizedBox(height: 6),
                TextField(
                  key: const ValueKey<String>('server.mount.new.path'),
                  controller: _path,
                  focusNode: _pathFocus,
                  enabled: editable,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                  decoration: InputDecoration(
                    hintText: '/path/to/folder',
                    helperText: 'Press Enter to add; a file path is rejected',
                    isDense: true,
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(6)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    suffixIcon: IconButton(
                      key: const ValueKey<String>('server.mount.new.browse'),
                      tooltip: 'Browse',
                      onPressed: editable ? _browse : null,
                      icon: const Icon(Icons.folder_open_outlined, size: 16),
                    ),
                  ),
                  onChanged: _syncNameFromPath,
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            key: const ValueKey<String>('server.mount.new.cancel'),
            tooltip: 'Cancel',
            onPressed: _submitting ? null : widget.onCancel,
            icon: const Icon(Icons.close, size: 16),
          ),
        ],
      ),
    );
  }
}
