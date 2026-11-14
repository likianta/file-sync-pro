import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:path/path.dart' as p;

import '../../transport/http_transport.dart';
import '../application/sync_client_config.dart';

final class PairEditorResult {
  const PairEditorResult({required this.entry, required this.token});

  final SyncPairEntry entry;
  final String token;
}

Future<PairEditorResult?> showPairEditorDialog({
  required BuildContext context,
  required String projectRoot,
  required SyncDeviceEntry device,
  required String token,
  SyncPairEntry? entry,
}) {
  return showFDialog<PairEditorResult>(
    context: context,
    barrierDismissible: false,
    builder: (context, style, animation) => _PairEditorDialog(
      animation: animation,
      projectRoot: projectRoot,
      device: device,
      token: token,
      entry: entry,
    ),
  );
}

class _PairEditorDialog extends StatefulWidget {
  const _PairEditorDialog({
    required this.animation,
    required this.projectRoot,
    required this.device,
    required this.token,
    this.entry,
  });

  final Animation<double> animation;
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
      final segments = uri?.pathSegments
          .where((segment) => segment.isNotEmpty)
          .toList();
      if (segments != null && segments.isNotEmpty) {
        _mount.text = segments.first;
        _subpath.text = segments.skip(1).join('/');
      }
    } else {
      final defaultLocal = p.normalize(
        p.join(widget.projectRoot, '..', 'photolens'),
      );
      _localRoot.text = defaultLocal;
      _name.text = p.basename(defaultLocal);
    }
    _token.text = widget.token;
    _fetchMounts();
  }

  @override
  void dispose() {
    _name.dispose();
    _localRoot.dispose();
    _token.dispose();
    _mount.dispose();
    _subpath.dispose();
    _ignores.dispose();
    super.dispose();
  }

  Future<void> _fetchMounts() async {
    setState(() {
      _loadingMounts = true;
      _mountError = null;
    });
    final transport = HttpTransport(
      baseUrl: widget.device.baseUrl,
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
    final mount = _mount.text.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    final subpath = _subpath.text.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    final remoteUrl = subpath.isEmpty
        ? '${widget.device.baseUrl}/$mount'
        : '${widget.device.baseUrl}/$mount/$subpath';
    final entry = SyncPairEntry(
      name: _name.text.trim(),
      deviceId: widget.device.id,
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
        .pop(PairEditorResult(entry: entry, token: _token.text.trim()));
  }

  bool get _canSave {
    return _name.text.trim().isNotEmpty &&
        _localRoot.text.trim().isNotEmpty &&
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
            const SizedBox(height: 6),
            Text(
              'Peer device: ${widget.device.name} · ${widget.device.baseUrl}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.body.xs.copyWith(
                color: theme.colors.mutedForeground,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 18),
            _Field(
              label: 'Pair name',
              child: FTextField(
                key: const ValueKey<String>('sync.pair.name'),
                control: FTextFieldControl.managed(
                  controller: _name,
                  onChange: (_) => setState(() {}),
                ),
                hint: 'gitbook',
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
              'Remote URL: ${widget.device.baseUrl}/'
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
