import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../features/server/presentation/file_server_page.dart';
import '../features/sync/presentation/sync_workspace_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.projectRoot,
    required this.clientConfigPath,
    required this.serverConfigPath,
  });

  final String projectRoot;
  final String clientConfigPath;
  final String serverConfigPath;

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
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (index) => setState(() => _index = index),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.sync, key: ValueKey<String>('nav.sync')),
                label: Text('Sync'),
              ),
              NavigationRailDestination(
                icon: Icon(
                  Icons.dns_outlined,
                  key: ValueKey<String>('nav.server'),
                ),
                label: Text('Server'),
              ),
            ],
          ),
          VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
          Expanded(
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
          ),
        ],
      ),
    );
  }
}
