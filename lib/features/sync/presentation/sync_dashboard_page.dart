import 'package:flutter/material.dart';

import '../application/sync_engine.dart';
import '../application/sync_pair_config.dart';
import '../domain/sync_plan.dart';
import 'sync_dashboard_controller.dart';

class SyncDashboardPage extends StatefulWidget {
  const SyncDashboardPage({super.key, required this.config});

  final SyncPairConfig config;

  @override
  State<SyncDashboardPage> createState() => _SyncDashboardPageState();
}

class _SyncDashboardPageState extends State<SyncDashboardPage> {
  late final SyncDashboardController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SyncDashboardController(config: widget.config);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Scaffold(
          body: Column(
            children: [
              _Header(controller: _controller),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _PairCard(config: _controller.config),
                          const SizedBox(height: 12),
                          _Toolbar(controller: _controller),
                          if (_controller.errorMessage != null) ...[
                            const SizedBox(height: 12),
                            _ErrorBanner(controller: _controller),
                          ],
                          const SizedBox(height: 12),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final plan = _PlanPanel(
                                  controller: _controller,
                                );
                                final log = _LogPanel(controller: _controller);
                                if (constraints.maxWidth >= 900) {
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(flex: 3, child: plan),
                                      const SizedBox(width: 12),
                                      Expanded(flex: 2, child: log),
                                    ],
                                  );
                                }
                                return Column(
                                  children: [
                                    Expanded(flex: 3, child: plan),
                                    const SizedBox(height: 12),
                                    Expanded(flex: 2, child: log),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final SyncDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = switch (controller.status) {
      SyncDashboardStatus.idle => const Color(0xFF2EA121),
      SyncDashboardStatus.scanning ||
      SyncDashboardStatus.applying ||
      SyncDashboardStatus.resolving => theme.colorScheme.primary,
      SyncDashboardStatus.error => theme.colorScheme.error,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final showPlatformChips = constraints.maxWidth >= 900;
        return Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.sync_alt,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'File Sync Pro',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Mac to remote Windows over HTTP',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              _Chip(
                icon: Icons.folder_outlined,
                label: controller.config.pairName,
              ),
              if (showPlatformChips) ...[
                const SizedBox(width: 8),
                _Chip(icon: Icons.computer_outlined, label: 'macOS'),
                const SizedBox(width: 8),
                _Chip(icon: Icons.cloud_outlined, label: 'Windows / frp'),
              ],
              const SizedBox(width: 12),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  controller.statusLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PairCard extends StatelessWidget {
  const _PairCard({required this.config});

  final SyncPairConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _PathRow(
              icon: Icons.computer_outlined,
              label: 'Local folder',
              value: config.localRoot,
              badge: 'this Mac',
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: theme.dividerColor),
            const SizedBox(height: 12),
            _PathRow(
              icon: Icons.cloud_outlined,
              label: 'Remote mount',
              value: config.remoteUrl,
              badge: 'Windows',
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'State: ${config.stateDir}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PathRow extends StatelessWidget {
  const _PathRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.badge,
  });

  final IconData icon;
  final String label;
  final String value;
  final String badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            maxLines: 1,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
        ),
        const SizedBox(width: 8),
        _Chip(icon: Icons.verified_outlined, label: badge),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller});

  final SyncDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = controller.preview?.plan;
    final progress = controller.total == 0
        ? null
        : controller.applied / controller.total;

    return Column(
      children: [
        Row(
          children: [
            OutlinedButton.icon(
              key: const ValueKey<String>('sync.check'),
              onPressed: controller.busy ? null : controller.check,
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: const Text('Check'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const ValueKey<String>('sync.run'),
              onPressed: controller.busy ? null : controller.sync,
              icon: const Icon(Icons.sync, size: 18),
              label: const Text('Sync'),
            ),
            const SizedBox(width: 14),
            if (controller.busy)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                controller.status == SyncDashboardStatus.error
                    ? Icons.error_outline
                    : Icons.check_circle_outline,
                size: 16,
                color: controller.status == SyncDashboardStatus.error
                    ? theme.colorScheme.error
                    : const Color(0xFF2EA121),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                controller.statusLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (plan != null)
              Text(
                '${plan.createCount + plan.updateCount} changes, '
                '${plan.conflicts.length} conflicts',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        if (controller.status == SyncDashboardStatus.applying ||
            controller.status == SyncDashboardStatus.resolving) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              minHeight: 4,
              value: controller.status == SyncDashboardStatus.applying
                  ? progress
                  : null,
            ),
          ),
          if (controller.currentPath != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                controller.currentPath!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.controller});

  final SyncDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            size: 18,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              controller.errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
                height: 1.4,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey<String>('sync.error.dismiss'),
            onPressed: controller.clearError,
            icon: const Icon(Icons.close, size: 16),
            color: theme.colorScheme.onErrorContainer,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _PlanPanel extends StatelessWidget {
  const _PlanPanel({required this.controller});

  final SyncDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final preview = controller.preview;
    final plan = preview?.plan;
    final conflicts = plan?.conflicts ?? const <SyncConflict>[];

    return _Panel(
      title: 'Changes',
      subtitle: plan == null
          ? 'Run Check to compare both sides.'
          : '${plan.actions.length} actions, ${conflicts.length} conflicts',
      child: plan == null
          ? const _EmptyState(
              icon: Icons.rule_folder_outlined,
              text: 'Click Check to scan both sides.',
            )
          : plan.isEmpty && conflicts.isEmpty
          ? const _EmptyState(
              icon: Icons.check_circle_outline,
              text: 'Already in sync.',
            )
          : _PlanList(plan: plan, controller: controller),
    );
  }
}

class _PlanList extends StatelessWidget {
  const _PlanList({required this.plan, required this.controller});

  final SyncPlan plan;
  final SyncDashboardController controller;

  static const _displayLimit = 300;

  @override
  Widget build(BuildContext context) {
    final uploads = plan.actions
        .where(
          (action) =>
              action.kind == SyncActionKind.createRight ||
              action.kind == SyncActionKind.updateRight,
        )
        .toList();
    final downloads = plan.actions
        .where(
          (action) =>
              action.kind == SyncActionKind.createLeft ||
              action.kind == SyncActionKind.updateLeft,
        )
        .toList();
    final deletes = plan.actions.where((action) => action.isDelete).toList();

    final children = <Widget>[
      if (uploads.isNotEmpty)
        _ActionSection(
          key: const ValueKey<String>('sync.section.uploads'),
          title: 'Upload to Windows',
          icon: Icons.arrow_upward,
          color: const Color(0xFF2EA121),
          actions: uploads,
        ),
      if (downloads.isNotEmpty)
        _ActionSection(
          key: const ValueKey<String>('sync.section.downloads'),
          title: 'Download to this Mac',
          icon: Icons.arrow_downward,
          color: const Color(0xFF3370FF),
          actions: downloads,
        ),
      if (deletes.isNotEmpty)
        _ActionSection(
          key: const ValueKey<String>('sync.section.deletes'),
          title: 'Delete',
          icon: Icons.delete_outline,
          color: const Color(0xFFD83931),
          actions: deletes,
        ),
      if (plan.conflicts.isNotEmpty)
        _ConflictSection(conflicts: plan.conflicts, controller: controller),
      if (plan.actions.length > _displayLimit)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Only the first $_displayLimit actions are shown.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ];

    return ListView(
      key: const ValueKey<String>('sync.plan.list'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: children,
    );
  }
}

class _ActionSection extends StatelessWidget {
  const _ActionSection({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.actions,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<SyncAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = actions.take(300).toList();
    return ExpansionTile(
      initiallyExpanded: true,
      title: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            '$title (${actions.length})',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      childrenPadding: const EdgeInsets.only(bottom: 4),
      children: [
        for (final action in visible)
          Padding(
            key: ValueKey<String>('sync.action.${action.path}'),
            padding: const EdgeInsets.fromLTRB(40, 2, 16, 2),
            child: Row(
              children: [
                Text(
                  action.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ConflictSection extends StatelessWidget {
  const _ConflictSection({required this.conflicts, required this.controller});

  final List<SyncConflict> conflicts;
  final SyncDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canResolve = controller.report != null && !controller.busy;

    return ExpansionTile(
      key: const ValueKey<String>('sync.section.conflicts'),
      initiallyExpanded: true,
      title: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: Color(0xFFD4A106),
          ),
          const SizedBox(width: 8),
          Text(
            'Conflicts (${conflicts.length})',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      subtitle: Text(
        'Keep one version. The other copy stays in the conflict backup folder.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      children: [
        for (final conflict in conflicts)
          Padding(
            key: ValueKey<String>('sync.conflict.${conflict.path}'),
            padding: const EdgeInsets.fromLTRB(40, 4, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        conflict.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    Text(
                      conflict.reason.name,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFD4A106),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    TextButton(
                      key: ValueKey<String>(
                        'sync.conflict.keepLeft.${conflict.path}',
                      ),
                      onPressed: canResolve
                          ? () => controller.resolveConflict(
                              conflict.path,
                              ConflictSide.left,
                            )
                          : null,
                      child: const Text('Keep Mac'),
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      key: ValueKey<String>(
                        'sync.conflict.keepRight.${conflict.path}',
                      ),
                      onPressed: canResolve
                          ? () => controller.resolveConflict(
                              conflict.path,
                              ConflictSide.right,
                            )
                          : null,
                      child: const Text('Keep Windows'),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LogPanel extends StatelessWidget {
  const _LogPanel({required this.controller});

  final SyncDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = controller.log;
    return _Panel(
      title: 'Activity',
      subtitle: lines.isEmpty ? 'No activity yet.' : '${lines.length} lines',
      child: lines.isEmpty
          ? const _EmptyState(
              icon: Icons.receipt_long_outlined,
              text: 'Scan or sync to see activity here.',
            )
          : ListView.builder(
              key: const ValueKey<String>('sync.log'),
              reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              itemCount: lines.length,
              itemBuilder: (context, index) {
                final line = lines[lines.length - 1 - index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    line,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      height: 1.35,
                      color: line.contains('ERROR')
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.dividerColor),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 26,
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      text,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
