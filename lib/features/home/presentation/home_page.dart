import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('File Sync Pro')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sync_alt, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('局域网文件同步', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '同步内核正在开发中',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
