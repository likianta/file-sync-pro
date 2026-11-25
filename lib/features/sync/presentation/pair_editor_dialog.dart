import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../transport/http_transport.dart';
import '../application/pair_ignores.dart';
import '../application/sync_client_config.dart';

final class PairEditorResult {
  const PairEditorResult({required this.entry});

  final SyncPairEntry entry;
}

Future<PairEditorResult?> showPairEditorDialog({
  required BuildContext context,
  required String projectRoot,
  required SyncDeviceEntry device,
  required String token,
  SyncPairEntry? entry,
}) {
  return showDialog<PairEditorResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _PairEditorDialog(
      projectRoot: projectRoot,
      device: device,
      token: token,
      entry: entry,
    ),
  );
}

/// A folder the peer exposes as a mount.
final class _PeerNode {
  const _PeerNode({required this.root, required this.label});

  final String root;
  final String label;
}

class _PairEditorDialog extends StatefulWidget {
  const _PairEditorDialog({
    required this.projectRoot,
    required this.device,
    required this.token,
    this.entry,
  });

  final String projectRoot;
  final SyncDeviceEntry device;
  final String token;
  final SyncPairEntry? entry;

  @override
  State<_PairEditorDialog> createState() => _PairEditorDialogState();
}

class _PairEditorDialogState extends State<_PairEditorDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _localRoot = TextEditingController();
  final TextEditingController _ignores = TextEditingController();
  final FocusNode _localRootFocus = FocusNode();

  List<String> _mounts = const [];
  bool _loadingMounts = false;
  String? _mountError;

  /// Remote root of the selected peer folder, e.g. `/asa-gui`.
  String _selectedRoot = '';
  bool _nameTouched = false;

  bool _loadingIgnores = false;
  bool _saving = false;
  String? _ignoresWarning;
  String? _saveError;
  IgnoresForm _ignoresForm = IgnoresForm.builtinList;
  IgnoresSource? _ignoresSource;
  String _loadedIgnoresText = '';
  int _ignoresRequest = 0;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    if (entry != null) {
      _name.text = entry.name;
      _localRoot.text = entry.localRoot;
      _selectedRoot = entry.remoteRoot;
      _nameTouched = true;
    } else {
      final defaultLocal = p.normalize(
        p.join(widget.projectRoot, '..', 'photolens'),
      );
      _localRoot.text = defaultLocal;
      _name.text = p.basename(defaultLocal);
    }
    _localRootFocus.addListener(() {
      if (!_localRootFocus.hasFocus) {
        _loadIgnores();
      }
    });
    _fetchMounts();
    _loadIgnores();
  }

  @override
  void dispose() {
    _disposed = true;
    _name.dispose();
    _localRoot.dispose();
    _ignores.dispose();
    _localRootFocus.dispose();
    super.dispose();
  }

  Future<void> _fetchMounts() async {
    setState(() {
      _loadingMounts = true;
      _mountError = null;
    });
    final transport = HttpTransport(
      baseUrl: widget.device.baseUrl,
      token: widget.token,
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

  /// Peer folders plus the current remote root when the peer no longer
  /// advertises it (an old pair may point at a subfolder).
  List<_PeerNode> get _peerNodes {
    final nodes = <_PeerNode>[
      for (final mount in _mounts) _PeerNode(root: '/$mount', label: mount),
    ];
    if (_selectedRoot.isNotEmpty &&
        !nodes.any((node) => node.root == _selectedRoot)) {
      nodes.insert(
        0,
        _PeerNode(root: _selectedRoot, label: _selectedRoot.substring(1)),
      );
    }
    return nodes;
  }

  void _selectNode(_PeerNode node) {
    if (_selectedRoot == node.root) return;
    final label = p.posix.basename(node.root);
    setState(() {
      _selectedRoot = node.root;
      if (!_nameTouched || _name.text.trim().isEmpty) {
        _name.text = label;
      }
    });
    _loadIgnores();
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
      if (!_nameTouched && _name.text.trim().isEmpty) {
        _name.text = p.basename(path);
      }
    });
    _loadIgnores();
  }

  /// Loads the ignore rules for the selected folder.
  ///
  /// Reloads are skipped once the editor has unsaved edits, so switching
  /// folders never discards typed patterns.
  Future<void> _loadIgnores() async {
    final localRoot = _localRoot.text.trim();
    if (localRoot.isEmpty) return;
    if (!_ignoresUnchanged) return;
    final request = ++_ignoresRequest;
    setState(() {
      _loadingIgnores = true;
      _ignoresWarning = null;
    });
    final store = PairIgnoresStore(
      localRoot: p.normalize(localRoot),
      remoteUrl: _selectedRoot.isEmpty
          ? ''
          : '${widget.device.baseUrl}$_selectedRoot',
      token: widget.token,
      pairName: _name.text.trim().isEmpty ? 'pair' : _name.text.trim(),
    );
    final result = await store.load();
    if (_disposed || !mounted || request != _ignoresRequest) return;
    setState(() {
      _loadingIgnores = false;
      _ignoresForm = result.form;
      _ignoresSource = result.source;
      _loadedIgnoresText = result.text;
      _ignores.text = result.text;
      _ignoresWarning = result.warning;
    });
  }

  static String _normalizedList(String text) {
    return text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
  }

  static String _trimTrailingNewline(String text) {
    return text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
  }

  bool get _ignoresUnchanged {
    if (_ignoresForm == IgnoresForm.gitignore) {
      return _trimTrailingNewline(_ignores.text) ==
          _trimTrailingNewline(_loadedIgnoresText);
    }
    return _normalizedList(_ignores.text) ==
        _normalizedList(_loadedIgnoresText);
  }

  /// Writes the current editor content in the opposite storage form and keeps
  /// the dialog open so the badges and hints update in place.
  Future<void> _saveAsOtherForm() async {
    if (!_canSave || _saving || _loadingIgnores) return;
    final target = _ignoresForm == IgnoresForm.gitignore
        ? IgnoresForm.builtinList
        : IgnoresForm.gitignore;
    final entry = _buildEntry();

    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await PairIgnoresStore(
        localRoot: entry.localRoot,
        remoteUrl: entry.remoteUrlFor(widget.device),
        token: widget.token,
        pairName: entry.name,
      ).save(form: target, text: _ignores.text);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _ignoresForm = target;
        _loadedIgnoresText = target == IgnoresForm.gitignore
            ? (_ignores.text.isEmpty || _ignores.text.endsWith('\n')
                  ? _ignores.text
                  : '${_ignores.text}\n')
            : _normalizedList(_ignores.text);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = error.toString();
      });
    }
  }

  SyncPairEntry _buildEntry() {
    return SyncPairEntry(
      id: widget.entry?.id ?? SyncClientConfig.newPairId(),
      name: _name.text.trim(),
      deviceId: widget.device.id,
      localRoot: p.normalize(_localRoot.text.trim()),
      remoteRoot: _selectedRoot,
    );
  }

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    final entry = _buildEntry();

    if (_ignoresUnchanged) {
      Navigator.of(context).pop(PairEditorResult(entry: entry));
      return;
    }

    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await PairIgnoresStore(
        localRoot: entry.localRoot,
        remoteUrl: entry.remoteUrlFor(widget.device),
        token: widget.token,
        pairName: entry.name,
      ).save(form: _ignoresForm, text: _ignores.text);
      if (!mounted) return;
      Navigator.of(context).pop(PairEditorResult(entry: entry));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = error.toString();
      });
    }
  }

  bool get _canSave {
    return _name.text.trim().isNotEmpty &&
        _localRoot.text.trim().isNotEmpty &&
        _selectedRoot.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
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
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.swap_horiz,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          widget.entry == null
                              ? 'Add sync pair'
                              : 'Edit sync pair',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Peer device: ${widget.device.name} · '
                      '${widget.device.baseUrl}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _buildPeerFolders(theme),
                    const SizedBox(height: 18),
                    TextField(
                      key: const ValueKey<String>('sync.pair.name'),
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'Pair name',
                        hintText: 'asa-gui',
                        helperText: 'Defaults to the selected peer folder',
                      ),
                      onChanged: (_) {
                        _nameTouched = true;
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey<String>('sync.pair.localRoot'),
                            controller: _localRoot,
                            focusNode: _localRootFocus,
                            decoration: const InputDecoration(
                              labelText: 'Local folder',
                            ),
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => _loadIgnores(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          key: const ValueKey<String>('sync.pair.browseLocal'),
                          onPressed: _browseLocalRoot,
                          icon: const Icon(
                            Icons.folder_open_outlined,
                            size: 16,
                          ),
                          label: const Text('Browse'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Text(
                          'Ignore rules',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_loadingIgnores) ...[
                          const SizedBox(width: 8),
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ],
                        const Spacer(),
                        if (_ignoresSource != null) ...[
                          _IgnoresBadge(
                            key: const ValueKey<String>(
                              'sync.pair.ignores.side',
                            ),
                            label: _ignoresSource == IgnoresSource.local
                                ? 'Local'
                                : 'Remote',
                            color: _ignoresSource == IgnoresSource.local
                                ? const Color(0xFF2563EB)
                                : const Color(0xFF7C3AED),
                            tint: _ignoresSource == IgnoresSource.local
                                ? const Color(0xFFDBEAFE)
                                : const Color(0xFFEDE9FE),
                          ),
                          const SizedBox(width: 6),
                        ],
                        _IgnoresBadge(
                          key: const ValueKey<String>('sync.pair.ignores.form'),
                          label: _ignoresForm == IgnoresForm.gitignore
                              ? 'Gitignore'
                              : 'BuiltinList',
                          color: _ignoresForm == IgnoresForm.gitignore
                              ? const Color(0xFF059669)
                              : const Color(0xFFD97706),
                          tint: _ignoresForm == IgnoresForm.gitignore
                              ? const Color(0xFFD1FAE5)
                              : const Color(0xFFFEF3C7),
                        ),
                        const SizedBox(width: 4),
                        TextButton(
                          key: const ValueKey<String>(
                            'sync.pair.ignores.switchForm',
                          ),
                          onPressed: _canSave && !_saving && !_loadingIgnores
                              ? _saveAsOtherForm
                              : null,
                          style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.primary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            minimumSize: const Size(0, 28),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: Text(
                            _ignoresForm == IgnoresForm.gitignore
                                ? 'Save as builtin list'
                                : 'Save as .gitignore',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey<String>('sync.pair.ignores'),
                      controller: _ignores,
                      enabled: !_loadingIgnores && !_saving,
                      minLines: 4,
                      maxLines: 6,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily:
                            defaultTargetPlatform == TargetPlatform.macOS ||
                                defaultTargetPlatform == TargetPlatform.iOS
                            ? 'Menlo'
                            : 'monospace',
                        fontFamilyFallback: const [
                          'SF Mono',
                          'Monaco',
                          'Consolas',
                          'Courier New',
                          'Roboto Mono',
                          'Droid Sans Mono',
                          'PingFang SC',
                          'Heiti SC',
                          'Noto Sans CJK SC',
                          'Noto Sans SC',
                          'Source Han Sans SC',
                          'Microsoft YaHei',
                        ],
                      ),
                      decoration: InputDecoration(
                        labelText: 'Patterns',
                        hintText: '/node_modules/\n*.tmp',
                        helperText: _ignoresForm == IgnoresForm.gitignore
                            ? 'Loaded from <root>/.gitignore and saved to both '
                                  'sides; the next scan applies them.'
                            : 'One pattern per line. Stored in '
                                  '<root>/.file_sync_shot.json on both sides; '
                                  'the next scan applies them.',
                        helperMaxLines: 3,
                      ),
                    ),
                    if (_ignoresWarning != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _ignoresWarning!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                    if (_saveError != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer.withValues(
                            alpha: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _saveError!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      'Remote URL: ${widget.device.baseUrl}'
                      '${_selectedRoot.isEmpty ? '/' : _selectedRoot}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const ValueKey<String>('sync.pair.cancel'),
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey<String>('sync.pair.save'),
                    onPressed: _canSave && !_saving ? _save : null,
                    child: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save pair'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeerFolders(ThemeData theme) {
    final nodes = _peerNodes;
    return Column(
      key: const ValueKey<String>('sync.pair.mount'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Peer folders',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _loadingMounts ? 'Loading...' : 'Click one to use its mount',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            IconButton(
              key: const ValueKey<String>('sync.pair.refreshMounts'),
              tooltip: 'Refresh peer folders',
              onPressed: _loadingMounts ? null : _fetchMounts,
              icon: _loadingMounts
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 16),
            ),
          ],
        ),
        if (nodes.isEmpty && !_loadingMounts)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _mountError == null
                  ? 'The peer shares no folders.'
                  : 'Cannot list peer folders: $_mountError',
              style: theme.textTheme.bodySmall?.copyWith(
                color: _mountError == null
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.error,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final node in nodes)
                  _PeerNodeCard(
                    node: node,
                    selected: node.root == _selectedRoot,
                    onTap: () => _selectNode(node),
                  ),
              ],
            ),
          ),
        if (_mountError != null && nodes.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Cannot refresh peer folders: $_mountError',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

class _PeerNodeCard extends StatelessWidget {
  const _PeerNodeCard({
    required this.node,
    required this.selected,
    required this.onTap,
  });

  final _PeerNode node;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: InkWell(
        key: ValueKey<String>('sync.pair.node.${node.root}'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.folder : Icons.folder_outlined,
                size: 15,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                node.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IgnoresBadge extends StatelessWidget {
  const _IgnoresBadge({
    super.key,
    required this.label,
    required this.color,
    required this.tint,
  });

  final String label;
  final Color color;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
