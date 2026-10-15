import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/l10n/app_locale.dart';
import 'package:footwear_erp/core/utils/pdf_export.dart';
import 'package:footwear_erp/models/invoice_model.dart';
import 'package:footwear_erp/models/settings_model.dart';
import 'package:footwear_erp/models/transaction_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    'generateInvoicePdf renders a receipt using its saved header snapshot',
    () async {
      final now = Timestamp.fromMillisecondsSinceEpoch(0);
      final invoice = InvoiceModel(
        id: 'receipt-1',
        invoiceNumber: 'REC-2026-0001',
        type: InvoiceModel.typeCashReceipt,
        fulfillmentMode: 'none',
        shopId: 'shop-1',
        shopName: 'Sample Shop',
        subtotal: 0,
        total: 125,
        amountReceived: 125,
        outstandingAmount: 0,
        status: InvoiceModel.statusPaid,
        paymentMethod: 'bank_transfer',
        paymentReference: 'BANK-123',
        shopBalanceBefore: 200,
        shopBalanceAfter: 75,
        createdBy: 'seller-1',
        createdAt: now,
        updatedAt: now,
        currency: 'SAR',
        headerSnapshot: const {
          'name_en': 'Configured Workspace',
          'name_ar': 'مساحة العمل',
          'company_name': 'Configured Workspace',
          'template': 'centered',
          'accent_color': '#315C4C',
          'visible_fields': ['phone'],
          'phone': '+966500000000',
        },
      );

      final bytes = await generateInvoicePdf(
        invoice: invoice,
        companyName: 'Changed Workspace Name',
        currency: 'SAR',
        locale: AppLocale.en,
        header: const InvoiceHeaderConfig(nameEn: 'Current Settings Name'),
      );

      expect(invoice.isCashReceipt, isTrue);
      expect(bytes, isNotEmpty);
    },
  );

  test('generateInvoicePdf renders non-stock catalog lines', () async {
    final now = Timestamp.fromMillisecondsSinceEpoch(0);
    final invoice = InvoiceModel(
      id: 'non-stock-1',
      invoiceNumber: 'INV-2026-0002',
      type: InvoiceModel.typeSale,
      fulfillmentMode: InvoiceModel.fulfillmentNonStock,
      shopId: 'shop-1',
      shopName: 'Sample Shop',
      items: const [
        TransactionItem(
          variantId: 'variant-1',
          sku: '',
          productName: 'Model One · Size 42',
          size: '',
          color: '',
          qty: 2,
          unitPrice: 75,
          subtotal: 150,
        ),
      ],
      subtotal: 150,
      total: 150,
      amountReceived: 0,
      outstandingAmount: 150,
      status: InvoiceModel.statusIssued,
      createdBy: 'seller-1',
      createdAt: now,
      updatedAt: now,
      currency: 'SAR',
      headerSnapshot: const {
        'name_en': 'Configured Workspace',
        'name_ar': 'مساحة العمل',
        'company_name': 'Configured Workspace',
        'visible_fields': [],
      },
    );

    final bytes = await generateInvoicePdf(
      invoice: invoice,
      companyName: 'Changed Workspace Name',
      currency: 'SAR',
      locale: AppLocale.en,
    );

    expect(invoice.isNonStockSale, isTrue);
    expect(bytes, isNotEmpty);
  });

  test('generateInvoicePdf paginates invoices with long item lists', () async {
    final now = Timestamp.fromMillisecondsSinceEpoch(0);
    final items = List.generate(
      80,
      (index) => TransactionItem(
        variantId: 'variant-$index',
        sku: 'SKU-$index',
        productName: 'Extended catalog model ${index + 1}',
        size: '42',
        color: 'Black',
        qty: 1,
        unitPrice: 10,
        subtotal: 10,
      ),
    );
    final invoice = InvoiceModel(
      id: 'long-invoice',
      invoiceNumber: 'INV-2026-0080',
      type: InvoiceModel.typeSale,
      shopId: 'shop-1',
      shopName: 'Sample Shop',
      items: items,
      subtotal: 800,
      total: 800,
      status: InvoiceModel.statusIssued,
      createdBy: 'seller-1',
      createdAt: now,
      updatedAt: now,
    );

    final bytes = await generateInvoicePdf(
      invoice: invoice,
      companyName: 'Workspace',
    );

    final pageCount = RegExp(
      r'/Count\s+(\d+)',
    ).firstMatch(latin1.decode(bytes, allowInvalid: true));
    expect(pageCount, isNotNull);
    expect(int.parse(pageCount!.group(1)!), greaterThan(1));
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
