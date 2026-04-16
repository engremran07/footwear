import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/widgets/stat_card.dart';

void main() {
  testWidgets('StatCard renders title, value, subtitle, and key', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            height: 140,
            child: StatCard(
              title: 'Revenue',
              value: '1200',
              subtitle: 'Today',
              icon: Icons.attach_money,
              staggerIndex: 2,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Revenue'), findsOneWidget);
    expect(find.text('1200'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.byKey(const ValueKey('stat_Revenue_2')), findsOneWidget);
  });

  testWidgets('StatCard invokes onTap when pressed', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            height: 140,
            child: StatCard(
              title: 'Revenue',
              value: '1200',
              icon: Icons.attach_money,
              onTap: () => tapped = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(tapped, isTrue);
  });
}