import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/widgets/confirm_dialog.dart';

void main() {
  testWidgets('ConfirmDialog shows localized default action labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ConfirmDialog(
            title: 'Delete item',
            message: 'This action cannot be undone.',
          ),
        ),
      ),
    );

    expect(find.text('Delete item'), findsOneWidget);
    expect(find.text('This action cannot be undone.'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
  });

  testWidgets('ConfirmDialog shows loading state during async confirm', (
    tester,
  ) async {
    final completer = Completer<bool>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConfirmDialog(
            title: 'Delete item',
            message: 'This action cannot be undone.',
            onConfirmAsync: () => completer.future,
          ),
        ),
      ),
    );

    await tester.tap(find.text('OK'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(true);
    await tester.pumpAndSettle();
  });
}
