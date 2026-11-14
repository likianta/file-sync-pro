import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../transport/http_transport.dart';
import '../application/sync_client_config.dart';
import '../application/sync_pair_config.dart';
import 'sync_dashboard_page.dart';

class SyncWorkspacePage extends StatefulWidget {
  const SyncWorkspacePage({
    super.key,
    required this.configPath,
    required this.projectRoot,
  });

  final String configPath;
  final String projectRoot;

  @override
  State<SyncWorkspacePage> createState() => _SyncWorkspacePageState();
}

class _SyncWorkspacePageState extends State<SyncWorkspacePage> {
  late SyncClientConfig _config;
  String? _selectedName;
  SyncPairConfig? _runtime;
  String? _configError;

  @override
  void initState() {
    super.initState();
    try {
      _config = SyncClientConfig.load(
        path: widget.configPath,
        projectRoot: widget.projectRoot,
      );
      if (_config.pairs.isNotEmpty) {
        _selectedName = _config.pairs.first.name;
      }
      _refreshRuntime();
    } catch (error) {
      _configError = error.toString();
      _config = SyncClientConfig(
        token: '',
        timeoutSeconds: 300,
        extraIgnores: const [],
        pairs: const [],
      );
    }
  }

  void _refreshRuntime() {
    final name = _selectedName;
    _runtime = name == null ? null : _config.runtimeFor(name);
  }

  Future<void> _saveConfig() async {
    try {
      await _config.save(path: widget.configPath);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save config: $error')));
    }
  }

  Future<void> _addPair() async {
    final result = await showDialog<_PairEditorResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PairEditorDialog(
        projectRoot: widget.projectRoot,
        token: _config.token,
      ),
    );
    if (result == null) return;
    if (_config.pairs.any((pair) => pair.name == result.entry.name)) {
      _showMessage('A pair named "${result.entry.name}" already exists.');
      return;
    }

    setState(() {
      _config.token = result.token;
      _config.pairs.add(result.entry);
      _selectedName = result.entry.name;
      _refreshRuntime();
    });
    await _saveConfig();
  }

  Future<void> _editPair() async {
    final name = _selectedName;
    if (name == null) return;
    final entry = _config.pairs.firstWhere((pair) => pair.name == name);
    final result = await showDialog<_PairEditorResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PairEditorDialog(
        projectRoot: widget.projectRoot,
        token: _config.token,
        entry: entry,
      ),
    );
    if (result == null) return;
    if (_config.pairs.any(
      (pair) => pair.name == result.entry.name && pair.name != name,
    )) {
      _showMessage('A pair named "${result.entry.name}" already exists.');
      return;
    }

    setState(() {
      _config.token = result.token;
      final index = _config.pairs.indexWhere((pair) => pair.name == name);
      if (index >= 0) {
        _config.pairs[index] = result.entry;
      }
      _selectedName = result.entry.name;
      _refreshRuntime();
    });
    await _saveConfig();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _deletePair() async {
    final name = _selectedName;
    if (name == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete sync pair?'),
        content: Text(
          'Remove "$name" from this device. Files are not deleted; only the '
          'pair configuration and its state remain on disk.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey<String>('sync.pair.deleteConfirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _config.pairs.removeWhere((pair) => pair.name == name);
      _selectedName = _config.pairs.isEmpty ? null : _config.pairs.first.name;
      _refreshRuntime();
    });
    await _saveConfig();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_configError != null) {
      return Scaffold(
        body: Center(
          child: Text(
            'Cannot read sync config:\n$_configError',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              Text(
                'Sync pair',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              if (_config.pairs.isNotEmpty)
                DropdownButton<String>(
                  key: const ValueKey<String>('sync.pair.select'),
                  value: _selectedName,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final pair in _config.pairs)
                      DropdownMenuItem<String>(
                        value: pair.name,
                        child: Text(pair.name),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedName = value;
                      _refreshRuntime();
                    });
                  },
                )
              else
                Text(
                  'No pairs yet',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(width: 6),
              IconButton(
                key: const ValueKey<String>('sync.pair.add'),
                tooltip: 'Add sync pair',
                onPressed: _addPair,
                icon: const Icon(Icons.add, size: 18),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                key: const ValueKey<String>('sync.pair.edit'),
                tooltip: 'Edit sync pair',
                onPressed: _selectedName == null ? null : _editPair,
                icon: const Icon(Icons.edit_outlined, size: 18),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                key: const ValueKey<String>('sync.pair.delete'),
                tooltip: 'Delete sync pair',
                onPressed: _selectedName == null ? null : _deletePair,
                icon: const Icon(Icons.delete_outline, size: 18),
                visualDensity: VisualDensity.compact,
              ),
              const Spacer(),
              if (_config.token.isEmpty)
                _WarningChip(
                  label: 'Token not set',
                  onTap: _selectedName == null ? null : _editPair,
                ),
            ],
          ),
        ),
        Expanded(
          child: _runtime == null
              ? _EmptyPairs(onAdd: _addPair)
              : SyncDashboardPage(
                  key: ValueKey<String>(
                    'sync.dashboard.${_runtime!.pairName}'
                    '.${_runtime!.localRoot}.${_runtime!.remoteUrl}',
                  ),
                  config: _runtime!,
                ),
        ),
      ],
    );
  }
}

class _EmptyPairs extends StatelessWidget {
  const _EmptyPairs({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_copy_outlined,
            size: 36,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 10),
          Text('No sync pairs yet.', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            'Add a pair to choose a local folder and a remote mount.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const ValueKey<String>('sync.pair.emptyAdd'),
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add sync pair'),
          ),
        ],
      ),
    );
  }
}

class _WarningChip extends StatelessWidget {
  const _WarningChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFD4A106).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 14,
              color: Color(0xFFD4A106),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF8A6A00),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _PairEditorResult {
  const _PairEditorResult({required this.entry, required this.token});

  final SyncPairEntry entry;
  final String token;
}

class _PairEditorDialog extends StatefulWidget {
  const _PairEditorDialog({
    required this.projectRoot,
    required this.token,
    this.entry,
  });

  final String projectRoot;
  final String token;
  final SyncPairEntry? entry;

  @override
  State<_PairEditorDialog> createState() => _PairEditorDialogState();
}

class _PairEditorDialogState extends State<_PairEditorDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _localRoot = TextEditingController();
  final TextEditingController _server = TextEditingController();
  final TextEditingController _token = TextEditingController();
  final TextEditingController _mount = TextEditingController();
  final TextEditingController _subpath = TextEditingController();

  List<String> _mounts = const [];
  bool _loadingMounts = false;
  String? _mountError;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    if (entry != null) {
      _name.text = entry.name;
      _localRoot.text = entry.localRoot;
      final uri = Uri.tryParse(entry.remoteUrl);
      if (uri != null && uri.hasScheme) {
        _server.text = '${uri.scheme}://${uri.authority}';
        final segments = uri.pathSegments
            .where((segment) => segment.isNotEmpty)
            .toList();
        if (segments.isNotEmpty) {
          _mount.text = segments.first;
          _subpath.text = segments.skip(1).join('/');
        }
      }
    } else {
      final defaultLocal = p.normalize(
        p.join(widget.projectRoot, '..', 'photolens'),
      );
      _localRoot.text = defaultLocal;
      _name.text = p.basename(defaultLocal);
      _server.text = 'http://47.102.108.149:2160';
      _mount.text = 'photolens';
    }
    _token.text = widget.token;
    _fetchMounts();
  }

  @override
  void dispose() {
    _name.dispose();
    _localRoot.dispose();
    _server.dispose();
    _token.dispose();
    _mount.dispose();
    _subpath.dispose();
    super.dispose();
  }

  Future<void> _fetchMounts() async {
    final server = _server.text.trim();
    if (server.isEmpty) return;
    setState(() {
      _loadingMounts = true;
      _mountError = null;
    });
    final transport = HttpTransport(
      baseUrl: server,
      token: _token.text.trim(),
      timeout: const Duration(seconds: 20),
    );
    try {
      final json = await transport.getJson('');
      final mounts = json['mounts'];
      if (!mounted) return;
      setState(() {
        _mounts = mounts is List
            ? mounts.whereType<String>().toList(growable: false)
            : const [];
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _mountError = error.toString());
    } finally {
      await transport.close();
      if (mounted) {
        setState(() => _loadingMounts = false);
      }
    }
  }

  Future<void> _browseLocalRoot() async {
    final path = await getDirectoryPath(
      initialDirectory: _localRoot.text.isEmpty
          ? widget.projectRoot
          : _localRoot.text,
      confirmButtonText: 'Select folder',
    );
    if (path == null) return;
    setState(() {
      _localRoot.text = path;
      if (_name.text.trim().isEmpty) {
        _name.text = p.basename(path);
      }
    });
  }

  String get _sanitizedName {
    final value = _name.text.trim().isEmpty ? 'pair' : _name.text.trim();
    return value.replaceAll(RegExp(r'[<>:"/\\|?*]'), '-');
  }

  void _save() {
    final server = _server.text.trim().replaceAll(RegExp(r'/+$'), '');
    final mount = _mount.text.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    final subpath = _subpath.text.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    final remoteUrl = subpath.isEmpty
        ? '$server/$mount'
        : '$server/$mount/$subpath';
    final entry = SyncPairEntry(
      name: _name.text.trim(),
      localRoot: p.normalize(_localRoot.text.trim()),
      remoteUrl: remoteUrl,
      stateDir: widget.entry?.stateDir.isNotEmpty == true
          ? widget.entry!.stateDir
          : p.normalize(
              p.join(widget.projectRoot, 'data', 'sync_pairs', _sanitizedName),
            ),
    );
    Navigator.of(context)
        .pop(_PairEditorResult(entry: entry, token: _token.text.trim()));
  }

  bool get _canSave {
    return _name.text.trim().isNotEmpty &&
        _localRoot.text.trim().isNotEmpty &&
        _server.text.trim().isNotEmpty &&
        _mount.text.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      key: const ValueKey<String>('sync.pair.editor'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.sync_alt,
                    size: 22,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    widget.entry == null ? 'Add sync pair' : 'Edit sync pair',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                key: const ValueKey<String>('sync.pair.name'),
                controller: _name,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Pair name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey<String>('sync.pair.localRoot'),
                      controller: _localRoot,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Local folder',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    key: const ValueKey<String>('sync.pair.browseLocal'),
                    onPressed: _browseLocalRoot,
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Browse'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey<String>('sync.pair.server'),
                controller: _server,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Remote server',
                  hintText: 'http://47.102.108.149:2160',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey<String>('sync.pair.token'),
                controller: _token,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Token (shared by all pairs)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey<String>('sync.pair.mount'),
                      controller: _mount,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Remote mount',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    key: const ValueKey<String>('sync.pair.mountMenu'),
                    tooltip: 'Choose a mount',
                    onSelected: (value) => setState(() => _mount.text = value),
                    itemBuilder: (context) {
                      if (_mounts.isEmpty) {
                        return const [
                          PopupMenuItem<String>(
                            enabled: false,
                            child: Text('No mounts found'),
                          ),
                        ];
                      }
                      return [
                        for (final mount in _mounts)
                          PopupMenuItem<String>(
                            value: mount,
                            child: Text(mount),
                          ),
                      ];
                    },
                    icon: const Icon(Icons.arrow_drop_down),
                  ),
                  IconButton(
                    key: const ValueKey<String>('sync.pair.refreshMounts'),
                    tooltip: 'Refresh mounts',
                    onPressed: _loadingMounts ? null : _fetchMounts,
                    icon: _loadingMounts
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                  ),
                ],
              ),
              if (_mountError != null) ...[
                const SizedBox(height: 6),
                Text(
                  _mountError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey<String>('sync.pair.subpath'),
                controller: _subpath,
                decoration: const InputDecoration(
                  labelText: 'Remote subfolder (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Remote URL: ${_server.text.trim().replaceAll(RegExp(r'/+$'), '')}/'
                '${_mount.text.trim().replaceAll(RegExp(r'^/+|/+$'), '')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const ValueKey<String>('sync.pair.cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey<String>('sync.pair.save'),
                    onPressed: _canSave ? _save : null,
                    child: const Text('Save pair'),
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
