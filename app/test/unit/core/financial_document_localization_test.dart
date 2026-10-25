import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/l10n/financial_document_localization.dart';

void main() {
  test('cash-receipt title follows the English-Arabic workspace preference', () {
    expect(
      financialDocumentLabel(
        'cash_receipt',
        FinancialDocumentLanguagePair.englishArabic,
      ),
      'Cash Receipt\nسند قبض',
    );
  });

  test('cash-receipt title follows the English-Urdu workspace preference', () {
    expect(
      financialDocumentLabel(
        'cash_receipt',
        FinancialDocumentLanguagePair.englishUrdu,
      ),
      'Cash Receipt\nنقد وصولی کی رسید',
    );
  });

  test('unknown labels preserve the supplied localized fallback', () {
    expect(
      financialDocumentLabel(
        'unknown_document_key',
        FinancialDocumentLanguagePair.englishArabic,
        fallback: 'متاح',
      ),
      'متاح',
    );
  });
}
