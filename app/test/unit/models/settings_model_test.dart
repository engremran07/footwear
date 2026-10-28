import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/l10n/financial_document_localization.dart';
import 'package:footwear_erp/models/settings_model.dart';

void main() {
  group('SettingsModel.fromJson', () {
    final ts = Timestamp.fromMillisecondsSinceEpoch(0);
    final baseJson = <String, dynamic>{
      'tenant_id': 'workspace-a',
      'company_name': 'Test Co',
      'currency': 'SAR',
      'pairs_per_carton': 12,
      'logo_base64': 'aGVsbG8=', // base64('hello')
      'allow_non_stock_invoices': false,
      'invoice_header': {
        'name_en': 'Test Company',
        'name_ar': 'شركة الاختبار',
        'phone': '+966500000000',
        'receipt_phone_2': '+966511111111',
        'receipt_phone_3': '+966522222222',
        'document_language_pair': 'english_urdu',
        'template': 'classic',
        'accent_color': '#345678',
        'visible_fields': ['phone', 'email'],
      },
      'updated_at': ts,
    };

    test('parses all fields correctly', () {
      final m = SettingsModel.fromJson(baseJson);
      expect(m.tenantId, 'workspace-a');
      expect(m.companyName, 'Test Company');
      expect(m.currency, 'SAR');
      expect(m.pairsPerCarton, 12);
      expect(m.logoBase64, 'aGVsbG8=');
      expect(m.logoBytes, isNotNull);
      expect(m.allowNonStockInvoices, isFalse);
      expect(m.invoiceHeader.nameEn, 'Test Company');
      expect(m.invoiceHeader.nameAr, 'شركة الاختبار');
      expect(m.invoiceHeader.phone, '+966500000000');
      expect(m.invoiceHeader.receiptPhone2, '+966511111111');
      expect(m.invoiceHeader.receiptPhone3, '+966522222222');
      expect(
        m.invoiceHeader.documentLanguagePair,
        FinancialDocumentLanguagePair.englishUrdu,
      );
      expect(m.invoiceHeader.visibleFields, containsAll(['phone', 'email']));
    });

    test('missing fields use defaults', () {
      final m = SettingsModel.fromJson({});
      expect(m.tenantId, '__global__');
      expect(m.companyName, 'My Business');
      expect(m.currency, 'SAR');
      expect(m.pairsPerCarton, 12);
      expect(m.logoBase64, isNull);
      expect(m.logoBytes, isNull);
      expect(m.allowNonStockInvoices, isFalse);
      expect(m.invoiceHeader.nameEn, '');
      expect(m.invoiceHeader.receiptPhone2, '');
      expect(m.invoiceHeader.receiptPhone3, '');
      expect(
        m.invoiceHeader.documentLanguagePair,
        FinancialDocumentLanguagePair.englishArabic,
      );
    });

    test('reads and preserves the workspace non-stock invoice setting', () {
      final settings = SettingsModel.fromJson({
        ...baseJson,
        'allow_non_stock_invoices': true,
      });

      expect(settings.allowNonStockInvoices, isTrue);
      expect(settings.toJson()['allow_non_stock_invoices'], isTrue);
    });

    test('invoice header snapshot includes tenant branding and logo', () {
      final settings = SettingsModel.fromJson(baseJson);
      final snapshot = settings.invoiceHeaderSnapshot;

      expect(snapshot['name_en'], 'Test Company');
      expect(snapshot['name_ar'], 'شركة الاختبار');
      expect(snapshot['document_language_pair'], 'english_urdu');
      expect(snapshot['receipt_phone_2'], '+966511111111');
      expect(snapshot['receipt_phone_3'], '+966522222222');
      expect(snapshot.containsKey('company_name'), isFalse);
      expect(snapshot['logo_base64'], 'aGVsbG8=');
    });

    test('migrates legacy company name into an otherwise empty header', () {
      final settings = SettingsModel.fromJson({
        'company_name': 'Legacy Workspace',
        'currency': 'SAR',
        'pairs_per_carton': 12,
      });

      expect(settings.invoiceHeader.nameEn, 'Legacy Workspace');
      expect(settings.toJson().containsKey('company_name'), isFalse);
    });

    test('ignores the retired reprint-header toggle', () {
      final header = InvoiceHeaderConfig.fromJson({
        'name_en': 'Saved Name',
        'use_latest_header_on_reprint': false,
      });

      expect(header.nameEn, 'Saved Name');
      expect(header.toJson(), isNot(contains('use_latest_header_on_reprint')));
    });
  });

  group('SettingsModel.toJson', () {
    test('round-trips through fromJson/toJson', () {
      final ts = Timestamp.fromMillisecondsSinceEpoch(1000);
      final original = SettingsModel(
        currency: 'PKR',
        pairsPerCarton: 20,
        allowNonStockInvoices: false,
        invoiceHeader: const InvoiceHeaderConfig(
          nameEn: 'Workshop',
          nameAr: 'ورشة',
          documentLanguagePair: FinancialDocumentLanguagePair.englishUrdu,
          phone: '+966511111111',
          receiptPhone2: '+966522222222',
          receiptPhone3: '+966533333333',
          visibleFields: {'phone', 'tax_number'},
        ),
        updatedAt: ts,
      );
      final json = original.toJson();
      final restored = SettingsModel.fromJson(json);
      expect(restored.companyName, original.companyName);
      expect(json.containsKey('company_name'), isFalse);
      expect(restored.currency, original.currency);
      expect(restored.pairsPerCarton, original.pairsPerCarton);
      expect(restored.allowNonStockInvoices, isFalse);
      expect(restored.invoiceHeader.nameEn, 'Workshop');
      expect(restored.invoiceHeader.nameAr, 'ورشة');
      expect(
        restored.invoiceHeader.documentLanguagePair,
        FinancialDocumentLanguagePair.englishUrdu,
      );
      expect(restored.invoiceHeader.receiptPhone2, '+966522222222');
      expect(restored.invoiceHeader.receiptPhone3, '+966533333333');
      expect(restored.invoiceHeader.visibleFields, {'phone', 'tax_number'});
    });

    test('copyWith can update and clear optional logo field', () {
      final ts = Timestamp.fromMillisecondsSinceEpoch(1000);
      final original = SettingsModel(
        currency: 'PKR',
        pairsPerCarton: 12,
        invoiceHeader: const InvoiceHeaderConfig(nameEn: 'My Shop'),
        logoBase64: 'aGVsbG8=',
        updatedAt: ts,
      );

      final updated = original.copyWith(currency: 'SAR', clearLogoBase64: true);
      expect(updated.companyName, original.companyName);
      expect(updated.currency, 'SAR');
      expect(updated.logoBase64, isNull);
    });

    test('equality includes business fields', () {
      final ts = Timestamp.fromMillisecondsSinceEpoch(1000);
      final left = SettingsModel(
        currency: 'PKR',
        pairsPerCarton: 12,
        invoiceHeader: const InvoiceHeaderConfig(nameEn: 'My Shop'),
        updatedAt: ts,
      );
      final right = SettingsModel(
        currency: 'PKR',
        pairsPerCarton: 12,
        invoiceHeader: const InvoiceHeaderConfig(nameEn: 'My Shop'),
        updatedAt: ts,
      );

      expect(left, right);
      expect(left.hashCode, right.hashCode);
    });

    test('asserts when pairsPerCarton is not positive', () {
      expect(
        () => SettingsModel(
          currency: 'PKR',
          pairsPerCarton: 0,
          updatedAt: Timestamp.fromMillisecondsSinceEpoch(0),
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
