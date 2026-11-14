import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../features/server/presentation/file_server_page.dart';
import '../features/sync/application/sync_config_store.dart';
import '../features/sync/presentation/devices_page.dart';
import '../features/sync/presentation/sync_workspace_page.dart';
import 'forui_theme.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.projectRoot,
    required this.clientConfigPath,
    required this.serverConfigPath,
    required this.isDark,
    required this.onToggleTheme,
  });

  final String projectRoot;
  final String clientConfigPath;
  final String serverConfigPath;
  final bool isDark;
  final VoidCallback onToggleTheme;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _index;
  late final SyncConfigStore _store;

  @override
  void initState() {
    super.initState();
    _index = defaultTargetPlatform == TargetPlatform.windows ? 2 : 0;
    _store = SyncConfigStore(
      path: widget.clientConfigPath,
      projectRoot: widget.projectRoot,
    );
    _store.load();
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return FScaffold(
      childPad: false,
      scaffoldStyle: AppForuiTheme.scaffoldStyle(dark: widget.isDark),
      sidebar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: theme.colors.border)),
        ),
        child: FSidebar(
          header: const _Brand(),
          footer: _SidebarFooter(
            isDark: widget.isDark,
            onToggleTheme: widget.onToggleTheme,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Text(
                'WORKSPACE',
                style: theme.typography.body.xs.copyWith(
                  color: theme.colors.mutedForeground,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.9,
                ),
              ),
            ),
            FSidebarGroup(
              children: [
                FSidebarItem(
                  icon: const Icon(FLucideIcons.refreshCw),
                  label: const Text('Sync'),
                  selected: _index == 0,
                  onPress: () => setState(() => _index = 0),
                ),
                FSidebarItem(
                  icon: const Icon(FLucideIcons.router),
                  label: const Text('Devices'),
                  selected: _index == 1,
                  onPress: () => setState(() => _index = 1),
                ),
                FSidebarItem(
                  icon: const Icon(FLucideIcons.server),
                  label: const Text('File server'),
                  selected: _index == 2,
                  onPress: () => setState(() => _index = 2),
                ),
              ],
            ),
          ],
        ),
      ),
      child: IndexedStack(
        index: _index,
        children: [
          SyncWorkspacePage(store: _store),
          DevicesPage(store: _store),
          FileServerPage(
            configPath: widget.serverConfigPath,
            projectRoot: widget.projectRoot,
          ),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: theme.colors.primary,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              FLucideIcons.arrowRightLeft,
              size: 17,
              color: theme.colors.primaryForeground,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'File Sync Pro',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.typography.body.sm.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  'LAN file sync',
                  style: theme.typography.body.xs.copyWith(
                    color: theme.colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({required this.isDark, required this.onToggleTheme});

  final bool isDark;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FButton(
            variant: FButtonVariant.ghost,
            size: FButtonSizeVariant.sm,
            onPress: onToggleTheme,
            prefix: Icon(
              isDark ? FLucideIcons.sun : FLucideIcons.moon,
              size: 15,
            ),
            child: Text(isDark ? 'Light mode' : 'Dark mode'),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF2EA121),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'v0.3.0 · desktop',
                    style: theme.typography.body.xs.copyWith(
                      color: theme.colors.mutedForeground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
