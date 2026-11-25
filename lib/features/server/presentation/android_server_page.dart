import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'directory_picker_page.dart';
import 'file_server_controller.dart';

/// The Android build is a controlled peer: it only serves folders.
class AndroidServerPage extends StatefulWidget {
  const AndroidServerPage({super.key});

  @override
  State<AndroidServerPage> createState() => _AndroidServerPageState();
}

enum _MountAction { rename, changeFolder, remove }

class _AndroidServerPageState extends State<AndroidServerPage>
    with WidgetsBindingObserver {
  final TextEditingController _token = TextEditingController();
  final TextEditingController _port = TextEditingController();

  FileServerController? _controller;
  String? _appRoot;
  String? _internalRoot;
  String? _error;
  var _ready = false;
  var _obscureToken = true;
  var _allFiles = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _token.dispose();
    _port.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _ready) {
      _refreshPermission();
    }
  }

  Future<void> _bootstrap() async {
    try {
      final support = await getApplicationSupportDirectory();
      final external = await getExternalStorageDirectory();
      final configPath = p.join(support.path, 'file_server.config.json');
      final firstRun = !File(configPath).existsSync();

      final controller = FileServerController(
        configPath: configPath,
        projectRoot: support.path,
      );
      await controller.load();

      var dirty = false;
      if (controller.config.token.trim().isEmpty) {
        controller.updateToken(_newToken());
        dirty = true;
      }
      if (firstRun) {
        final shared = Directory(
          p.join(external?.path ?? support.path, 'shared'),
        );
        await shared.create(recursive: true);
        await controller.addMount(name: 'shared', path: shared.path);
        dirty = true;
      }
      if (dirty) {
        await controller.save();
      }

      final status = await Permission.manageExternalStorage.status;
      if (!mounted) {
        controller.dispose();
        return;
      }
      _token.text = controller.config.token;
      _port.text = controller.config.port.toString();
      setState(() {
        _controller = controller;
        _appRoot = external?.path;
        _internalRoot = support.path;
        _allFiles = status.isGranted;
        _ready = true;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    }
  }

  String _newToken() {
    final random = Random.secure();
    return List.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
  }

  Future<void> _refreshPermission() async {
    final status = await Permission.manageExternalStorage.status;
    if (!mounted) return;
    setState(() => _allFiles = status.isGranted);
  }

  Future<void> _requestAccess() async {
    final status = await Permission.manageExternalStorage.request();
    if (!mounted) return;
    setState(() => _allFiles = status.isGranted);
    if (!status.isGranted) {
      _snack(
        'Grant "All files access" in the system settings, then return here.',
      );
    }
  }

  String get _address {
    final controller = _controller;
    final ip = controller?.selectedIp ?? '0.0.0.0';
    final port = controller?.config.port ?? 2160;
    return 'http://$ip:$port';
  }

  Future<void> _copyAddress() async {
    await Clipboard.setData(ClipboardData(text: _address));
    if (mounted) _snack('Address copied: $_address');
  }

  Future<void> _copyToken() async {
    final token = _controller?.config.token ?? '';
    if (token.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: token));
    if (mounted) _snack('Token copied.');
  }

  Future<void> _toggleServer() async {
    final controller = _controller!;
    if (controller.isRunning) {
      await controller.stop();
      return;
    }
    if (controller.config.mounts.isEmpty) {
      _snack('Add at least one folder to share.');
      return;
    }
    await controller.start();
    if (controller.status == FileServerStatus.error &&
        controller.errorMessage != null) {
      _snack(controller.errorMessage!);
    }
  }

  String get _defaultBrowsePath {
    final controller = _controller!;
    if (_allFiles) return '/storage/emulated/0';
    if (controller.config.mounts.isNotEmpty) {
      return controller.config.mounts.first.path;
    }
    return _appRoot ?? _internalRoot ?? '/';
  }

  List<DirectoryRoot> get _roots => [
    if (_appRoot != null) DirectoryRoot(label: 'App storage', path: _appRoot!),
    if (_allFiles)
      const DirectoryRoot(
        label: 'Internal storage',
        path: '/storage/emulated/0',
      ),
  ];

  Future<String?> _pickDirectory({required String initialPath}) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) =>
            DirectoryPickerPage(initialPath: initialPath, roots: _roots),
      ),
    );
  }

  Future<void> _addMount() async {
    final path = await _pickDirectory(initialPath: _defaultBrowsePath);
    if (path == null || !mounted) return;
    final controller = _controller!;
    await controller.addMount(name: _uniqueName(p.basename(path)), path: path);
  }

  String _uniqueName(String base) {
    final controller = _controller!;
    final name = base.trim().isEmpty ? 'folder' : base.trim();
    if (!controller.config.mounts.any((mount) => mount.name == name)) {
      return name;
    }
    var index = 2;
    while (controller.config.mounts.any(
      (mount) => mount.name == '$name $index',
    )) {
      index++;
    }
    return '$name $index';
  }

  Future<void> _renameMount(int index) async {
    final controller = _controller!;
    final mount = controller.config.mounts[index];
    final text = TextEditingController(text: mount.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename folder'),
        content: TextField(
          controller: text,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Mount name'),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(text.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    text.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    if (controller.config.mounts.any(
      (other) => other.name == name && other != mount,
    )) {
      _snack('A folder named "$name" already exists.');
      return;
    }
    await controller.renameMount(index, name);
  }

  Future<void> _changeFolder(int index) async {
    final controller = _controller!;
    final path = await _pickDirectory(
      initialPath: controller.config.mounts[index].path.isEmpty
          ? _defaultBrowsePath
          : controller.config.mounts[index].path,
    );
    if (path == null) return;
    await controller.updateMountPath(index, path);
  }

  Future<void> _confirmRemove(int index) async {
    final controller = _controller!;
    final mount = controller.config.mounts[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove folder?'),
        content: Text(
          '"${mount.name}" will no longer be shared. Files on the device are '
          'not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.removeMount(index);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 40,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 12),
                const Text('Cannot start the Android app'),
                const SizedBox(height: 6),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _ready = false;
                    });
                    _bootstrap();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final controller = _controller;
    if (!_ready || controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _buildScaffold(context, controller),
    );
  }

  Widget _buildScaffold(BuildContext context, FileServerController controller) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(title: const Text('File Sync Pro')),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              32 + MediaQuery.paddingOf(context).bottom,
            ),
            sliver: SliverList.list(
              children: [
                _statusCard(context, controller),
                const SizedBox(height: 16),
                if (!_allFiles) ...[
                  _permissionCard(context),
                  const SizedBox(height: 16),
                ],
                if (controller.errorMessage != null) ...[
                  _errorCard(context, controller),
                  const SizedBox(height: 16),
                ],
                _connectionCard(context, controller),
                const SizedBox(height: 16),
                _mountsSection(context, controller),
                const SizedBox(height: 16),
                _hintCard(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(BuildContext context, FileServerController controller) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final running = controller.isRunning;
    final foreground = scheme.onSurfaceVariant;

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  running
                      ? Icons.wifi_tethering_rounded
                      : Icons.wifi_tethering_off_rounded,
                  size: 20,
                  color: running ? scheme.primary : foreground,
                ),
                const SizedBox(width: 8),
                Text(
                  running ? 'Serving files' : 'Server stopped',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (running)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'LIVE',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            SelectableText(
              _address,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              running
                  ? '${controller.config.mounts.length} folders shared. '
                        'Keep this app open while syncing.'
                  : 'Start the server so the Mac can connect.',
              style: theme.textTheme.bodySmall?.copyWith(color: foreground),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _toggleServer,
                    icon: Icon(
                      running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    ),
                    label: Text(running ? 'Stop server' : 'Run file server'),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  onPressed: _copyAddress,
                  tooltip: 'Copy address',
                  icon: const Icon(Icons.link_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _permissionCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card.filled(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.folder_special_rounded,
              color: scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'All-files access',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Needed to share folders outside the app storage.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _requestAccess,
              child: const Text('Grant'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorCard(BuildContext context, FileServerController controller) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card.filled(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: scheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                controller.errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
            IconButton(
              onPressed: controller.clearError,
              tooltip: 'Dismiss',
              icon: Icon(Icons.close_rounded, color: scheme.onErrorContainer),
            ),
          ],
        ),
      ),
    );
  }

  Widget _connectionCard(
    BuildContext context,
    FileServerController controller,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final running = controller.isRunning;

    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.tune_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Connection',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _token,
              enabled: !running,
              obscureText: _obscureToken,
              onChanged: controller.updateToken,
              decoration: InputDecoration(
                labelText: 'Access token',
                helperText: 'Use the same token on the Mac client.',
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: _obscureToken ? 'Show token' : 'Hide token',
                      onPressed: () =>
                          setState(() => _obscureToken = !_obscureToken),
                      icon: Icon(
                        _obscureToken
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy token',
                      onPressed: _copyToken,
                      icon: const Icon(Icons.copy_rounded, size: 20),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: controller.selectedIp,
                    decoration: const InputDecoration(labelText: 'Local IPv4'),
                    hint: const Text('No address'),
                    items: [
                      for (final address in controller.addresses)
                        DropdownMenuItem<String>(
                          value: address,
                          child: Text(address),
                        ),
                    ],
                    onChanged: running
                        ? null
                        : (value) {
                            if (value != null) controller.selectAddress(value);
                          },
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _port,
                    enabled: !running,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (value) {
                      final port = int.tryParse(value);
                      if (port != null && port > 0 && port < 65536) {
                        controller.updatePort(port);
                      }
                    },
                    decoration: const InputDecoration(labelText: 'Port'),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: running ? null : controller.refreshAddresses,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Refresh IP'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mountsSection(BuildContext context, FileServerController controller) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final running = controller.isRunning;
    final mounts = controller.config.mounts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Shared folders',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: running ? null : _addMount,
              icon: const Icon(Icons.create_new_folder_rounded, size: 18),
              label: const Text('Add folder'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (mounts.isEmpty)
          Card.outlined(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.folder_off_rounded,
                    size: 34,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No folders shared yet.',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add a folder and the Mac can pull or push files into it.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          for (var index = 0; index < mounts.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card.outlined(
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.folder_rounded,
                      size: 20,
                      color: scheme.primary,
                    ),
                  ),
                  title: Text(
                    mounts[index].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    mounts[index].path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: PopupMenuButton<_MountAction>(
                    enabled: !running,
                    tooltip: 'Folder actions',
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (action) {
                      switch (action) {
                        case _MountAction.rename:
                          _renameMount(index);
                        case _MountAction.changeFolder:
                          _changeFolder(index);
                        case _MountAction.remove:
                          _confirmRemove(index);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _MountAction.rename,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.drive_file_rename_outline),
                          title: Text('Rename'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _MountAction.changeFolder,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.folder_open_rounded),
                          title: Text('Change folder'),
                        ),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: _MountAction.remove,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.delete_outline_rounded),
                          title: Text('Remove'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }

  Widget _hintCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lightbulb_outline_rounded,
            size: 18,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'On the Mac, add this device as '
              'http://<ip>:<port>/<mount> with the same token. Both devices '
              'must be on the same Wi-Fi or reachable through a tunnel.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSecondaryContainer,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
