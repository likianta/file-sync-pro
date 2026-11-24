import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../application/sync_engine.dart';
import 'sync_dashboard_controller.dart';

/// Shows the post-sync conflict review dialog.
///
/// The left side edits the local winner. The right side shows the archived
/// remote copy, highlighting lines that differ from the local version.
Future<void> showConflictReviewDialog(
  BuildContext context,
  SyncDashboardController controller,
  List<ConflictArchiveEntry> entries,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        _ConflictReviewDialog(controller: controller, entries: entries),
  );
}

class _ConflictReviewDialog extends StatefulWidget {
  const _ConflictReviewDialog({
    required this.controller,
    required this.entries,
  });

  final SyncDashboardController controller;
  final List<ConflictArchiveEntry> entries;

  @override
  State<_ConflictReviewDialog> createState() => _ConflictReviewDialogState();
}

class _ConflictReviewDialogState extends State<_ConflictReviewDialog> {
  final TextEditingController _editor = TextEditingController();
  int _selected = 0;
  bool _loading = true;
  bool _saving = false;
  bool _binary = false;
  bool _remoteBinary = false;
  bool _localMissing = false;
  String? _error;
  String? _savedNote;
  String _localBaseline = '';
  String? _remoteText;
  int _remoteBytes = 0;

  static const _monoStyle = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: [
      'PingFang SC',
      'Heiti SC',
      'Noto Sans CJK SC',
      'sans-serif',
    ],
    fontSize: 12.5,
    height: 1.45,
  );

  static const _changedLine = Color(0xFFFFF1B8);

  ConflictArchiveEntry get _entry => widget.entries[_selected];

  String get _localPath {
    final entry = _entry;
    return entry.localPath ??
        p.joinAll([
          widget.controller.config.localRoot,
          ...entry.path.split('/'),
        ]);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _savedNote = null;
      _binary = false;
      _remoteBinary = false;
      _localMissing = false;
      _remoteText = null;
      _remoteBytes = 0;
      _localBaseline = '';
    });

    final localFile = File(_localPath);
    var localText = '';
    var localMissing = false;
    var binary = false;
    try {
      if (await localFile.exists()) {
        final bytes = await localFile.readAsBytes();
        binary = _looksBinary(bytes);
        if (!binary) {
          localText = utf8.decode(bytes, allowMalformed: true);
        }
      } else {
        localMissing = true;
      }
    } catch (error) {
      _error = 'Cannot read the local file: $error';
    }

    String? remoteText;
    var remoteBinary = false;
    var remoteBytes = 0;
    final archivePath = _entry.archivedRemotePath;
    if (archivePath != null) {
      try {
        final archive = File(archivePath);
        if (await archive.exists()) {
          final bytes = await archive.readAsBytes();
          remoteBytes = bytes.length;
          remoteBinary = _looksBinary(bytes);
          if (!remoteBinary) {
            remoteText = utf8.decode(bytes, allowMalformed: true);
          }
        }
      } catch (error) {
        _error = 'Cannot read the archived remote file: $error';
      }
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _binary = binary;
      _localMissing = localMissing;
      _remoteBinary = remoteBinary;
      _remoteText = remoteText;
      _remoteBytes = remoteBytes;
      _localBaseline = localText;
      _editor.text = localText;
    });
  }

  Future<void> _select(int index) async {
    if (index == _selected) return;
    setState(() => _selected = index);
    await _load();
  }

  Future<void> _save() async {
    if (_saving || _binary) return;
    setState(() {
      _saving = true;
      _error = null;
      _savedNote = null;
    });
    try {
      final file = File(_localPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(_editor.text, flush: true);
      setState(() {
        _localBaseline = _editor.text;
        _localMissing = false;
        _savedNote = 'Saved locally.';
      });
      final parent = _parentScope(_entry.path);
      await widget.controller.refreshSide(
        left: true,
        subPath: parent.isEmpty ? null : parent,
      );
      if (!mounted) return;
      setState(() {
        _savedNote = widget.controller.errorMessage == null
            ? 'Saved locally and refreshed the local snapshot.'
            : 'Saved locally, but refreshing the snapshot failed.';
        _error = widget.controller.errorMessage;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Cannot save the local file: $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _copyRemote() async {
    final text = _remoteText;
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Remote copy copied to the clipboard.')),
    );
  }

  static String _parentScope(String path) {
    final index = path.lastIndexOf('/');
    return index < 0 ? '' : path.substring(0, index);
  }

  static bool _looksBinary(List<int> bytes) {
    return bytes.take(8192).contains(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final width = (size.width - 72).clamp(720.0, 1200.0);
    final height = (size.height - 72).clamp(480.0, 780.0);

    return Dialog(
      key: const ValueKey<String>('conflicts.dialog'),
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(theme),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 250, child: _sidebar(theme)),
                  VerticalDivider(
                    width: 1,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _editorPane(theme)),
                              VerticalDivider(
                                width: 1,
                                color: theme.colorScheme.outlineVariant,
                              ),
                              Expanded(child: _diffPane(theme)),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
      child: Row(
        children: [
          Icon(Icons.merge_type, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Conflicts resolved locally (${widget.entries.length})',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Remote copies were archived before the local files '
                  'overwrote them.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey<String>('conflicts.close'),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _sidebar(ThemeData theme) {
    return ListView.builder(
      key: const ValueKey<String>('conflicts.sidebar'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: widget.entries.length,
      itemBuilder: (context, index) {
        final entry = widget.entries[index];
        final selected = index == _selected;
        return InkWell(
          key: ValueKey<String>('conflicts.item.${entry.path}'),
          onTap: () => _select(index),
          child: Container(
            color: selected
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
                : Colors.transparent,
            padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.path,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 3,
                  children: [
                    if (!entry.localExisted)
                      _chip('local deleted', theme.colorScheme.error),
                    if (!entry.remoteExisted)
                      _chip('remote deleted', theme.colorScheme.tertiary),
                    if (entry.archivedRemotePath == null && entry.remoteExisted)
                      _chip('remote not archived', theme.colorScheme.outline),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _editorPane(ThemeData theme) {
    final entry = _entry;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _paneHeader(
          theme,
          icon: Icons.edit_outlined,
          title: 'Local winner',
          subtitle: _localPath,
          trailing: FilledButton.icon(
            key: const ValueKey<String>('conflicts.save'),
            onPressed: _saving || _binary || _loading ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined, size: 15),
            label: const Text('Save'),
          ),
        ),
        if (_localMissing)
          _banner(
            theme,
            icon: Icons.info_outline,
            text: 'The local file was missing. Saving recreates it.',
            color: theme.colorScheme.tertiary,
          ),
        if (_error != null)
          _banner(
            theme,
            icon: Icons.error_outline,
            text: _error!,
            color: theme.colorScheme.error,
          ),
        if (_savedNote != null)
          _banner(
            theme,
            icon: Icons.check_circle_outline,
            text: _savedNote!,
            color: const Color(0xFF2EA121),
          ),
        Expanded(
          child: _binary
              ? Center(
                  child: Text(
                    'Binary file. Edit it with an external editor; the '
                    'remote copy is still archived.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: TextField(
                    key: const ValueKey<String>('conflicts.editor'),
                    controller: _editor,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: _monoStyle,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isCollapsed: true,
                    ),
                  ),
                ),
        ),
        if (entry.localExisted)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              'Saving writes the local file and refreshes its folder in the '
              'snapshot. Sync again to publish the edit.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  Widget _diffPane(ThemeData theme) {
    final entry = _entry;
    final remote = _remoteText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _paneHeader(
          theme,
          icon: Icons.difference_outlined,
          title: 'Remote version (archived)',
          subtitle: entry.archivedRemotePath ?? 'No remote copy',
          trailing: IconButton(
            key: const ValueKey<String>('conflicts.copyRemote'),
            tooltip: 'Copy remote text',
            onPressed: remote == null ? null : _copyRemote,
            icon: const Icon(Icons.copy_all_outlined, size: 16),
          ),
        ),
        Expanded(
          child: remote == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(
                      _remoteBinary
                          ? 'Binary file ($_remoteBytes bytes). Cannot '
                                'display it here.'
                          : 'The remote file was missing or deleted before '
                                'the sync.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  child: SelectableText.rich(
                    TextSpan(
                      style: _monoStyle,
                      children: _diffSpans(_localBaseline, remote),
                    ),
                    key: const ValueKey<String>('conflicts.diff'),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Row(
            children: [
              Container(width: 10, height: 10, color: _changedLine),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Highlighted lines differ from the local winner. '
                  'This pane is read-only; select or copy freely.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _paneHeader(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10.5,
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _banner(
    ThemeData theme, {
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<InlineSpan> _diffSpans(String local, String remote) {
    final counts = <String, int>{};
    for (final line in local.split('\n')) {
      counts[line] = (counts[line] ?? 0) + 1;
    }
    final remoteLines = remote.split('\n');
    final spans = <InlineSpan>[];
    for (var i = 0; i < remoteLines.length; i++) {
      final line = remoteLines[i];
      final remaining = counts[line] ?? 0;
      final changed = remaining == 0;
      if (remaining > 0) {
        counts[line] = remaining - 1;
      }
      spans.add(
        TextSpan(
          text: line,
          style: changed
              ? const TextStyle(backgroundColor: _changedLine)
              : null,
        ),
      );
      if (i < remoteLines.length - 1) {
        spans.add(const TextSpan(text: '\n'));
      }
    }
    return spans;
  }
}
