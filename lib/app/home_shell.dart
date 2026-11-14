import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../features/server/presentation/file_server_page.dart';
import '../features/sync/presentation/sync_workspace_page.dart';

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

  @override
  void initState() {
    super.initState();
    _index = defaultTargetPlatform == TargetPlatform.windows ? 1 : 0;
  }

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      childPad: false,
      sidebar: FSidebar(
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
              style: context.theme.typography.body.xs.copyWith(
                color: context.theme.colors.mutedForeground,
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
                icon: const Icon(FLucideIcons.server),
                label: const Text('File server'),
                selected: _index == 1,
                onPress: () => setState(() => _index = 1),
              ),
            ],
          ),
        ],
      ),
      child: IndexedStack(
        index: _index,
        children: [
          SyncWorkspacePage(
            configPath: widget.clientConfigPath,
            projectRoot: widget.projectRoot,
          ),
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
