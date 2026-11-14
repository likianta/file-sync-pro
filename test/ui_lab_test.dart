import 'dart:ui' show Size;

import 'package:file_sync_pro/ui_lab_main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Forui lab renders both pages', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ForuiLabApp());
    await tester.pumpAndSettle();

    expect(find.text('Sync'), findsWidgets);
    expect(find.textContaining('Upload to remote'), findsOneWidget);

    await tester.tap(find.text('File server'));
    await tester.pumpAndSettle();

    expect(find.text('Input token'), findsOneWidget);
    expect(find.text('Shared folders'), findsOneWidget);
    expect(find.text('Run file server'), findsOneWidget);
  });
}
