import 'package:flutter/material.dart';

import '../features/home/presentation/home_page.dart';
import 'theme.dart';

class FileSyncProApp extends StatelessWidget {
  const FileSyncProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'File Sync Pro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const HomePage(),
    );
  }
}
