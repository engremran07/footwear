import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/constants/app_brand.dart';
import 'package:footwear_erp/core/l10n/app_locale.dart';
import 'package:footwear_erp/widgets/app_balance_badge.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('balance badge semantics follow EN, AR, and UR locales', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    for (final locale in AppLocale.values) {
      container.read(appLocaleProvider.notifier).set(locale);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: AppBalanceBadge(amount: 1250, currencySymbol: 'PKR'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final expectedLabel = '${trRead('balance', locale)}:';
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label?.startsWith(expectedLabel) == true,
        ),
        findsOneWidget,
      );
    }
  });

  test('balance badge text colors meet AA contrast on their backgrounds', () {
    expect(
      _contrastRatio(AppBrand.successFg, AppBrand.successBg),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrastRatio(AppBrand.errorFg, AppBrand.errorBg),
      greaterThanOrEqualTo(4.5),
    );
  });
}

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
