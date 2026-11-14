import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// A quick-access location shown at the top of [DirectoryPickerPage].
final class DirectoryRoot {
  const DirectoryRoot({required this.label, required this.path});

  final String label;
  final String path;
}

/// A lightweight, dependency-free folder browser.
///
/// Android's SAF returns content URIs which the file server cannot serve, so we
/// browse the raw filesystem instead. This requires all-files access.
class DirectoryPickerPage extends StatefulWidget {
  const DirectoryPickerPage({
    super.key,
    required this.initialPath,
    required this.roots,
  });

  final String initialPath;
  final List<DirectoryRoot> roots;

  @override
  State<DirectoryPickerPage> createState() => _DirectoryPickerPageState();
}

class _DirectoryPickerPageState extends State<DirectoryPickerPage> {
  late String _current;
  List<Directory> _children = const [];
  String? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _current = widget.initialPath;
    _open(_current);
  }

  Future<void> _open(String path) async {
    setState(() {
      _current = path;
      _loading = true;
      _error = null;
    });
    try {
      final children = await Directory(path)
          .list(followLinks: false)
          .where((entry) => entry is Directory)
          .cast<Directory>()
          .toList();
      children.sort(
        (a, b) => p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase()),
      );
      if (!mounted) return;
      setState(() {
        _children = children
            .where((dir) => !p.basename(dir.path).startsWith('.'))
            .toList(growable: false);
        _loading = false;
      });
    } on FileSystemException {
      if (!mounted) return;
      setState(() {
        _children = const [];
        _loading = false;
        _error =
            'Cannot read this folder. Grant "All files access" on the home '
            'screen, then try again.';
      });
    }
  }

  bool get _canGoUp {
    final parent = p.dirname(_current);
    return parent != _current && _current != '/storage';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose folder'),
        actions: [
          IconButton(
            tooltip: 'Parent folder',
            onPressed: _canGoUp ? () => _open(p.dirname(_current)) : null,
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => _open(_current),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.roots.length > 1)
            SizedBox(
              height: 46,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: widget.roots.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final root = widget.roots[index];
                  final selected = _current == root.path;
                  return ChoiceChip(
                    avatar: const Icon(Icons.folder_special_rounded, size: 18),
                    label: Text(root.label),
                    selected: selected,
                    onSelected: (_) => _open(root.path),
                  );
                },
              ),
            ),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.folder_open_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _current,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _children.isEmpty
                ? Center(
                    child: Text(
                      'No subfolders here.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: _children.length,
                    itemBuilder: (context, index) {
                      final dir = _children[index];
                      return ListTile(
                        leading: Icon(
                          Icons.folder_rounded,
                          color: scheme.primary,
                        ),
                        title: Text(p.basename(dir.path)),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _open(dir.path),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(_current),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Use this folder'),
          ),
        ),
      ),
    );
  }
}
