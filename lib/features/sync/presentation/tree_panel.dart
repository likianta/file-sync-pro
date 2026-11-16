import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import 'sync_tree.dart';

/// One side of the two-pane tree view.
class SyncTreePanel extends StatefulWidget {
  const SyncTreePanel({
    super.key,
    required this.idPrefix,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tree,
    required this.selectedPath,
    required this.onSelect,
    required this.onToggle,
    this.loading = false,
    this.onBrowse,
    this.onRefresh,
    this.rootLabel = 'root',
  });

  final String idPrefix;
  final String title;
  final String subtitle;
  final IconData icon;
  final SyncTree? tree;
  final bool loading;
  final String? selectedPath;
  final ValueChanged<SyncTreeNode> onSelect;
  final ValueChanged<SyncTreeNode> onToggle;
  final VoidCallback? onBrowse;
  final VoidCallback? onRefresh;
  final String rootLabel;

  @override
  State<SyncTreePanel> createState() => _SyncTreePanelState();
}

class _SyncTreePanelState extends State<SyncTreePanel> {
  final ScrollController _scroll = ScrollController();
  String? _hovered;

  @override
  void didUpdateWidget(covariant SyncTreePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedPath != oldWidget.selectedPath) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _revealSelected() {
    final tree = widget.tree;
    final selected = widget.selectedPath;
    if (!mounted || tree == null || selected == null || !_scroll.hasClients) {
      return;
    }
    final rows = tree.visibleRows();
    final index = rows.indexWhere((row) => row.node.path == selected);
    if (index < 0) return;

    final top = index * 34.0;
    final bottom = top + 34;
    final position = _scroll.position;
    if (top >= position.pixels &&
        bottom <= position.pixels + position.viewportDimension) {
      return;
    }
    final target = (top - position.viewportDimension / 2 + 17)
        .clamp(0.0, position.maxScrollExtent)
        .toDouble();
    unawaited(
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context),
          Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 9, 6, 9),
      child: Row(
        children: [
          Icon(widget.icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (widget.loading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (widget.onBrowse != null)
            IconButton(
              key: ValueKey<String>('${widget.idPrefix}.browse'),
              tooltip: 'Browse folder',
              onPressed: widget.onBrowse,
              icon: const Icon(Icons.folder_open_outlined, size: 18),
            ),
          if (widget.onRefresh != null)
            IconButton(
              key: ValueKey<String>('${widget.idPrefix}.refresh'),
              tooltip: 'Refresh',
              onPressed: widget.loading ? null : widget.onRefresh,
              icon: const Icon(Icons.refresh, size: 18),
            ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    final tree = widget.tree;
    if (tree == null) {
      if (widget.loading) {
        return const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      }
      return Center(
        child: Text(
          'Waiting for folder data...',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final rows = tree.visibleRows();
    if (rows.length == 1 && tree.root.children.isEmpty) {
      return Center(
        child: Text(
          'This folder is empty.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Scrollbar(
      controller: _scroll,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemExtent: 34,
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          return _row(context, row.node, row.depth);
        },
      ),
    );
  }

  Widget _row(BuildContext context, SyncTreeNode node, int depth) {
    final theme = Theme.of(context);
    final selected = widget.selectedPath == node.path;
    final hovered = _hovered == node.path;
    final color = node.isDirectory
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    final keyPath = node.path.isEmpty ? '__root__' : node.path;

    final trailing = node.isDirectory
        ? '${node.children.length}'
        : formatBytes(node.entry?.size ?? 0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = node.path),
      onExit: (_) {
        if (_hovered == node.path) setState(() => _hovered = null);
      },
      child: Material(
        color: selected
            ? AppTheme.selectedColor(context)
            : hovered
            ? AppTheme.hoverColor(context)
            : Colors.transparent,
        child: InkWell(
          key: ValueKey<String>('${widget.idPrefix}.node.$keyPath'),
          hoverColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onTap: () => _selectNode(node),
          child: Padding(
            padding: EdgeInsets.only(left: 8 + depth * 18.0, right: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 34,
                  child: node.isDirectory
                      ? GestureDetector(
                          key: ValueKey<String>(
                            '${widget.idPrefix}.toggle.$keyPath',
                          ),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => widget.onToggle(node),
                          child: Icon(
                            node.expanded
                                ? Icons.expand_more
                                : Icons.chevron_right,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 2),
                SizedBox(
                  width: 20,
                  height: 34,
                  child: Icon(
                    node.isDirectory
                        ? (node.expanded
                              ? Icons.folder_open_outlined
                              : Icons.folder_outlined)
                        : Icons.insert_drive_file_outlined,
                    size: 17,
                    color: color,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    node.path.isEmpty ? widget.rootLabel : node.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 13,
                      fontWeight: node.isDirectory
                          ? FontWeight.w500
                          : FontWeight.w400,
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  trailing,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _selectNode(SyncTreeNode node) {
    if (node.isDirectory) {
      widget.onToggle(node);
    }
    widget.onSelect(node);
  }
}
