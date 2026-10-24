import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/design/app_tokens.dart';
import 'package:footwear_erp/widgets/app_filter_chip_bar.dart';

void main() {
  testWidgets('filter chips meet the shared minimum touch target', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: AppFilterChipBar(
              labels: ['Active'],
              selected: 'Active',
              onSelected: _ignoreSelection,
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(FilterChip).first).height,
      greaterThanOrEqualTo(AppTokens.minTouchTarget),
    );
  });

  testWidgets('filter chips remain visible with expanded text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: AppFilterChipBar(
                labels: ['نشط'],
                selected: 'نشط',
                onSelected: _ignoreSelection,
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(FilterChip).first).height,
      greaterThanOrEqualTo(AppTokens.minTouchTarget),
    );
  });
}

void _ignoreSelection(String? _) {}
