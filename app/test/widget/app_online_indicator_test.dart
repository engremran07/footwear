import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/constants/app_brand.dart';
import 'package:footwear_erp/widgets/app_online_indicator.dart';

void main() {
  testWidgets('AppOnlineIndicator uses success color when online', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppOnlineIndicator(isOnline: true)),
      ),
    );

    final container = tester.widget<Container>(find.byType(Container));
    final decoration = container.decoration! as BoxDecoration;

    expect(decoration.color, AppBrand.successColor);
    expect(find.bySemanticsLabel('Online'), findsOneWidget);
  });

  testWidgets('AppOnlineIndicator uses error color when offline', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) =>
              const Scaffold(body: AppOnlineIndicator(isOnline: false)),
        ),
      ),
    );

    final container = tester.widget<Container>(find.byType(Container));
    final decoration = container.decoration! as BoxDecoration;
    final context = tester.element(find.byType(AppOnlineIndicator));

    expect(decoration.color, Theme.of(context).colorScheme.error);
    expect(find.bySemanticsLabel('Offline'), findsOneWidget);
  });
}
