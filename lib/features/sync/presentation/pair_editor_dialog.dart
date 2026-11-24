import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
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
      final segments = entry.remoteRoot
          .split('/')
          .where((segment) => segment.isNotEmpty)
          .toList();
      if (segments.isNotEmpty) {
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

  void _save() {
    final mount = _mount.text.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    final subpath = _subpath.text.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    final remoteRoot = subpath.isEmpty ? '/$mount' : '/$mount/$subpath';
    final id = widget.entry?.id ?? SyncClientConfig.newPairId();
    final entry = SyncPairEntry(
      id: id,
      name: _name.text.trim(),
      deviceId: widget.device.id,
      localRoot: p.normalize(_localRoot.text.trim()),
      remoteRoot: remoteRoot,
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
    final theme = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 660),
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
                      Icons.swap_horiz,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
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
              const SizedBox(height: 4),
              Text(
                'Peer device: ${widget.device.name} · ${widget.device.baseUrl}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                key: const ValueKey<String>('sync.pair.name'),
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Pair name',
                  hintText: 'gitbook',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey<String>('sync.pair.localRoot'),
                      controller: _localRoot,
                      decoration: const InputDecoration(
                        labelText: 'Local folder',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    key: const ValueKey<String>('sync.pair.browseLocal'),
                    onPressed: _browseLocalRoot,
                    icon: const Icon(Icons.folder_open_outlined, size: 16),
                    label: const Text('Browse'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey<String>('sync.pair.token'),
                controller: _token,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Token (shared by all pairs)',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey<String>('sync.pair.mount'),
                      controller: _mount,
                      decoration: const InputDecoration(
                        labelText: 'Remote mount',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    key: const ValueKey<String>('sync.pair.refreshMounts'),
                    tooltip: 'Refresh mounts',
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
              if (_mounts.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final mount in _mounts)
                      ActionChip(
                        label: Text(mount),
                        onPressed: () => setState(() => _mount.text = mount),
                      ),
                  ],
                ),
              ],
              if (_mountError != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Cannot list remote mounts: $_mountError',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey<String>('sync.pair.subpath'),
                controller: _subpath,
                decoration: const InputDecoration(
                  labelText: 'Remote subfolder (optional)',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Ignore rules live in <root>/.file_sync_shot.json and are '
                'shared by every pair that uses the same folder.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Remote URL: ${widget.device.baseUrl}/'
                '${_mount.text.trim().replaceAll(RegExp(r'^/+|/+$'), '')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
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
