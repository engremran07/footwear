import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/utils/financial_amount_policy.dart';

void main() {
  group('FinancialAmountPolicy', () {
    test('uses the established maximum for SAR and PKR', () {
      expect(FinancialAmountPolicy.maximumForCurrency('SAR'), 999999.99);
      expect(FinancialAmountPolicy.maximumForCurrency('pkr'), 999999.99);
    });

    test('rejects unsupported currencies', () {
      expect(
        () => FinancialAmountPolicy.maximumForCurrency('USD'),
        throwsArgumentError,
      );
    });

    test('accepts only positive finite amounts within the shared cap', () {
      expect(FinancialAmountPolicy.accepts(999999.99, currency: 'SAR'), isTrue);
      expect(FinancialAmountPolicy.accepts(1000000, currency: 'PKR'), isFalse);
      expect(
        FinancialAmountPolicy.accepts(double.infinity, currency: 'SAR'),
        isFalse,
      );
      expect(FinancialAmountPolicy.accepts(0, currency: 'SAR'), isFalse);
    });
  });
}
