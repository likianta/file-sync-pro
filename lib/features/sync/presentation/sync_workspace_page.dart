import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../app/ui.dart';
import '../application/sync_client_config.dart';
import '../application/sync_config_store.dart';
import '../application/sync_engine.dart';
import '../application/sync_pair_config.dart';
import 'diff_sheet.dart';
import 'sync_dashboard_controller.dart';
import 'sync_tree.dart';
import 'tree_panel.dart';

class SyncWorkspacePage extends StatefulWidget {
  const SyncWorkspacePage({super.key, required this.store});

  final SyncConfigStore store;

  @override
  State<SyncWorkspacePage> createState() => _SyncWorkspacePageState();
}

class _SyncWorkspacePageState extends State<SyncWorkspacePage> {
  String? _deviceId;
  String? _pairName;
  SyncDashboardController? _controller;
  String? _controllerKey;

  SyncTree? _leftTree;
  SyncTree? _rightTree;
  SyncPreview? _lastPreview;

  String _leftSelection = '';
  String _rightSelection = '';
  String _activePath = '';
  bool _autoLocate = true;
  bool _logExpanded = false;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_syncSelection);
    _syncSelection();
  }

  @override
  void dispose() {
    widget.store.removeListener(_syncSelection);
    _detachController();
    super.dispose();
  }

  void _syncSelection() {
    if (!widget.store.loaded) return;

    final devices = widget.store.devices;
    var deviceId = _deviceId;
    if (deviceId == null || !devices.any((device) => device.id == deviceId)) {
      deviceId = devices.isEmpty ? null : devices.first.id;
    }

    final pairs = deviceId == null
        ? const <SyncPairEntry>[]
        : widget.store.config.pairsForDevice(deviceId);
    var pairName = _pairName;
    if (pairName == null || !pairs.any((pair) => pair.name == pairName)) {
      pairName = pairs.isEmpty ? null : pairs.first.name;
    }

    final runtime = pairName == null
        ? null
        : widget.store.config.runtimeFor(pairName);
    final key = runtime == null ? null : _keyOf(runtime);

    var changed = deviceId != _deviceId || pairName != _pairName;
    _deviceId = deviceId;
    _pairName = pairName;

    if (key != _controllerKey) {
      _detachController();
      _controller = runtime == null
          ? null
          : SyncDashboardController(config: runtime);
      _controllerKey = key;
      _leftTree = null;
      _rightTree = null;
      _lastPreview = null;
      _leftSelection = '';
      _rightSelection = '';
      _activePath = '';
      final controller = _controller;
      if (controller != null) {
        controller.addListener(_onControllerChanged);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) controller.refresh();
        });
      }
      changed = true;
    }

    if (changed && mounted) setState(() {});
  }

  static String _keyOf(SyncPairConfig config) {
    return [
      config.localRoot,
      config.remoteUrl,
      config.token,
      config.timeoutSeconds,
      config.stateDir,
      config.extraIgnores.join('\u0000'),
    ].join('\u0001');
  }

  void _detachController() {
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    _controller = null;
  }

  void _onControllerChanged() {
    _syncTrees();
    if (mounted) setState(() {});
  }

  void _syncTrees() {
    final preview = _controller?.preview;
    if (preview == null || identical(preview, _lastPreview)) return;

    final expandedLeft = _expandedPaths(_leftTree);
    final expandedRight = _expandedPaths(_rightTree);
    final rootName = _currentPair?.name ?? 'root';
    final left = buildSyncTree(preview.a, rootName: rootName);
    final right = buildSyncTree(preview.b, rootName: rootName);
    for (final path in expandedLeft) {
      left.byPath[path]?.expanded = true;
    }
    for (final path in expandedRight) {
      right.byPath[path]?.expanded = true;
    }
    _leftTree = left;
    _rightTree = right;
    _lastPreview = preview;
    left.reveal(_leftSelection);
    right.reveal(_rightSelection);
  }

  static Set<String> _expandedPaths(SyncTree? tree) {
    if (tree == null) return const {};
    return {
      for (final entry in tree.byPath.entries)
        if (entry.value.expanded) entry.key,
    };
  }

  SyncPairEntry? get _currentPair {
    final name = _pairName;
    if (name == null) return null;
    for (final pair in widget.store.config.pairs) {
      if (pair.name == name) return pair;
    }
    return null;
  }

  SyncDeviceEntry? get _currentDevice {
    final id = _deviceId;
    return id == null ? null : widget.store.config.deviceById(id);
  }

  void _selectDevice(String deviceId) {
    if (deviceId == _deviceId) return;
    _deviceId = deviceId;
    _pairName = null;
    _syncSelection();
  }

  void _selectPair(String name) {
    if (name == _pairName) return;
    _pairName = name;
    _syncSelection();
  }

  void _selectNode({required bool left, required SyncTreeNode node}) {
    setState(() {
      _activePath = node.path;
      final tree = left ? _leftTree : _rightTree;
      tree?.reveal(node.path);
      if (left) {
        _leftSelection = node.path;
      } else {
        _rightSelection = node.path;
      }
      if (_autoLocate) {
        final other = left ? _rightTree : _leftTree;
        if (other?.byPath[node.path] != null) {
          other!.reveal(node.path);
          if (left) {
            _rightSelection = node.path;
          } else {
            _leftSelection = node.path;
          }
        }
      }
    });
  }

  void _toggleNode(SyncTreeNode node) {
    setState(() => node.expanded = !node.expanded);
  }

  void _toggleAutoLocate(bool value) {
    setState(() {
      _autoLocate = value;
      if (!value) return;
      final path = _activePath;
      if (_leftTree?.byPath[path] != null) {
        _leftTree!.reveal(path);
        _leftSelection = path;
      }
      if (_rightTree?.byPath[path] != null) {
        _rightTree!.reveal(path);
        _rightSelection = path;
      }
    });
  }

  Future<void> _browseLocalRoot() async {
    final pair = _currentPair;
    if (pair == null) return;
    final path = await getDirectoryPath(
      initialDirectory: pair.localRoot,
      confirmButtonText: 'Select folder',
    );
    if (path == null || !mounted) return;
    widget.store.upsertPair(
      pair.copyWith(localRoot: p.normalize(path)),
      previousName: pair.name,
    );
  }

  Future<void> _check() async {
    final controller = _controller;
    if (controller == null || controller.busy) return;
    await controller.check();
    if (!mounted || controller.preview == null) return;
    await showSyncDiffSheet(context, controller);
  }

  Future<void> _run(SyncDirection direction) async {
    final controller = _controller;
    if (controller == null || controller.busy) return;
    await controller.run(
      direction: direction,
      subPath: _activePath.isEmpty ? null : _activePath,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        if (!widget.store.loaded) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (widget.store.error != null) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: AppErrorBanner(
                  message: 'Cannot read sync config: ${widget.store.error}',
                ),
              ),
            ),
          );
        }

        final controller = _controller;
        final busy = controller?.busy ?? false;
        final scanning = controller?.status == SyncDashboardStatus.scanning;
        final canRun = controller != null && !busy;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TopRow(
              hostname: Platform.localHostname,
              devices: widget.store.devices,
              selectedDeviceId: _deviceId,
              pairs: _deviceId == null
                  ? const []
                  : widget.store.config.pairsForDevice(_deviceId!),
              selectedPair: _pairName,
              autoLocate: _autoLocate,
              busy: busy,
              canRun: canRun,
              onSelectDevice: _selectDevice,
              onSelectPair: _selectPair,
              onToggleAutoLocate: _toggleAutoLocate,
              onCheck: _check,
              onPull: () => _run(SyncDirection.pull),
              onPush: () => _run(SyncDirection.push),
              onSync: () => _run(SyncDirection.both),
            ),
            if (controller?.errorMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: AppErrorBanner(
                  message: controller!.errorMessage!,
                  onDismiss: controller.clearError,
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: SyncTreePanel(
                        key: const ValueKey<String>('sync.tree.left'),
                        idPrefix: 'left',
                        title: Platform.localHostname.isEmpty
                            ? 'This machine'
                            : Platform.localHostname,
                        subtitle:
                            _currentPair?.localRoot ?? 'Choose a sync pair.',
                        icon: Icons.computer_outlined,
                        rootLabel: _currentPair?.name ?? 'root',
                        tree: _leftTree,
                        loading: scanning,
                        selectedPath: _leftSelection,
                        onSelect: (node) => _selectNode(left: true, node: node),
                        onToggle: _toggleNode,
                        onBrowse: _currentPair == null
                            ? null
                            : _browseLocalRoot,
                        onRefresh: controller?.refresh,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SyncTreePanel(
                        key: const ValueKey<String>('sync.tree.right'),
                        idPrefix: 'right',
                        title: _currentDevice?.name ?? 'Peer device',
                        subtitle:
                            _currentPair?.remoteUrl ?? 'Choose a sync pair.',
                        icon: Icons.cloud_outlined,
                        rootLabel: _currentPair?.name ?? 'root',
                        tree: _rightTree,
                        loading: scanning,
                        selectedPath: _rightSelection,
                        onSelect: (node) =>
                            _selectNode(left: false, node: node),
                        onToggle: _toggleNode,
                        onRefresh: controller?.refresh,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _ActivityPanel(
              controller: controller,
              expanded: _logExpanded,
              onToggle: () => setState(() => _logExpanded = !_logExpanded),
            ),
          ],
        );
      },
    );
  }
}

class _TopRow extends StatelessWidget {
  const _TopRow({
    required this.hostname,
    required this.devices,
    required this.selectedDeviceId,
    required this.pairs,
    required this.selectedPair,
    required this.autoLocate,
    required this.busy,
    required this.canRun,
    required this.onSelectDevice,
    required this.onSelectPair,
    required this.onToggleAutoLocate,
    required this.onCheck,
    required this.onPull,
    required this.onPush,
    required this.onSync,
  });

  final String hostname;
  final List<SyncDeviceEntry> devices;
  final String? selectedDeviceId;
  final List<SyncPairEntry> pairs;
  final String? selectedPair;
  final bool autoLocate;
  final bool busy;
  final bool canRun;
  final ValueChanged<String> onSelectDevice;
  final ValueChanged<String> onSelectPair;
  final ValueChanged<bool> onToggleAutoLocate;
  final VoidCallback onCheck;
  final VoidCallback onPull;
  final VoidCallback onPush;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final machine = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'THIS MACHINE',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          hostname.isEmpty ? 'This machine' : hostname,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );

    final pair = SizedBox(
      width: 220,
      child: _SelectBox(
        key: const ValueKey<String>('sync.pair.select'),
        label: 'Sync pair',
        value: selectedPair,
        items: [for (final item in pairs) item.name],
        onChanged: pairs.isEmpty ? null : onSelectPair,
        emptyLabel: 'No pairs',
      ),
    );

    final actions = <Widget>[
      OutlinedButton.icon(
        key: const ValueKey<String>('sync.check'),
        onPressed: busy ? null : onCheck,
        icon: const Icon(Icons.fact_check_outlined, size: 16),
        label: const Text('Check'),
      ),
      _ActionButton(
        key: const ValueKey<String>('sync.pull'),
        tooltip: 'Copy the selected node from the peer to this machine',
        icon: Icons.arrow_back,
        label: 'Pull',
        onPressed: canRun ? onPull : null,
      ),
      _ActionButton(
        key: const ValueKey<String>('sync.push'),
        tooltip: 'Copy the selected node from this machine to the peer',
        icon: Icons.arrow_forward,
        label: 'Push',
        onPressed: canRun ? onPush : null,
      ),
      FilledButton.icon(
        key: const ValueKey<String>('sync.run'),
        onPressed: canRun ? onSync : null,
        icon: const Icon(Icons.sync, size: 16),
        label: const Text('Sync'),
      ),
      _AutoLocateButton(value: autoLocate, onChanged: onToggleAutoLocate),
    ];

    final peer = SizedBox(
      width: 240,
      child: _SelectBox(
        key: const ValueKey<String>('sync.device.select'),
        label: 'Peer device',
        value: selectedDeviceId,
        items: [for (final device in devices) device.id],
        labels: {for (final device in devices) device.id: device.name},
        onChanged: devices.isEmpty ? null : onSelectDevice,
        emptyLabel: 'No devices',
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: machine),
              const SizedBox(width: 12),
              pair,
              const SizedBox(width: 12),
              peer,
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    actions[i],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact icon-only toggle used for auto-locate.
class _AutoLocateButton extends StatelessWidget {
  const _AutoLocateButton({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: value ? 'Auto locate is on' : 'Auto locate is off',
      child: IconButton(
        key: const ValueKey<String>('sync.autoLocate'),
        isSelected: value,
        selectedIcon: const Icon(Icons.center_focus_strong, size: 20),
        icon: const Icon(Icons.center_focus_weak, size: 20),
        style: IconButton.styleFrom(
          minimumSize: const Size(38, 38),
          backgroundColor: value
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : null,
          foregroundColor: value
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
          side: BorderSide(color: theme.colorScheme.outlineVariant),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: () => onChanged(!value),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
      ),
    );
  }
}

class _SelectBox extends StatelessWidget {
  const _SelectBox({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.labels = const {},
    this.emptyLabel = 'None',
  });

  final String label;
  final String? value;
  final List<String> items;
  final ValueChanged<String>? onChanged;
  final Map<String, String> labels;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      ),
      child: items.isEmpty
          ? Text(
              emptyLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: items.contains(value) ? value : null,
                isDense: true,
                isExpanded: true,
                borderRadius: BorderRadius.circular(10),
                items: [
                  for (final item in items)
                    DropdownMenuItem<String>(
                      value: item,
                      child: Text(
                        labels[item] ?? item,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
                onChanged: onChanged == null
                    ? null
                    : (selected) {
                        if (selected != null) onChanged!(selected);
                      },
              ),
            ),
    );
  }
}

class _ActivityPanel extends StatelessWidget {
  const _ActivityPanel({
    required this.controller,
    required this.expanded,
    required this.onToggle,
  });

  final SyncDashboardController? controller;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = controller?.log ?? const <String>[];
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const ValueKey<String>('sync.log.toggle'),
            onTap: onToggle,
            child: SizedBox(
              height: 38,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(
                      Icons.terminal,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Activity',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${lines.length} lines',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      expanded ? Icons.expand_more : Icons.expand_less,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: expanded
                ? SizedBox(
                    height: 168,
                    child: lines.isEmpty
                        ? Center(
                            child: Text(
                              'No activity yet.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : ListView.builder(
                            reverse: true,
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                            itemCount: lines.length,
                            itemBuilder: (context, index) {
                              final line = lines[lines.length - 1 - index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Text(
                                  line,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: line.contains('ERROR')
                                        ? theme.colorScheme.error
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              );
                            },
                          ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
