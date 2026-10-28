import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/utils/formatters.dart';
import 'package:footwear_erp/core/utils/input_formatters.dart';

void main() {
  group('AppInputFormatters.amountFormatter', () {
    String format(String input) {
      final selection = TextSelection.collapsed(offset: input.length);
      return AppInputFormatters.amountFormatter
          .formatEditUpdate(
            TextEditingValue.empty,
            TextEditingValue(text: input, selection: selection),
          )
          .text;
    }

    test('preserves Arabic-Indic digits and Arabic decimal separator', () {
      expect(format('١٢٣٫٤٥'), '١٢٣٫٤٥');
    });

    test('preserves Eastern Arabic digits and grouping separator', () {
      expect(format('۱۲٬۳۴۵٫۶۰'), '۱۲٬۳۴۵٫۶۰');
    });

    test('preserves ASCII amount input and removes letters', () {
      expect(format('PKR 1,200.50'), '1,200.50');
    });

    test('preserves parseable Arabic and Eastern Arabic amounts', () {
      expect(AppFormatters.parseAmountText(format('١٢٣٫٤٥')), 123.45);
      expect(AppFormatters.parseAmountText(format('۱۲٬۳۴۵٫۶۰')), 12345.6);
    });
  });
}
