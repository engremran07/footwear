import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/widgets/empty_state.dart';

void main() {
  testWidgets('EmptyState renders message, key, and actions', (tester) async {
    var primaryTapped = false;
    var secondaryTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyState(
            message: 'No data',
            actionLabel: 'Retry',
            onAction: () => primaryTapped = true,
            secondaryActionLabel: 'Back',
            onSecondaryAction: () => secondaryTapped = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('empty_state_No data')), findsOneWidget);
    expect(find.text('No data'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.tap(find.text('Back'));
    await tester.pump();

    expect(primaryTapped, isTrue);
    expect(secondaryTapped, isTrue);
  });
}
