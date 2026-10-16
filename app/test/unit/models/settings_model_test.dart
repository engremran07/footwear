import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/settings_model.dart';

void main() {
  group('SettingsModel.fromJson', () {
    final ts = Timestamp.fromMillisecondsSinceEpoch(0);
    final baseJson = <String, dynamic>{
      'tenant_id': 'jbm-impex',
      'company_name': 'Test Co',
      'currency': 'SAR',
      'pairs_per_carton': 12,
      'logo_base64': 'aGVsbG8=', // base64('hello')
      'allow_non_stock_invoices': false,
      'invoice_header': {
        'name_en': 'Test Company',
        'name_ar': 'شركة الاختبار',
        'phone': '+966500000000',
        'template': 'classic',
        'accent_color': '#345678',
        'visible_fields': ['phone', 'email'],
      },
      'updated_at': ts,
    };

    test('parses all fields correctly', () {
      final m = SettingsModel.fromJson(baseJson);
      expect(m.tenantId, 'jbm-impex');
      expect(m.companyName, 'Test Co');
      expect(m.currency, 'SAR');
      expect(m.pairsPerCarton, 12);
      expect(m.logoBase64, 'aGVsbG8=');
      expect(m.logoBytes, isNotNull);
      expect(m.allowNonStockInvoices, isFalse);
      expect(m.invoiceHeader.nameEn, 'Test Company');
      expect(m.invoiceHeader.nameAr, 'شركة الاختبار');
      expect(m.invoiceHeader.phone, '+966500000000');
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
    });

    test('invoice header snapshot includes tenant branding and logo', () {
      final settings = SettingsModel.fromJson(baseJson);
      final snapshot = settings.invoiceHeaderSnapshot;

      expect(snapshot['name_en'], 'Test Company');
      expect(snapshot['name_ar'], 'شركة الاختبار');
      expect(snapshot['company_name'], 'Test Co');
      expect(snapshot['logo_base64'], 'aGVsbG8=');
    });
  });

  group('SettingsModel.toJson', () {
    test('round-trips through fromJson/toJson', () {
      final ts = Timestamp.fromMillisecondsSinceEpoch(1000);
      final original = SettingsModel(
        companyName: 'My Shop',
        currency: 'PKR',
        pairsPerCarton: 20,
        allowNonStockInvoices: false,
        invoiceHeader: const InvoiceHeaderConfig(
          nameEn: 'Workshop',
          nameAr: 'ورشة',
          phone: '+966511111111',
          visibleFields: {'phone', 'tax_number'},
        ),
        updatedAt: ts,
      );
      final json = original.toJson();
      final restored = SettingsModel.fromJson(json);
      expect(restored.companyName, original.companyName);
      expect(restored.currency, original.currency);
      expect(restored.pairsPerCarton, original.pairsPerCarton);
      expect(restored.allowNonStockInvoices, isFalse);
      expect(restored.invoiceHeader.nameEn, 'Workshop');
      expect(restored.invoiceHeader.nameAr, 'ورشة');
      expect(restored.invoiceHeader.visibleFields, {'phone', 'tax_number'});
    });

    test('copyWith can update and clear optional logo field', () {
      final ts = Timestamp.fromMillisecondsSinceEpoch(1000);
      final original = SettingsModel(
        companyName: 'My Shop',
        currency: 'PKR',
        pairsPerCarton: 12,
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
        companyName: 'My Shop',
        currency: 'PKR',
        pairsPerCarton: 12,
        updatedAt: ts,
      );
      final right = SettingsModel(
        companyName: 'My Shop',
        currency: 'PKR',
        pairsPerCarton: 12,
        updatedAt: ts,
      );

      expect(left, right);
      expect(left.hashCode, right.hashCode);
    });

    test('asserts when pairsPerCarton is not positive', () {
      expect(
        () => SettingsModel(
          companyName: 'Broken',
          currency: 'PKR',
          pairsPerCarton: 0,
          updatedAt: Timestamp.fromMillisecondsSinceEpoch(0),
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
