import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/widgets/stat_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  const icon = Icons.monetization_on;

  group('StatCard rendering', () {
    testWidgets('displays title and value', (tester) async {
      await tester.pumpWidget(
        _wrap(const StatCard(title: 'Revenue', value: 'SAR 5,000', icon: icon)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Revenue'), findsOneWidget);
      expect(find.text('SAR 5,000'), findsOneWidget);
    });

    testWidgets('displays icon', (tester) async {
      await tester.pumpWidget(
        _wrap(const StatCard(title: 'T', value: 'V', icon: icon)),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(icon), findsOneWidget);
    });

    testWidgets('displays subtitle when provided', (tester) async {
      await tester.pumpWidget(
        _wrap(const StatCard(
          title: 'T',
          value: 'V',
          icon: icon,
          subtitle: 'This month',
        )),
      );
      await tester.pumpAndSettle();
      expect(find.text('This month'), findsOneWidget);
    });

    testWidgets('does not display subtitle widget when not provided',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const StatCard(title: 'T', value: 'V', icon: icon)),
      );
      await tester.pumpAndSettle();
      expect(find.text('This month'), findsNothing);
    });
  });

  group('StatCard interaction', () {
    testWidgets('onTap callback fires when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(StatCard(
          title: 'T',
          value: 'V',
          icon: icon,
          onTap: () => tapped = true,
        )),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(StatCard));
      expect(tapped, isTrue);
    });

    testWidgets('no crash when onTap is null', (tester) async {
      await tester.pumpWidget(
        _wrap(const StatCard(title: 'T', value: 'V', icon: icon)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(StatCard));
      // no exception expected
    });
  });

  group('StatCard with custom color', () {
    testWidgets('renders with provided color', (tester) async {
      await tester.pumpWidget(
        _wrap(const StatCard(
          title: 'T',
          value: 'V',
          icon: icon,
          color: Colors.green,
        )),
      );
      await tester.pumpAndSettle();
      expect(find.byType(StatCard), findsOneWidget);
    });
  });
}
