import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:footwear_erp/core/l10n/app_locale.dart';
import 'package:footwear_erp/core/l10n/financial_document_localization.dart';
import 'package:footwear_erp/core/utils/pdf_export.dart';
import 'package:footwear_erp/models/invoice_model.dart';
import 'package:footwear_erp/models/settings_model.dart';
import 'package:footwear_erp/models/transaction_model.dart';

final _testLogoBase64 = base64Encode(_createTestLogoBytes());
final _testLogoBytes = base64Decode(_testLogoBase64);

Uint8List _createTestLogoBytes() {
  final logo = img.Image(width: 2, height: 2, numChannels: 4);
  img.fill(logo, color: img.ColorRgba8(24, 82, 146, 255));
  logo.setPixelRgba(0, 0, 24, 82, 146, 0);
  return Uint8List.fromList(img.encodePng(logo));
}

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

  test('PDF text direction follows the first script in mixed values', () {
    expect(
      pdfTextDirectionFor(
        'Classic Shoe حذاء كلاسيكي جوتا',
        pw.TextDirection.rtl,
      ),
      pw.TextDirection.ltr,
    );
    expect(
      pdfTextDirectionFor(
        'Invoice INV-2026-1 موديل حذاء فروخت',
        pw.TextDirection.rtl,
      ),
      pw.TextDirection.ltr,
    );
    expect(
      pdfTextDirectionFor('حذاء كلاسيكي Classic Shoe', pw.TextDirection.ltr),
      pw.TextDirection.rtl,
    );
    expect(
      pdfTextDirectionFor('أسود Black کالا', pw.TextDirection.ltr),
      pw.TextDirection.rtl,
    );
  });

  test('numeric-only date strings use LTR direction in RTL documents', () {
    expect(
      pdfTextDirectionFor('23/08/2026', pw.TextDirection.rtl),
      pw.TextDirection.ltr,
    );
    expect(
      pdfTextDirectionFor('٢٣/٠٨/٢٠٢٦', pw.TextDirection.rtl),
      pw.TextDirection.ltr,
    );
    expect(
      pdfTextDirectionFor('— •', pw.TextDirection.rtl),
      pw.TextDirection.rtl,
    );
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
    expect(summary.totalCredit, 52);
    expect(summary.closingBalance, 68);
  });

  test(
    'current workspace header overrides the saved invoice header on print',
    () {
      final now = Timestamp.fromMillisecondsSinceEpoch(0);
      final invoice = InvoiceModel(
        id: 'header-reprint',
        invoiceNumber: 'INV-HEADER-1',
        type: InvoiceModel.typeSale,
        shopId: 'shop-1',
        shopName: 'Sample Shop',
        subtotal: 0,
        total: 0,
        status: InvoiceModel.statusIssued,
        createdBy: 'seller-1',
        createdAt: now,
        updatedAt: now,
        headerSnapshot: {
          'name_en': 'Saved Workspace Header',
          'visible_fields': [],
        },
      );

      const current = InvoiceHeaderConfig(nameEn: 'Current Workspace Header');

      expect(
        resolveInvoiceHeaderForPrint(
          invoice: invoice,
          currentHeader: current,
        ).nameEn,
        'Current Workspace Header',
      );
      expect(
        resolveInvoiceHeaderForPrint(
          invoice: invoice,
          currentHeader: null,
        ).nameEn,
        'Saved Workspace Header',
      );
    },
  );

  test('paginateItems splits a list into page-sized chunks', () {
    final pages = paginateItems<int>(List.generate(60, (i) => i), 30);

    expect(pages, hasLength(2));
    expect(pages.first, hasLength(30));
    expect(pages.last, hasLength(30));
    expect(pages.last.first, 30);
  });

  test(
    'cash receipt reference layout stays A5 and one page in Arabic and Urdu',
    () async {
      final now = Timestamp.fromMillisecondsSinceEpoch(0);
      final invoice = InvoiceModel(
        id: 'receipt-1',
        invoiceNumber: 'REC-2026-0001',
        type: InvoiceModel.typeCashReceipt,
        fulfillmentMode: 'none',
        shopId: 'shop-1',
        shopName: 'Sample Shop · محل مثال',
        subtotal: 0,
        total: 125,
        amountReceived: 125,
        outstandingAmount: 0,
        status: InvoiceModel.statusPaid,
        paymentMethod: 'bank_transfer',
        paymentReference: List.filled(120, 'BANK-123 ').join(),
        shopBalanceBefore: 200,
        shopBalanceAfter: 75,
        cashReceiptSequence: 1,
        linkedInvoiceId: 'INV-2026-0001',
        sellerName: 'Workspace Seller',
        notes: 'Old account collection · صافي المستحق · یہ اردو ٹیسٹ ہے؛ ادائیگی؛ ٹ ڈ ڑ ں ھ ے',
        createdBy: 'seller-1',
        createdAt: now,
        updatedAt: now,
        currency: 'SAR',
        headerSnapshot: {
          'name_en': 'Configured Workspace',
          'name_ar': 'مساحة العمل',
          'company_name': 'Configured Workspace',
          'logo_base64': _testLogoBase64,
          'template': 'centered',
          'accent_color': '#315C4C',
          'visible_fields': ['phone'],
          'phone': '+966500000000',
          'receipt_phone_2': '+966511111111',
          'receipt_phone_3': '+966522222222',
        },
      );

      const currentHeader = InvoiceHeaderConfig(
        nameEn:
            'Current Settings Name for a Long Distribution Workspace Header',
        nameAr: 'اسم مساحة العمل',
        phone: '+966500000000',
        receiptPhone2: '+966511111111',
        receiptPhone3: '+966522222222',
      );
      final bytes = await generateInvoicePdf(
        invoice: invoice,
        companyName: 'Changed Workspace Name',
        currency: 'SAR',
        locale: AppLocale.ar,
        header: currentHeader,
      );

      expect(invoice.isCashReceipt, isTrue);
      void expectSinglePageA5WithResources(Uint8List generatedBytes) {
        final pdf = latin1.decode(generatedBytes, allowInvalid: true);
        final pageCount = RegExp(r'/Count\s+(\d+)').firstMatch(pdf);
        expect(pageCount, isNotNull);
        expect(int.parse(pageCount!.group(1)!), 1);
        final mediaBox = RegExp(r'/MediaBox\[0 0 ([\d.]+) ([\d.]+)\]')
            .firstMatch(pdf);
        expect(mediaBox, isNotNull);
        expect(
          double.parse(mediaBox!.group(1)!),
          closeTo(PdfPageFormat.a5.width, 0.1),
        );
        expect(
          double.parse(mediaBox.group(2)!),
          closeTo(PdfPageFormat.a5.height, 0.1),
        );
        expect(pdf, contains('/Subtype/Image'));
        expect(pdf, contains('/SMask'));
        expect(pdf, contains('NotoSansArabic'));
        expect(pdf, contains('/FontFile2'));
      }

      expectSinglePageA5WithResources(bytes);
      final urduBytes = await generateInvoicePdf(
        invoice: invoice,
        companyName: 'Changed Workspace Name',
        currency: 'SAR',
        locale: AppLocale.ur,
        header: currentHeader.copyWith(
          documentLanguagePair: FinancialDocumentLanguagePair.englishUrdu,
          nameUr: 'ورک اسپیس کمپنی',
        ),
      );
      expectSinglePageA5WithResources(urduBytes);
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
      headerSnapshot: {
        'name_en': 'Configured Workspace',
        'name_ar': 'مساحة العمل',
        'company_name': 'Configured Workspace',
        'logo_base64': _testLogoBase64,
      },
    );

    final bytes = await generateInvoicePdf(
      invoice: invoice,
      companyName: 'Changed Workspace Name',
      currency: 'SAR',
      locale: AppLocale.en,
      header: const InvoiceHeaderConfig(nameEn: 'Current Workspace Name'),
    );

    expect(invoice.isNonStockSale, isTrue);
    expect(bytes, isNotEmpty);
    expect(
      latin1.decode(bytes, allowInvalid: true),
      contains('/Subtype/Image'),
    );
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

    final pageCount = RegExp(r'/Count\s+(\d+)')
        .firstMatch(latin1.decode(bytes, allowInvalid: true));
    expect(pageCount, isNotNull);
    expect(int.parse(pageCount!.group(1)!), greaterThan(1));
  });

  test('PDF test builds enable the Arabic shaping algorithm', () {
    expect(const bool.fromEnvironment('use_arabic'), isTrue);
  });

  test('Arabic PDF generation fails closed when shaping is disabled', () async {
    final pdf = buildPdfTable(
      title: 'تقرير الحساب',
      headers: const ['المتجر'],
      rows: const [
        ['دکان'],
      ],
      locale: AppLocale.ar,
    );

    if (const bool.fromEnvironment('use_arabic')) {
      expect(await pdf, isNotEmpty);
    } else {
      await expectLater(
        pdf,
        throwsA(
          isA<PdfExportConfigurationException>().having(
            (error) => error.code,
            'code',
            'pdf_arabic_shaping_disabled',
          ),
        ),
      );
    }
  });

  test('standalone table logo uses the shared centered brand header', () async {
    final bytes = await buildPdfTable(
      title: 'Sales report',
      headers: const ['Shop'],
      rows: const [
        ['Sample Shop'],
      ],
      companyName: 'Workspace Name',
      locale: AppLocale.en,
      logoBytes: _testLogoBytes,
    );
    final pdf = latin1.decode(bytes, allowInvalid: true);
    expect(pdf, contains('/Subtype/Image'));

    final hiddenLogoBytes = await buildPdfTable(
      title: 'Sales report',
      headers: const ['Shop'],
      rows: const [
        ['Sample Shop'],
      ],
      companyName: 'Workspace Name',
      locale: AppLocale.en,
      logoBytes: _testLogoBytes,
      header: const InvoiceHeaderConfig(
        nameEn: 'Workspace Name',
        visibleFields: {},
      ),
    );
    expect(
      latin1.decode(hiddenLogoBytes, allowInvalid: true),
      isNot(contains('/Subtype/Image')),
    );
  });

  test(
    'shared PDF header preserves logo alpha and opaque image treatment',
    () async {
      final transparentLogo = img.Image(width: 4, height: 4, numChannels: 4);
      img.fill(transparentLogo, color: img.ColorRgba8(0, 120, 200, 255));
      transparentLogo.setPixelRgba(0, 0, 0, 0, 0, 0);
      final transparentPdf = await buildPdfTable(
        title: 'Logo report',
        headers: const ['Shop'],
        rows: const [
          ['Sample Shop'],
        ],
        companyName: 'Workspace Name',
        locale: AppLocale.en,
        logoBytes: Uint8List.fromList(img.encodePng(transparentLogo)),
        header: const InvoiceHeaderConfig(
          nameEn: 'Workspace Name',
          visibleFields: {'logo'},
        ),
      );
      final transparentPdfText = latin1.decode(
        transparentPdf,
        allowInvalid: true,
      );
      expect(transparentPdfText, contains('/Subtype/Image'));
      expect(transparentPdfText, contains('/SMask'));

      final opaqueLogo = img.Image(width: 4, height: 4, numChannels: 3);
      img.fill(opaqueLogo, color: img.ColorRgb8(24, 82, 146));
      final opaquePdf = await buildPdfTable(
        title: 'Logo report',
        headers: const ['Shop'],
        rows: const [
          ['Sample Shop'],
        ],
        companyName: 'Workspace Name',
        locale: AppLocale.en,
        logoBytes: Uint8List.fromList(img.encodePng(opaqueLogo)),
        header: const InvoiceHeaderConfig(
          nameEn: 'Workspace Name',
          visibleFields: {'logo'},
        ),
      );
      final opaquePdfText = latin1.decode(opaquePdf, allowInvalid: true);
      expect(opaquePdfText, contains('/Subtype/Image'));

      final hiddenLogoPdf = await buildPdfTable(
        title: 'Logo report',
        headers: const ['Shop'],
        rows: const [
          ['Sample Shop'],
        ],
        companyName: 'Workspace Name',
        locale: AppLocale.en,
        logoBytes: Uint8List.fromList(img.encodePng(transparentLogo)),
        header: const InvoiceHeaderConfig(
          nameEn: 'Workspace Name',
          visibleFields: {},
        ),
      );
      expect(
        latin1.decode(hiddenLogoPdf, allowInvalid: true),
        isNot(contains('/Subtype/Image')),
      );
    },
  );

  test('Arabic and Urdu text builds across shared PDF report paths', () async {
    final date = Timestamp.fromDate(DateTime(2026, 10, 22));
    const arabic = 'تقرير الحساب؛ صافي المستحق؛ يجري';
    const urdu = 'یہ اردو رپورٹ ٹیسٹ ہے؛ ادائیگی؛ ٹ ڈ ڑ ں ھ ے';
    Map<String, String> labelsFor(
      AppLocale locale,
      List<String> keys, {
      FinancialDocumentLanguagePair? pair,
    }) => {
      for (final key in keys)
        key: pair == null
            ? trRead(key, locale)
            : financialDocumentLabel(key, pair, fallback: trRead(key, locale)),
    };
    void expectPdf(List<int> bytes) {
      expect(bytes, isNotEmpty);
      final pdf = latin1.decode(bytes, allowInvalid: true);
      expect(pdf.substring(0, 5), '%PDF-');
      expect(pdf, contains('NotoSansArabic'));
      expect(pdf, contains('/FontFile2'));
    }

    final tablePdf = await buildPdfTable(
      title: arabic,
      headers: const ['المتجر', 'دکان'],
      rows: [
        [arabic, urdu],
      ],
      locale: AppLocale.ar,
    );
    expectPdf(tablePdf);

    final transaction = TransactionModel(
      id: 'rtl-transaction',
      shopId: 'rtl-shop',
      shopName: urdu,
      routeId: 'route-rtl',
      type: TransactionModel.typeCashOut,
      amount: 25,
      createdBy: 'seller-rtl',
      createdAt: date,
      description: 'Invoice INV-RTL-1 $arabic — $urdu',
    );
    const ledgerKeys = [
      'account_statement',
      'report_date',
      'generated_by',
      'date',
      'description',
      'debit',
      'credit',
      'running_balance',
      'net_payable',
      'total_entries',
      'page',
      'opening_balance',
      'duration',
    ];
    final ledgerPdf = await buildPdfLedger(
      shopName: urdu,
      companyName: arabic,
      openingBalance: 10,
      transactions: [transaction],
      dateFrom: DateTime(2026, 8, 23),
      dateTo: DateTime(2026, 10, 25),
      labels: labelsFor(
        AppLocale.ur,
        ledgerKeys,
        pair: FinancialDocumentLanguagePair.englishUrdu,
      ),
      locale: AppLocale.ur,
      logoBytes: _testLogoBytes,
      header: const InvoiceHeaderConfig(
        nameEn: 'Footwear',
        nameAr: 'شركة الأحذية',
        phone: '+966500000000',
        documentLanguagePair: FinancialDocumentLanguagePair.englishUrdu,
      ),
    );
    expectPdf(ledgerPdf);
    final arabicLedgerPdf = await buildPdfLedger(
      shopName: arabic,
      companyName: 'Footwear',
      openingBalance: 10,
      transactions: [transaction],
      dateFrom: DateTime(2026, 8, 23),
      dateTo: DateTime(2026, 10, 25),
      labels: labelsFor(
        AppLocale.ar,
        ledgerKeys,
        pair: FinancialDocumentLanguagePair.englishArabic,
      ),
      locale: AppLocale.ar,
      header: const InvoiceHeaderConfig(
        nameEn: 'Footwear',
        nameAr: 'شركة الأحذية',
      ),
    );
    expectPdf(arabicLedgerPdf);
    expect(
      latin1.decode(ledgerPdf, allowInvalid: true),
      contains('/Subtype/Image'),
    );
    expect(
      RegExp(r'/Count\s+(\d+)')
          .firstMatch(latin1.decode(ledgerPdf, allowInvalid: true))
          ?.group(1),
      '1',
    );

    const sellerReportKeys = [
      'seller_report',
      'report_date',
      'seller',
      'route',
      'inventory',
      'stock_received',
      'stock_sold',
      'stock_remaining',
      'shops',
      'shop',
      'revenue',
      'outstanding',
      'total',
      'pairs',
    ];
    final sellerPdf = await buildPdfSellerReport(
      sellerName: urdu,
      sellerPhone: '+923001234567',
      routeName: arabic,
      shops: [
        const SellerReportShop(
          name: urdu,
          totalPairsSold: 12,
          totalRevenue: 50,
          outstandingBalance: 25,
          currency: 'SAR',
        ),
        const SellerReportShop(
          name: arabic,
          totalPairsSold: 6,
          totalRevenue: 75,
          outstandingBalance: 10,
          currency: 'PKR',
        ),
      ],
      stockReceived: 24,
      stockSold: 12,
      stockRemaining: 12,
      labels: labelsFor(AppLocale.ar, sellerReportKeys),
      locale: AppLocale.ar,
      companyName: arabic,
      logoBytes: _testLogoBytes,
      header: const InvoiceHeaderConfig(
        nameEn: 'Footwear',
        nameAr: 'شركة الأحذية',
      ),
    );
    expectPdf(sellerPdf);
    expect(
      latin1.decode(sellerPdf, allowInvalid: true),
      contains('/Subtype/Image'),
    );

    final invoicePdf = await generateInvoicePdf(
      invoice: InvoiceModel(
        id: 'rtl-invoice',
        invoiceNumber: 'INV-RTL-1',
        type: InvoiceModel.typeSale,
        shopId: 'rtl-shop',
        shopName: urdu,
        items: [
          const TransactionItem(
            variantId: 'rtl-variant',
            sku: 'RTL-1',
            productName: 'Classic Shoe — $arabic — $urdu',
            size: '42',
            color: 'Black — أسود — کالا',
            qty: 1,
            unitPrice: 25,
            subtotal: 25,
          ),
        ],
        subtotal: 25,
        total: 25,
        amountReceived: 0,
        outstandingAmount: 25,
        status: InvoiceModel.statusIssued,
        createdBy: 'seller-rtl',
        createdAt: date,
        updatedAt: date,
        headerSnapshot: const {
          'name_en': 'Footwear',
          'name_ar': 'شركة الأحذية',
          'name_ur': 'جوتوں کی کمپنی',
          'company_name': 'Footwear',
          'visible_fields': [],
        },
      ),
      companyName: 'Footwear',
      locale: AppLocale.ur,
    );
    expectPdf(invoicePdf);

    const multiShopKeys = [
      'report_date',
      'generated_by',
      'total_entries',
      'net_payable',
      'name',
      'route',
      'debit',
      'credit',
      'running_balance',
      'date',
      'description',
      'page',
      'opening_balance',
    ];
    final multiShopPdf = await buildPdfMultiShopLedger(
      title: arabic,
      subtitle: urdu,
      companyName: arabic,
      generatedBy: urdu,
      sections: [
        MultiShopLedgerSection(
          shopName: urdu,
          routeLabel: arabic,
          openingBalance: 10,
          transactions: [transaction],
        ),
      ],
      labels: labelsFor(
        AppLocale.ur,
        multiShopKeys,
        pair: FinancialDocumentLanguagePair.englishUrdu,
      ),
      locale: AppLocale.ur,
      logoBytes: _testLogoBytes,
      header: const InvoiceHeaderConfig(
        nameEn: 'Footwear',
        nameUr: 'جوتوں کی کمپنی',
        documentLanguagePair: FinancialDocumentLanguagePair.englishUrdu,
      ),
    );
    expectPdf(multiShopPdf);
    expect(
      latin1.decode(multiShopPdf, allowInvalid: true),
      contains('/Subtype/Image'),
    );
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
