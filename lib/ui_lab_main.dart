import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// A standalone Forui design lab.
///
/// Run with:
///   flutter run -t lib/ui_lab_main.dart -d macos
void main() {
  runApp(const ForuiLabApp());
}

class ForuiLabApp extends StatelessWidget {
  const ForuiLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = FTheme.neutral.light.desktop;
    return MaterialApp(
      title: 'Forui Lab',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(),
      localizationsDelegates: FLocalizations.localizationsDelegates,
      supportedLocales: FLocalizations.supportedLocales,
      builder: (context, child) => FTheme(
        data: theme,
        child: FToaster(child: FTooltipGroup(child: child!)),
      ),
      home: const _LabShell(),
    );
  }
}

class _LabShell extends StatefulWidget {
  const _LabShell();

  @override
  State<_LabShell> createState() => _LabShellState();
}

class _LabShellState extends State<_LabShell> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      sidebar: FSidebar(
        header: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 12, 10),
          child: Row(
            children: [
              Icon(FLucideIcons.refreshCw, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'File Sync Pro',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.theme.typography.body.md.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        footer: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            'Forui design lab',
            style: context.theme.typography.body.xs.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
        ),
        children: [
          FSidebarGroup(
            label: const Text('Workspace'),
            children: [
              FSidebarItem(
                icon: const Icon(FLucideIcons.refreshCw),
                label: const Text('Sync'),
                selected: _index == 0,
                onPress: () => setState(() => _index = 0),
              ),
              FSidebarItem(
                icon: const Icon(FLucideIcons.server),
                label: const Text('File server'),
                selected: _index == 1,
                onPress: () => setState(() => _index = 1),
              ),
            ],
          ),
        ],
      ),
      child: _index == 0 ? const _SyncDemo() : const _ServerDemo(),
    );
  }
}

class _SyncDemo extends StatefulWidget {
  const _SyncDemo();

  @override
  State<_SyncDemo> createState() => _SyncDemoState();
}

class _SyncDemoState extends State<_SyncDemo> {
  var _pair = 'photolens';

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sync',
                        style: theme.typography.display.sm.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Local folder to remote file server',
                        style: theme.typography.body.sm.copyWith(
                          color: theme.colors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 190,
                    child: FSelect<String>(
                      control: FSelectControl<String>.managed(
                        initial: _pair,
                        onChange: (value) =>
                            setState(() => _pair = value ?? 'photolens'),
                      ),
                      label: const Text('Sync pair'),
                      items: const {
                        'photolens': 'photolens',
                        'notes': 'notes',
                        'design-assets': 'design-assets',
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  FButton(
                    variant: FButtonVariant.outline,
                    onPress: () {},
                    prefix: const Icon(FLucideIcons.pencil, size: 15),
                    child: const Text('Edit'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              FCard(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: FItemGroup(
                    divider: FItemDivider.full,
                    children: [
                      FItem(
                        prefix: Icon(FLucideIcons.computer),
                        title: Text('Local folder'),
                        subtitle: Text('/Users/likianta/photolens'),
                        details: Text('this device'),
                      ),
                      FItem(
                        prefix: Icon(FLucideIcons.cloud),
                        title: Text('Remote mount'),
                        subtitle: Text('http://47.102.108.149:2160/photolens'),
                        details: Text('remote'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  FButton(
                    variant: FButtonVariant.outline,
                    onPress: () {},
                    prefix: const Icon(FLucideIcons.check, size: 15),
                    child: const Text('Check'),
                  ),
                  const SizedBox(width: 8),
                  FButton(
                    onPress: () {},
                    prefix: const Icon(FLucideIcons.refreshCw, size: 15),
                    child: const Text('Sync'),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    '3 changes, 1 conflict',
                    style: theme.typography.body.sm.copyWith(
                      color: theme.colors.mutedForeground,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 220,
                    child: FDeterminateProgress(value: 0.42),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: FCard(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _SectionTitle(
                              icon: FLucideIcons.arrowUp,
                              title: 'Upload to remote',
                              count: 2,
                            ),
                            const SizedBox(height: 6),
                            FItemGroup(
                              divider: FItemDivider.full,
                              children: [
                                FItem(
                                  prefix: Icon(FLucideIcons.fileText),
                                  title: Text('src/photolens/workbench.py'),
                                  details: Text('updated'),
                                ),
                                FItem(
                                  prefix: Icon(FLucideIcons.fileText),
                                  title: Text('docs/goal.zh.md'),
                                  details: Text('new'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _SectionTitle(
                              icon: FLucideIcons.arrowDown,
                              title: 'Download to this device',
                              count: 3,
                            ),
                            const SizedBox(height: 6),
                            FItemGroup(
                              divider: FItemDivider.full,
                              children: [
                                FItem(
                                  prefix: Icon(FLucideIcons.fileText),
                                  title: Text('database.db'),
                                  details: Text('updated'),
                                ),
                                FItem(
                                  prefix: Icon(FLucideIcons.folder),
                                  title: Text('tmp/cache'),
                                  details: Text('new'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _SectionTitle(
                              icon: FLucideIcons.alertTriangle,
                              title: 'Conflict',
                              count: 1,
                            ),
                            const SizedBox(height: 8),
                            FItem(
                              prefix: const Icon(FLucideIcons.fileText),
                              title: const Text('docs/readme.md'),
                              subtitle: const Text(
                                'Both sides changed this file',
                              ),
                              suffix: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  FButton(
                                    variant: FButtonVariant.outline,
                                    onPress: () {},
                                    child: const Text('Keep local'),
                                  ),
                                  const SizedBox(width: 6),
                                  FButton(
                                    variant: FButtonVariant.outline,
                                    onPress: () {},
                                    child: const Text('Keep remote'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 2,
                    child: FCard(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Activity',
                                  style: theme.typography.body.md.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '12 lines',
                                  style: theme.typography.body.xs.copyWith(
                                    color: theme.colors.mutedForeground,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '10:42:01  Scanning both sides...\n'
                              '10:42:03  Plan: 2 create, 2 update, 1 delete\n'
                              '10:42:04  +> upload src/photolens/workbench.py\n'
                              '10:42:04  <+ download database.db\n'
                              '10:42:05  => upload docs/goal.zh.md\n'
                              '10:42:06  ! conflict docs/readme.md\n'
                              '10:42:06  1 conflict left untouched',
                              style: theme.typography.body.xs.copyWith(
                                fontFamily: 'monospace',
                                height: 1.6,
                                color: theme.colors.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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

class _ServerDemo extends StatefulWidget {
  const _ServerDemo();

  @override
  State<_ServerDemo> createState() => _ServerDemoState();
}

class _ServerDemoState extends State<_ServerDemo> {
  final _token = TextEditingController(text: 'demo-token-8f31c2');
  final _port = TextEditingController(text: '2160');
  var _ip = '192.168.1.23';
  var _running = false;
  var _mounts = <(String, String)>[
    ('photolens', 'C:/Likianta/workspace/dev.master.likianta/photolens'),
    ('design-assets', 'C:/Likianta/workspace/design-assets'),
  ];

  @override
  void dispose() {
    _token.dispose();
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'File server',
                        style: theme.typography.display.sm.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Share folders with other devices over HTTP',
                        style: theme.typography.body.sm.copyWith(
                          color: theme.colors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  _Status(
                    running: _running,
                    label: _running
                        ? 'Serving on 0.0.0.0:${_port.text}'
                        : 'Stopped',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              FCard(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FTextField(
                        control: FTextFieldControl.managed(controller: _token),
                        label: const Text('Input token'),
                        hint: 'Clients must use the same token',
                        description: const Text(
                          'Required before the server starts.',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            flex: 3,
                            child: FSelect<String>(
                              control: FSelectControl<String>.managed(
                                initial: _ip,
                                onChange: (value) =>
                                    setState(() => _ip = value ?? _ip),
                              ),
                              label: const Text('Local IPv4'),
                              items: const {
                                '192.168.1.23': '192.168.1.23',
                                '10.0.0.5': '10.0.0.5',
                                '172.16.8.20': '172.16.8.20',
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 130,
                            child: FTextField(
                              control: FTextFieldControl.managed(
                                controller: _port,
                              ),
                              label: const Text('Port'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FButton(
                            onPress: () => setState(() => _running = !_running),
                            prefix: Icon(
                              _running
                                  ? FLucideIcons.square
                                  : FLucideIcons.play,
                              size: 15,
                            ),
                            child: Text(
                              _running ? 'Stop server' : 'Run file server',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'The server listens on 0.0.0.0:${_port.text}. '
                        'Expose it with frp or another tunnel.',
                        style: theme.typography.body.xs.copyWith(
                          color: theme.colors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FCard(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Shared folders',
                            style: theme.typography.body.lg.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          FButton(
                            variant: FButtonVariant.outline,
                            onPress: () => setState(() {
                              _mounts = [
                                ..._mounts,
                                ('new-folder', 'C:/choose/a/folder'),
                              ];
                            }),
                            prefix: const Icon(FLucideIcons.folder, size: 15),
                            child: const Text('Add folder'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      FItemGroup(
                        divider: FItemDivider.full,
                        children: [
                          for (var i = 0; i < _mounts.length; i++)
                            FItem(
                              prefix: const Icon(FLucideIcons.folder),
                              title: Text(_mounts[i].$1),
                              subtitle: Text(_mounts[i].$2),
                              details: Text('${i + 1} folder'),
                              suffix: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  FButton.icon(
                                    variant: FButtonVariant.ghost,
                                    onPress: () {},
                                    child: const Icon(
                                      FLucideIcons.pencil,
                                      size: 15,
                                    ),
                                  ),
                                  FButton.icon(
                                    variant: FButtonVariant.ghost,
                                    onPress: () {},
                                    child: const Icon(
                                      FLucideIcons.settings,
                                      size: 15,
                                    ),
                                  ),
                                  FButton.icon(
                                    variant: FButtonVariant.ghost,
                                    onPress: () => setState(
                                      () => _mounts = [..._mounts]..removeAt(i),
                                    ),
                                    child: const Icon(
                                      FLucideIcons.trash2,
                                      size: 15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.running, required this.label});

  final bool running;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: running ? const Color(0xFF2EA121) : const Color(0xFF999999),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.typography.body.sm.copyWith(
            color: theme.colors.mutedForeground,
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.count,
  });

  final IconData icon;
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Row(
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 8),
        Text(
          '$title ($count)',
          style: theme.typography.body.md.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
