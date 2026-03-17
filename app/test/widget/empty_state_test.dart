import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/widgets/empty_state.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('EmptyState rendering', () {
    testWidgets('displays message', (tester) async {
      await tester.pumpWidget(
        _wrap(const EmptyState(message: 'No items found')),
      );
      expect(find.text('No items found'), findsOneWidget);
    });

    testWidgets('does not show action button by default', (tester) async {
      await tester.pumpWidget(
        _wrap(const EmptyState(message: 'No items')),
      );
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('shows action button when label and callback provided', (tester) async {
      await tester.pumpWidget(
        _wrap(EmptyState(
          message: 'No items',
          actionLabel: 'Add First Item',
          onAction: () {},
        )),
      );
      expect(find.text('Add First Item'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('action button callback fires', (tester) async {
      var called = false;
      await tester.pumpWidget(
        _wrap(EmptyState(
          message: 'No items',
          actionLabel: 'Add',
          onAction: () => called = true,
        )),
      );
      await tester.tap(find.byType(FilledButton));
      expect(called, isTrue);
    });

    testWidgets('uses default inbox icon', (tester) async {
      await tester.pumpWidget(
        _wrap(const EmptyState(message: 'Empty')),
      );
      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    });

    testWidgets('uses custom icon when provided', (tester) async {
      await tester.pumpWidget(
        _wrap(const EmptyState(message: 'Empty', icon: Icons.search_off)),
      );
      expect(find.byIcon(Icons.search_off), findsOneWidget);
    });
  });
}
