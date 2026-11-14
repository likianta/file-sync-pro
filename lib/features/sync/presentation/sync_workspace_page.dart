import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
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
      _showMessage('Failed to save config: $error');
    }
  }

  Future<void> _addPair() async {
    final result = await _showPairEditor();
    if (result == null || !mounted) return;
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
    final result = await _showPairEditor(entry: entry);
    if (result == null || !mounted) return;
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

  Future<_PairEditorResult?> _showPairEditor({SyncPairEntry? entry}) {
    return showFDialog<_PairEditorResult>(
      context: context,
      barrierDismissible: false,
      builder: (context, style, animation) => _PairEditorDialog(
        animation: animation,
        projectRoot: widget.projectRoot,
        token: _config.token,
        entry: entry,
      ),
    );
  }

  Future<void> _deletePair() async {
    final name = _selectedName;
    if (name == null) return;
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
                'Remove "$name" from this device. Files are not deleted; only '
                'the pair configuration and its state remain on disk.',
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
                    key: const ValueKey<String>('sync.pair.deleteConfirm'),
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
    if (confirmed != true || !mounted) return;

    setState(() {
      _config.pairs.removeWhere((pair) => pair.name == name);
      _selectedName = _config.pairs.isEmpty ? null : _config.pairs.first.name;
      _refreshRuntime();
    });
    await _saveConfig();
  }

  void _showMessage(String message) {
    showFToast(
      context: context,
      title: Text(message),
      icon: const Icon(FLucideIcons.circleAlert),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    if (_configError != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: FAlert(
            variant: FAlertVariant.destructive,
            title: const Text('Cannot read sync config'),
            subtitle: Text(_configError!),
            icon: const Icon(FLucideIcons.circleAlert),
          ),
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          decoration: BoxDecoration(
            color: theme.colors.background,
            border: Border(bottom: BorderSide(color: theme.colors.border)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sync',
                      style: theme.typography.body.xl.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Keep a local folder and a remote mount in step.',
                      style: theme.typography.body.sm.copyWith(
                        color: theme.colors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              if (_config.pairs.isNotEmpty) ...[
                SizedBox(
                  width: 220,
                  child: FSelect<String>(
                    key: const ValueKey<String>('sync.pair.select'),
                    control: FSelectControl<String>.lifted(
                      value: _selectedName,
                      onChange: (value) {
                        if (value == null) return;
                        setState(() {
                          _selectedName = value;
                          _refreshRuntime();
                        });
                      },
                    ),
                    items: {
                      for (final pair in _config.pairs) pair.name: pair.name,
                    },
                    label: const Text('Sync pair'),
                  ),
                ),
                const SizedBox(width: 8),
              ] else
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, right: 8),
                  child: Text(
                    'No pairs yet',
                    style: theme.typography.body.sm.copyWith(
                      color: theme.colors.mutedForeground,
                    ),
                  ),
                ),
              FButton.icon(
                key: const ValueKey<String>('sync.pair.add'),
                variant: FButtonVariant.outline,
                onPress: _addPair,
                semanticsTooltip: 'Add sync pair',
                child: const Icon(FLucideIcons.plus, size: 16),
              ),
              const SizedBox(width: 6),
              FButton.icon(
                key: const ValueKey<String>('sync.pair.edit'),
                variant: FButtonVariant.outline,
                onPress: _selectedName == null ? null : _editPair,
                semanticsTooltip: 'Edit sync pair',
                child: const Icon(FLucideIcons.pencil, size: 16),
              ),
              const SizedBox(width: 6),
              FButton.icon(
                key: const ValueKey<String>('sync.pair.delete'),
                variant: FButtonVariant.outline,
                onPress: _selectedName == null ? null : _deletePair,
                semanticsTooltip: 'Delete sync pair',
                child: const Icon(FLucideIcons.trash2, size: 16),
              ),
              const Spacer(),
              if (_config.token.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 2),
                  child: FButton(
                    variant: FButtonVariant.outline,
                    size: FButtonSizeVariant.sm,
                    onPress: _selectedName == null ? null : _editPair,
                    prefix: const Icon(FLucideIcons.circleAlert, size: 14),
                    child: const Text('Token not set'),
                  ),
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
                    '.${_runtime!.localRoot}.${_runtime!.remoteUrl}'
                    '.${_runtime!.extraIgnores.join('|')}',
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
              FLucideIcons.folderOpen,
              size: 24,
              color: theme.colors.mutedForeground,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No sync pairs yet.',
            style: theme.typography.body.md.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add a pair to choose a local folder and a remote mount.',
            style: theme.typography.body.sm.copyWith(
              color: theme.colors.mutedForeground,
            ),
          ),
          const SizedBox(height: 18),
          FButton(
            key: const ValueKey<String>('sync.pair.emptyAdd'),
            onPress: onAdd,
            prefix: const Icon(FLucideIcons.plus, size: 16),
            child: const Text('Add sync pair'),
          ),
        ],
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
    required this.animation,
    required this.projectRoot,
    required this.token,
    this.entry,
  });

  final Animation<double> animation;
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
  final TextEditingController _ignores = TextEditingController();

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
      _ignores.text = entry.ignores.join('\n');
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
    _ignores.dispose();
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
      ignores: [
        for (final line in _ignores.text.split('\n'))
          if (line.trim().isNotEmpty && !line.trim().startsWith('#'))
            line.trim(),
      ],
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
    final theme = context.theme;
    return FDialog(
      animation: widget.animation,
      constraints: const BoxConstraints(minWidth: 560, maxWidth: 680),
      builder: (context, style) => SingleChildScrollView(
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
                    FLucideIcons.arrowRightLeft,
                    size: 16,
                    color: theme.colors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  widget.entry == null ? 'Add sync pair' : 'Edit sync pair',
                  style: style.titleTextStyle,
                ),
              ],
            ),
            const SizedBox(height: 20),
            _Field(
              label: 'Pair name',
              child: FTextField(
                key: const ValueKey<String>('sync.pair.name'),
                control: FTextFieldControl.managed(
                  controller: _name,
                  onChange: (_) => setState(() {}),
                ),
                hint: 'photolens',
              ),
            ),
            const SizedBox(height: 14),
            _Field(
              label: 'Local folder',
              child: Row(
                children: [
                  Expanded(
                    child: FTextField(
                      key: const ValueKey<String>('sync.pair.localRoot'),
                      control: FTextFieldControl.managed(
                        controller: _localRoot,
                        onChange: (_) => setState(() {}),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FButton(
                    key: const ValueKey<String>('sync.pair.browseLocal'),
                    variant: FButtonVariant.outline,
                    onPress: _browseLocalRoot,
                    prefix: const Icon(FLucideIcons.folderOpen, size: 15),
                    child: const Text('Browse'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _Field(
              label: 'Remote server',
              child: FTextField(
                key: const ValueKey<String>('sync.pair.server'),
                control: FTextFieldControl.managed(
                  controller: _server,
                  onChange: (_) => setState(() {}),
                ),
                hint: 'http://47.102.108.149:2160',
              ),
            ),
            const SizedBox(height: 14),
            _Field(
              label: 'Token (shared by all pairs)',
              child: FTextField(
                key: const ValueKey<String>('sync.pair.token'),
                control: FTextFieldControl.managed(
                  controller: _token,
                  onChange: (_) => setState(() {}),
                ),
                obscureText: true,
              ),
            ),
            const SizedBox(height: 14),
            _Field(
              label: 'Remote mount',
              child: Row(
                children: [
                  Expanded(
                    child: FTextField(
                      key: const ValueKey<String>('sync.pair.mount'),
                      control: FTextFieldControl.managed(
                        controller: _mount,
                        onChange: (_) => setState(() {}),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FButton.icon(
                    key: const ValueKey<String>('sync.pair.refreshMounts'),
                    variant: FButtonVariant.outline,
                    onPress: _loadingMounts ? null : _fetchMounts,
                    semanticsTooltip: 'Refresh mounts',
                    child: _loadingMounts
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: FCircularProgress(),
                          )
                        : const Icon(FLucideIcons.refreshCw, size: 15),
                  ),
                ],
              ),
            ),
            if (_mounts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final mount in _mounts)
                    FButton(
                      variant: FButtonVariant.outline,
                      size: FButtonSizeVariant.sm,
                      onPress: () => setState(() => _mount.text = mount),
                      child: Text(mount),
                    ),
                ],
              ),
            ],
            if (_mountError != null) ...[
              const SizedBox(height: 8),
              FAlert(
                variant: FAlertVariant.destructive,
                title: const Text('Cannot list remote mounts'),
                subtitle: Text(_mountError!),
                icon: const Icon(FLucideIcons.circleAlert),
              ),
            ],
            const SizedBox(height: 14),
            _Field(
              label: 'Remote subfolder (optional)',
              child: FTextField(
                key: const ValueKey<String>('sync.pair.subpath'),
                control: FTextFieldControl.managed(controller: _subpath),
              ),
            ),
            const SizedBox(height: 20),
            Container(height: 1, color: theme.colors.border),
            const SizedBox(height: 18),
            Row(
              children: [
                Icon(
                  FLucideIcons.settings,
                  size: 15,
                  color: theme.colors.mutedForeground,
                ),
                const SizedBox(width: 7),
                Text(
                  'Ignores',
                  style: theme.typography.body.sm.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'One pattern per line. This pair uses its own list instead of '
              'the global ignores.',
              style: theme.typography.body.xs.copyWith(
                color: theme.colors.mutedForeground,
              ),
            ),
            const SizedBox(height: 10),
            FTextField(
              key: const ValueKey<String>('sync.pair.ignores'),
              control: FTextFieldControl.managed(controller: _ignores),
              hint: '/.git/\n/blog/\n*.b64.html',
              description: const Text(
                'Gitignore-like syntax: /path anchors at the sync root, '
                'dir/ matches a directory, * and ** match names.',
              ),
              minLines: 5,
              maxLines: 9,
            ),
            const SizedBox(height: 8),
            Text(
              'Remote URL: '
              '${_server.text.trim().replaceAll(RegExp(r'/+$'), '')}/'
              '${_mount.text.trim().replaceAll(RegExp(r'^/+|/+$'), '')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.body.xs.copyWith(
                color: theme.colors.mutedForeground,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FButton(
                  key: const ValueKey<String>('sync.pair.cancel'),
                  variant: FButtonVariant.ghost,
                  onPress: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FButton(
                  key: const ValueKey<String>('sync.pair.save'),
                  onPress: _canSave ? _save : null,
                  child: const Text('Save pair'),
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
