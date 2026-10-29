abstract final class FinancialAmountPolicy {
  static const maximumAmount = 999999.99;

  static const Map<String, double> _maximums = {
    'SAR': maximumAmount,
    'PKR': maximumAmount,
  };

  static double maximumForCurrency(String currency) {
    final code = currency.trim().toUpperCase();
    final maximum = _maximums[code];
    if (maximum == null) {
      throw ArgumentError.value(currency, 'currency', 'Unsupported currency');
    }
    return maximum;
  }

  static bool accepts(double amount, {required String currency}) {
    return amount.isFinite &&
        amount > 0 &&
        amount <= maximumForCurrency(currency);
  }
}
