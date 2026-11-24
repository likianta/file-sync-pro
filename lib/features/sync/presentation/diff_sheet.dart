import 'package:flutter/material.dart';

import '../domain/sync_plan.dart';
import 'sync_dashboard_controller.dart';

/// Opens the diff table in an animated bottom sheet.
Future<void> showSyncDiffSheet(
  BuildContext context,
  SyncDashboardController controller,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: double.infinity),
    builder: (context) => AnimatedBuilder(
      animation: controller,
      builder: (context, _) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        builder: (context, scrollController) => _DiffSheetBody(
          controller: controller,
          scrollController: scrollController,
        ),
      ),
    ),
  );
}

class _DiffSheetBody extends StatelessWidget {
  const _DiffSheetBody({
    required this.controller,
    required this.scrollController,
  });

  final SyncDashboardController controller;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = controller.diffPlan;
    final scope = controller.diffSubPath;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 10, 10),
          child: Row(
            children: [
              Icon(
                Icons.fact_check_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Changes',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  plan == null
                      ? 'Run Check to compare both sides.'
                      : '${scope ?? 'Whole tree'} · '
                            '${plan.actions.length} actions · '
                            '${plan.conflicts.length} conflicts',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (controller.busy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        Expanded(
          child: plan == null
              ? const Center(child: Text('Nothing to compare yet.'))
              : _DiffList(plan: plan, scrollController: scrollController),
        ),
      ],
    );
  }
}

class _DiffList extends StatelessWidget {
  const _DiffList({required this.plan, required this.scrollController});

  final SyncPlan plan;
  final ScrollController scrollController;

  static const _limit = 500;

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

    final rows = <Widget>[];
    void addSection(
      String title,
      IconData icon,
      Color color,
      List<SyncAction> actions,
      String label,
    ) {
      if (actions.isEmpty) return;
      rows.add(
        _SectionHeader(
          title: '$title (${actions.length})',
          icon: icon,
          color: color,
        ),
      );
      for (final action in actions.take(_limit)) {
        rows.add(
          _ActionRow(
            key: ValueKey<String>('diff.action.${action.path}'),
            path: action.path,
            label: label,
            color: color,
          ),
        );
      }
    }

    addSection(
      'Upload to peer',
      Icons.arrow_upward,
      const Color(0xFF2EA121),
      uploads,
      'push',
    );
    addSection(
      'Download to this machine',
      Icons.arrow_downward,
      const Color(0xFF3370FF),
      downloads,
      'pull',
    );
    addSection(
      'Delete',
      Icons.delete_outline,
      const Color(0xFFD83931),
      deletes,
      'delete',
    );

    if (plan.conflicts.isNotEmpty) {
      rows.add(
        _SectionHeader(
          title: 'Conflicts (${plan.conflicts.length})',
          icon: Icons.warning_amber_outlined,
          color: const Color(0xFFD4A106),
        ),
      );
      for (final conflict in plan.conflicts.take(_limit)) {
        rows.add(
          _ConflictRow(
            key: ValueKey<String>('diff.conflict.${conflict.path}'),
            conflict: conflict,
          ),
        );
      }
    }

    if (plan.actions.isEmpty && plan.conflicts.isEmpty) {
      return Center(
        child: Text(
          'Both sides are already in sync.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
      children: [
        ...rows,
        if (plan.actions.length > _limit)
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              'Only the first $_limit actions are shown.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.color,
  });

  final String title;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Text(
            title,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    super.key,
    required this.path,
    required this.label,
    required this.color,
  });

  final String path;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          _Pill(label: label, color: color),
        ],
      ),
    );
  }
}

class _ConflictRow extends StatelessWidget {
  const _ConflictRow({super.key, required this.conflict});

  final SyncConflict conflict;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conflict.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
                Text(
                  conflict.reason.name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Sync keeps local',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
