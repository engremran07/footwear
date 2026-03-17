import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/settings_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);
  final base = <String, dynamic>{
    'company_name': 'Footwear ERP Ltd',
    'currency_primary': 'SAR',
    'currency_secondary': 'PKR',
    'tax_rate': 15.0,
    'low_stock_threshold': 10,
    'logo_url': null,
    'company_address': 'Riyadh, KSA',
    'company_phone': '+966 11 234 5678',
    'default_pk_rate': 85.0,
    'default_ksa_rate': 15.0,
    'product_categories': ['Formal', 'Sports'],
    'expense_categories': ['rent', 'utilities'],
    'qc_reject_reasons': ['stitching_issue', 'sole_defect'],
    'updated_at': ts,
  };

  group('SettingsModel.fromJson', () {
    test('parses all fields', () {
      final m = SettingsModel.fromJson(base, 'global');
      expect(m.id, 'global');
      expect(m.companyName, 'Footwear ERP Ltd');
      expect(m.companyAddress, 'Riyadh, KSA');
      expect(m.companyPhone, '+966 11 234 5678');
      expect(m.defaultPkRate, 85.0);
      expect(m.defaultKsaRate, 15.0);
      expect(m.productCategories, ['Formal', 'Sports']);
      expect(m.expenseCategories, ['rent', 'utilities']);
      expect(m.qcRejectReasons, ['stitching_issue', 'sole_defect']);
      expect(m.currencyPrimary, 'SAR');
      expect(m.currencySecondary, 'PKR');
      expect(m.taxRate, 15.0);
      expect(m.lowStockThreshold, 10);
      expect(m.logoUrl, isNull);
    });

    test('handles integer tax rate', () {
      final m = SettingsModel.fromJson({...base, 'tax_rate': 15}, 'global');
      expect(m.taxRate, 15.0);
    });
  });

  group('SettingsModel.toJson + copyWith', () {
    test('round-trip', () {
      final original = SettingsModel.fromJson(base, 'global');
      final restored = SettingsModel.fromJson(original.toJson(), 'global');
      expect(restored.companyName, original.companyName);
      expect(restored.taxRate, original.taxRate);
    });

    test('copyWith changes threshold', () {
      final m = SettingsModel.fromJson(base, 'global');
      final copy = m.copyWith(lowStockThreshold: 20);
      expect(copy.lowStockThreshold, 20);
      expect(copy.companyName, m.companyName);
    });
  });
}
