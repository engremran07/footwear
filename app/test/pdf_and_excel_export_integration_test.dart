import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:typed_data';

import 'package:footwear_erp/core/utils/pdf_export.dart';
import 'package:footwear_erp/core/utils/excel_export.dart';
import 'package:footwear_erp/models/transaction_model.dart';
import 'package:footwear_erp/core/l10n/app_locale.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Long ledger PDF and Excel export produce non-empty bytes', () async {
    // Build a long list of transactions to force multi-page output
    final now = DateTime.now();
    final txs = List<TransactionModel>.generate(180, (i) {
      final date = Timestamp.fromDate(now.subtract(Duration(days: 180 - i)));
      return TransactionModel(
        id: 'tx_$i',
        shopId: 'shop_1',
        shopName: 'Test Shop',
        routeId: 'route_1',
        type: i % 2 == 0 ? TransactionModel.typeCashOut : TransactionModel.typeCashIn,
        amount: (i + 1) * 1.5,
        createdBy: 'user_1',
        createdAt: date,
      );
    });

    final labels = {
      'account_statement': 'Account Statement',
      'report_date': 'Generated On',
      'generated_by': 'By',
      'date': 'Date',
      'description': 'Description',
      'debit': 'Debit',
      'credit': 'Credit',
      'running_balance': 'Balance',
      'cash_in': 'Cash In',
      'cash_out': 'Cash Out',
      'net_payable': 'Final Balance',
      'total_entries': 'Total entries',
      'page': 'Page',
      'opening_balance': 'Opening Balance',
      'duration': 'Duration',
    };

    // Generate PDF bytes
    final pdfBytes = await buildPdfLedger(
      shopName: 'Test Shop',
      companyName: 'ACME Ltd',
      generatedBy: 'tester',
      openingBalance: 0.0,
      transactions: txs,
      labels: labels,
      locale: AppLocale.en,
    );

    expect(pdfBytes, isA<Uint8List>());
    expect(pdfBytes.lengthInBytes, greaterThan(1000));

    // Generate Excel bytes
    const headers = ['Date', 'Description', 'Debit', 'Credit', 'Balance'];
    final rows = txs.map((t) => [
      t.createdAt.toDate().toIso8601String(),
      t.description ?? '',
      t.isCashOut ? t.amount : 0,
      t.isCashIn ? t.amount : 0,
      t.amount,
    ]).toList();
    final excel = buildStyledExcelBytes(sheetName: 'Ledger', headers: headers, rows: rows);
    expect(excel, isNotNull);
    expect(excel!.length, greaterThan(1000));
  }, timeout: const Timeout.factor(4));
}
