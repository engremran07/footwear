import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/widgets/status_chip.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('StatusChip rendering', () {
    testWidgets('displays status label uppercased', (tester) async {
      await tester.pumpWidget(_wrap(const StatusChip(status: 'pending')));
      expect(find.text('PENDING'), findsOneWidget);
    });

    testWidgets('replaces underscores with spaces', (tester) async {
      await tester.pumpWidget(_wrap(const StatusChip(status: 'in_production')));
      expect(find.text('IN PRODUCTION'), findsOneWidget);
    });

    testWidgets('renders for shipped status', (tester) async {
      await tester.pumpWidget(_wrap(const StatusChip(status: 'shipped')));
      expect(find.text('SHIPPED'), findsOneWidget);
    });

    testWidgets('renders for approved status', (tester) async {
      await tester.pumpWidget(_wrap(const StatusChip(status: 'approved')));
      expect(find.text('APPROVED'), findsOneWidget);
    });

    testWidgets('renders for rejected status', (tester) async {
      await tester.pumpWidget(_wrap(const StatusChip(status: 'rejected')));
      expect(find.text('REJECTED'), findsOneWidget);
    });

    testWidgets('renders for unknown status without error', (tester) async {
      await tester.pumpWidget(_wrap(const StatusChip(status: 'custom_state')));
      expect(find.text('CUSTOM STATE'), findsOneWidget);
    });
  });
}
