import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../application/sync_engine.dart';
import '../domain/sync_plan.dart';
import 'sync_dashboard_controller.dart';

/// The comparison/todo table plus the activity log.
class SyncPreviewArea extends StatelessWidget {
  const SyncPreviewArea({super.key, required this.controller});

  final SyncDashboardController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller.errorMessage != null) ...[
            _ErrorBanner(controller: controller),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final preview = _PreviewPanel(controller: controller);
                final log = _LogPanel(controller: controller);
                if (constraints.maxWidth >= 900) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 3, child: preview),
                      const SizedBox(width: 12),
                      Expanded(flex: 2, child: log),
                    ],
                  );
                }
                return Column(
                  children: [
                    Expanded(flex: 3, child: preview),
                    const SizedBox(height: 12),
                    Expanded(flex: 2, child: log),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The bottom action row: check, sync, and progress.
class SyncBottomBar extends StatelessWidget {
  const SyncBottomBar({super.key, required this.controller});

  final SyncDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final plan = controller.preview?.plan;
    final progress = controller.total == 0
        ? null
        : controller.applied / controller.total;
    final busy = controller.busy;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      decoration: BoxDecoration(
        color: theme.colors.card,
        border: Border(top: BorderSide(color: theme.colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller.status == SyncDashboardStatus.scanning)
            const FProgress(),
          if (controller.status == SyncDashboardStatus.applying)
            if (progress != null)
              FDeterminateProgress(value: progress)
            else
              const FProgress(),
          if (controller.status == SyncDashboardStatus.resolving)
            const FProgress(),
          if (busy) const SizedBox(height: 10),
          Row(
            children: [
              FButton(
                key: const ValueKey<String>('sync.check'),
                variant: FButtonVariant.outline,
                onPress: busy ? null : controller.check,
                prefix: const Icon(FLucideIcons.listChecks, size: 15),
                child: const Text('Check'),
              ),
              const SizedBox(width: 8),
              FButton(
                key: const ValueKey<String>('sync.run'),
                onPress: busy ? null : controller.sync,
                prefix: const Icon(FLucideIcons.refreshCw, size: 15),
                child: const Text('Sync'),
              ),
              const SizedBox(width: 14),
              if (busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: FCircularProgress(),
                )
              else
                Icon(
                  controller.status == SyncDashboardStatus.error
                      ? FLucideIcons.circleAlert
                      : FLucideIcons.circleCheck,
                  size: 16,
                  color: controller.status == SyncDashboardStatus.error
                      ? theme.colors.destructive
                      : const Color(0xFF2EA121),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  controller.statusLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.typography.body.sm.copyWith(
                    color: theme.colors.mutedForeground,
                  ),
                ),
              ),
              if (plan != null)
                FBadge(
                  variant: FBadgeVariant.outline,
                  child: Text(
                    '${plan.createCount + plan.updateCount} changes · '
                    '${plan.conflicts.length} conflicts',
                  ),
                ),
            ],
          ),
          if (controller.currentPath != null &&
              controller.status == SyncDashboardStatus.applying) ...[
            const SizedBox(height: 6),
            Text(
              controller.currentPath!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.body.xs.copyWith(
                fontFamily: 'monospace',
                color: theme.colors.mutedForeground,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.controller});

  final SyncDashboardController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: FAlert(
            variant: FAlertVariant.destructive,
            title: const Text('Sync failed'),
            subtitle: Text(controller.errorMessage!),
            icon: const Icon(FLucideIcons.circleAlert),
          ),
        ),
        const SizedBox(width: 8),
        FButton.icon(
          key: const ValueKey<String>('sync.error.dismiss'),
          variant: FButtonVariant.ghost,
          onPress: controller.clearError,
          semanticsTooltip: 'Dismiss',
          child: const Icon(FLucideIcons.x, size: 15),
        ),
      ],
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({required this.controller});

  final SyncDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final preview = controller.preview;
    final report = controller.report;
    final conflicts = controller.conflicts;

    final String subtitle;
    if (preview != null) {
      subtitle =
          '${preview.plan.actions.length} actions · '
          '${conflicts.length} conflicts';
    } else if (report != null) {
      subtitle =
          '${report.applyReport?.created ?? 0} created · '
          '${report.applyReport?.updated ?? 0} updated · '
          '${report.applyReport?.deleted ?? 0} deleted';
    } else {
      subtitle = 'Run Check to compare both sides.';
    }

    return _PanelCard(
      title: 'Changes',
      subtitle: subtitle,
      child: preview != null
          ? (preview.plan.isEmpty && conflicts.isEmpty)
                ? const _EmptyState(
                    icon: FLucideIcons.circleCheck,
                    text: 'Already in sync.',
                  )
                : _PlanList(plan: preview.plan, controller: controller)
          : report != null
          ? _SummaryView(report: report, controller: controller)
          : const _EmptyState(
              icon: FLucideIcons.listChecks,
              text: 'Click Check to scan both sides.',
            ),
    );
  }
}

class _SummaryView extends StatelessWidget {
  const _SummaryView({required this.report, required this.controller});

  final SyncReport report;
  final SyncDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final apply = report.applyReport;
    final conflicts = controller.conflicts;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 30, 16, 18),
      children: [
        Icon(
          report.hasConflicts
              ? FLucideIcons.alertTriangle
              : FLucideIcons.circleCheck,
          size: 30,
          color: report.hasConflicts
              ? const Color(0xFFD4A106)
              : const Color(0xFF2EA121),
        ),
        const SizedBox(height: 10),
        Text(
          report.hasConflicts
              ? 'Sync finished with conflicts'
              : 'Sync complete',
          textAlign: TextAlign.center,
          style: theme.typography.body.lg.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          report.conflictBackupRoot == null
              ? 'Both sides now match.'
              : 'Conflicting files were left untouched. Their copies are in '
                    '${report.conflictBackupRoot}.',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.typography.body.xs.copyWith(
            color: theme.colors.mutedForeground,
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Stat(label: 'Created', value: apply?.created ?? 0),
            const SizedBox(width: 10),
            _Stat(label: 'Updated', value: apply?.updated ?? 0),
            const SizedBox(width: 10),
            _Stat(label: 'Deleted', value: apply?.deleted ?? 0),
            const SizedBox(width: 10),
            _Stat(label: 'Conflicts', value: conflicts.length),
          ],
        ),
        if (conflicts.isNotEmpty) ...[
          const SizedBox(height: 22),
          _ConflictSection(conflicts: conflicts, controller: controller),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colors.muted.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colors.border),
      ),
      child: Column(
        children: [
          Text(
            '$value',
            style: theme.typography.body.lg.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.typography.body.xs.copyWith(
              color: theme.colors.mutedForeground,
            ),
          ),
        ],
      ),
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

    return ListView(
      key: const ValueKey<String>('sync.plan.list'),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      children: [
        if (uploads.isNotEmpty)
          _ActionSection(
            key: const ValueKey<String>('sync.section.uploads'),
            title: 'Upload to the peer',
            icon: FLucideIcons.arrowUp,
            color: const Color(0xFF2EA121),
            actions: uploads,
          ),
        if (downloads.isNotEmpty)
          _ActionSection(
            key: const ValueKey<String>('sync.section.downloads'),
            title: 'Download to this Mac',
            icon: FLucideIcons.arrowDown,
            color: const Color(0xFF3370FF),
            actions: downloads,
          ),
        if (deletes.isNotEmpty)
          _ActionSection(
            key: const ValueKey<String>('sync.section.deletes'),
            title: 'Delete',
            icon: FLucideIcons.trash2,
            color: const Color(0xFFD83931),
            actions: deletes,
          ),
        if (plan.conflicts.isNotEmpty)
          _ConflictSection(conflicts: plan.conflicts, controller: controller),
        if (plan.actions.length > _displayLimit)
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              'Only the first $_displayLimit actions are shown.',
              style: context.theme.typography.body.xs.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
            ),
          ),
      ],
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
    final theme = context.theme;
    final visible = actions.take(300).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
            child: Row(
              children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 7),
                Text(
                  '$title (${actions.length})',
                  style: theme.typography.body.sm.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          FItemGroup(
            divider: FItemDivider.full,
            children: [
              for (final action in visible)
                FItem(
                  key: ValueKey<String>('sync.action.${action.path}'),
                  prefix: Icon(
                    action.isDelete
                        ? FLucideIcons.trash2
                        : FLucideIcons.fileText,
                    size: 14,
                    color: theme.colors.mutedForeground,
                  ),
                  title: Text(
                    action.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.typography.body.xs.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConflictSection extends StatelessWidget {
  const _ConflictSection({required this.conflicts, required this.controller});

  final List<SyncConflict> conflicts;
  final SyncDashboardController controller;

  Future<void> _keepAll(BuildContext context, ConflictSide side) async {
    final sideName = side == ConflictSide.left ? 'local' : 'remote';
    final confirmed = await showFDialog<bool>(
      context: context,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        constraints: const BoxConstraints(minWidth: 380, maxWidth: 460),
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Keep all $sideName?', style: style.titleTextStyle),
              const SizedBox(height: 8),
              Text(
                'All ${conflicts.length} conflicting file(s) will use the '
                '$sideName version. The other versions stay in the conflict '
                'backup folder.',
                style: style.bodyTextStyle,
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FButton(
                    variant: FButtonVariant.outline,
                    onPress: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FButton(
                    key: ValueKey<String>('sync.conflict.keepAll.${side.name}'),
                    onPress: () => Navigator.of(context).pop(true),
                    child: Text('Keep all $sideName'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return;
    await controller.resolveAllConflicts(side);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final canResolve = controller.report != null && !controller.busy;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
            child: Row(
              children: [
                const Icon(
                  FLucideIcons.alertTriangle,
                  size: 15,
                  color: Color(0xFFD4A106),
                ),
                const SizedBox(width: 7),
                Text(
                  'Conflicts (${conflicts.length})',
                  style: theme.typography.body.sm.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Keep one version. The other copy stays in the backup '
                    'folder.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.typography.body.xs.copyWith(
                      color: theme.colors.mutedForeground,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FButton(
                  key: const ValueKey<String>('sync.conflict.keepAllLeft'),
                  variant: FButtonVariant.outline,
                  size: FButtonSizeVariant.sm,
                  onPress: canResolve
                      ? () => _keepAll(context, ConflictSide.left)
                      : null,
                  child: const Text('Keep all local'),
                ),
                const SizedBox(width: 6),
                FButton(
                  key: const ValueKey<String>('sync.conflict.keepAllRight'),
                  variant: FButtonVariant.outline,
                  size: FButtonSizeVariant.sm,
                  onPress: canResolve
                      ? () => _keepAll(context, ConflictSide.right)
                      : null,
                  child: const Text('Keep all remote'),
                ),
              ],
            ),
          ),
          FItemGroup(
            divider: FItemDivider.full,
            children: [
              for (final conflict in conflicts)
                FItem(
                  key: ValueKey<String>('sync.conflict.${conflict.path}'),
                  prefix: const Icon(
                    FLucideIcons.alertTriangle,
                    size: 14,
                    color: Color(0xFFD4A106),
                  ),
                  title: Text(
                    conflict.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.typography.body.xs.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                  subtitle: Text(conflict.reason.name),
                  suffix: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FButton(
                        key: ValueKey<String>(
                          'sync.conflict.keepLeft.${conflict.path}',
                        ),
                        variant: FButtonVariant.outline,
                        size: FButtonSizeVariant.sm,
                        onPress: canResolve
                            ? () => controller.resolveConflict(
                                conflict.path,
                                ConflictSide.left,
                              )
                            : null,
                        child: const Text('Keep local'),
                      ),
                      const SizedBox(width: 6),
                      FButton(
                        key: ValueKey<String>(
                          'sync.conflict.keepRight.${conflict.path}',
                        ),
                        variant: FButtonVariant.outline,
                        size: FButtonSizeVariant.sm,
                        onPress: canResolve
                            ? () => controller.resolveConflict(
                                conflict.path,
                                ConflictSide.right,
                              )
                            : null,
                        child: const Text('Keep remote'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LogPanel extends StatelessWidget {
  const _LogPanel({required this.controller});

  final SyncDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final lines = controller.log;
    return _PanelCard(
      title: 'Activity',
      subtitle: lines.isEmpty ? 'No activity yet.' : '${lines.length} lines',
      child: lines.isEmpty
          ? const _EmptyState(
              icon: FLucideIcons.activity,
              text: 'Scan or sync to see activity here.',
            )
          : ListView.builder(
              key: const ValueKey<String>('sync.log'),
              reverse: true,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              itemCount: lines.length,
              itemBuilder: (context, index) {
                final line = lines[lines.length - 1 - index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    line,
                    style: theme.typography.body.xs.copyWith(
                      fontFamily: 'monospace',
                      height: 1.4,
                      color: line.contains('ERROR')
                          ? theme.colors.destructive
                          : theme.colors.mutedForeground,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return FCard(
      style: FCardStyleDelta.delta(
        padding: EdgeInsetsGeometryDelta.value(EdgeInsets.zero),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.typography.body.md.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.typography.body.xs.copyWith(
                    color: theme.colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: theme.colors.border),
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
    final theme = context.theme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 24,
            color: theme.colors.mutedForeground.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.typography.body.sm.copyWith(
              color: theme.colors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}
