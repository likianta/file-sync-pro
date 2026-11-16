/// Tree projection of a [Manifest] for the two-pane sync view.
library;

import '../domain/manifest.dart';

final class SyncTreeNode {
  SyncTreeNode({
    required this.path,
    required this.name,
    required this.isDirectory,
    this.entry,
  });

  /// Path relative to the sync root. The root node uses an empty string.
  final String path;

  /// Display name (the last path segment, or the root label).
  final String name;

  final bool isDirectory;

  /// The manifest entry backing this node. Synthetic parent folders can be
  /// null when a manifest only lists a child.
  ManifestEntry? entry;

  final List<SyncTreeNode> children = [];

  bool expanded = false;

  bool get isEmpty => children.isEmpty;
}

final class SyncTree {
  SyncTree({required this.root, required this.byPath});

  final SyncTreeNode root;
  final Map<String, SyncTreeNode> byPath;

  /// Flattens the currently expanded part of the tree into display rows.
  List<({SyncTreeNode node, int depth})> visibleRows() {
    final rows = <({SyncTreeNode node, int depth})>[];
    void walk(SyncTreeNode node, int depth) {
      rows.add((node: node, depth: depth));
      if (node.isDirectory && node.expanded) {
        for (final child in node.children) {
          walk(child, depth + 1);
        }
      }
    }

    walk(root, 0);
    return rows;
  }

  /// Expands all ancestors of [path] so the node becomes visible.
  SyncTreeNode? reveal(String path) {
    final target = byPath[path];
    if (target == null) return null;
    final segments = path.split('/');
    var current = root;
    current.expanded = true;
    final prefix = StringBuffer();
    for (final segment in segments) {
      if (prefix.isNotEmpty) prefix.write('/');
      prefix.write(segment);
      final next = byPath[prefix.toString()];
      if (next == null) break;
      if (next.isDirectory && next != target) {
        next.expanded = true;
      }
      current = next;
    }
    return target;
  }
}

SyncTree buildSyncTree(Manifest manifest, {required String rootName}) {
  final root = SyncTreeNode(path: '', name: rootName, isDirectory: true);
  final byPath = <String, SyncTreeNode>{'': root};

  for (final path in manifest.entries.keys) {
    final segments = path.split('/');
    var current = root;
    var currentPath = '';
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      currentPath = currentPath.isEmpty ? segment : '$currentPath/$segment';
      final isLeaf = i == segments.length - 1;
      var child = byPath[currentPath];
      if (child == null) {
        child = SyncTreeNode(
          path: currentPath,
          name: segment,
          isDirectory: isLeaf ? manifest.entries[path]!.isDirectory : true,
          entry: isLeaf ? manifest.entries[path] : null,
        );
        byPath[currentPath] = child;
        current.children.add(child);
      } else if (isLeaf && child.entry == null) {
        child.entry = manifest.entries[path];
      }
      current = child;
    }
  }

  void sort(SyncTreeNode node) {
    node.children.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    for (final child in node.children) {
      sort(child);
    }
  }

  sort(root);
  root.expanded = true;
  return SyncTree(root: root, byPath: byPath);
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(1)} GB';
}
