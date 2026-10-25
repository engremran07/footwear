import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/l10n/financial_document_localization.dart';
import 'package:footwear_erp/core/utils/report_column_naming.dart';

void main() {
  test('column labels use the selected workspace language pair', () {
    expect(
      triCol(
        'cash_receipt',
        pair: FinancialDocumentLanguagePair.englishArabic,
      ),
      'Cash Receipt\nسند قبض',
    );
    expect(
      triCol(
        'cash_receipt',
        pair: FinancialDocumentLanguagePair.englishUrdu,
      ),
      'Cash Receipt\nنقد وصولی کی رسید',
    );
  });

  test('statement labels apply the selected pair to document-level labels', () {
    expect(
      trilingualLabels(
        const {'net_payable': 'Net Payable'},
        pair: FinancialDocumentLanguagePair.englishArabic,
      )['net_payable'],
      'Net Payable\nصافي المستحق',
    );
  });
}
