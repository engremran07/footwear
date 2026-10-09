import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/l10n/app_locale.dart';
import 'package:footwear_erp/core/utils/pdf_export.dart';
import 'package:footwear_erp/models/transaction_model.dart';

void main() {
  test('pdfCurrencyLabel preserves each supported route currency', () {
    expect(pdfCurrencyLabel(AppLocale.en, 'SAR'), 'SAR');
    expect(pdfCurrencyLabel(AppLocale.en, 'PKR'), 'PKR');
    expect(pdfCurrencyLabel(AppLocale.ar, 'SAR'), 'ريال');
    expect(pdfCurrencyLabel(AppLocale.ar, 'PKR'), 'روبية');
    expect(pdfCurrencyLabel(AppLocale.ur, 'SAR'), 'ریال');
    expect(pdfCurrencyLabel(AppLocale.ur, 'PKR'), 'روپے');
  });

  test('calculateLedgerSummary follows authoritative balance impacts', () {
    final now = Timestamp.now();
    TransactionModel transaction(String id, String type, double amount) =>
        TransactionModel(
          id: id,
          shopId: 'shop-1',
          shopName: 'Shop',
          routeId: 'route-1',
          type: type,
          amount: amount,
          createdBy: 'user-1',
          createdAt: now,
        );

    final summary = calculateLedgerSummary(
      openingBalance: 20,
      transactions: [
        transaction('sale', TransactionModel.typeCashOut, 100),
        transaction('cash', TransactionModel.typeCashIn, 30),
        transaction('return', TransactionModel.typeReturn, 10),
        transaction('payment', TransactionModel.typePayment, 5),
        transaction('write-off', TransactionModel.typeWriteOff, 7),
        transaction('legacy', 'legacy_type', 99),
      ],
    );

    expect(summary.totalDebit, 100);
    expect(summary.totalCredit, 45);
    expect(summary.closingBalance, 75);
  });

  test('paginateItems splits a list into page-sized chunks', () {
    final pages = paginateItems<int>(List.generate(60, (i) => i), 30);

    expect(pages, hasLength(2));
    expect(pages.first, hasLength(30));
    expect(pages.last, hasLength(30));
    expect(pages.last.first, 30);
  });

  test(
    'buildPdfLedger rejects missing required labels before font loading',
    () async {
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
    },
  );
}
