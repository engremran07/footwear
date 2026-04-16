import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/l10n/app_locale.dart';
import 'package:footwear_erp/core/utils/pdf_export.dart';

void main() {
  test('buildPdfLedger rejects missing required labels before font loading', () async {
    expect(
      () => buildPdfLedger(
        shopName: 'Shop A',
        companyName: 'Footwear',
        openingBalance: 0,
        transactions: const [],
        labels: const <String, String>{},
        locale: AppLocale.en,
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('Missing required PDF labels'),
        ),
      ),
    );
  });
}