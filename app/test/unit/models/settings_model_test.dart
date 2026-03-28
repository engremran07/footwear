import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/settings_model.dart';

void main() {
  group('SettingsModel.fromJson', () {
    final ts = Timestamp.fromMillisecondsSinceEpoch(0);
    final baseJson = <String, dynamic>{
      'company_name': 'Test Co',
      'currency': 'SAR',
      'pairs_per_carton': 12,
      'logo_base64': 'aGVsbG8=', // base64('hello')
      'updated_at': ts,
    };

    test('parses all fields correctly', () {
      final m = SettingsModel.fromJson(baseJson);
      expect(m.companyName, 'Test Co');
      expect(m.currency, 'SAR');
      expect(m.pairsPerCarton, 12);
      expect(m.logoBase64, 'aGVsbG8=');
      expect(m.logoBytes, isNotNull);
    });

    test('missing fields use defaults', () {
      final m = SettingsModel.fromJson({});
      expect(m.companyName, 'My Business');
      expect(m.currency, 'SAR');
      expect(m.pairsPerCarton, 12);
      expect(m.logoBase64, isNull);
      expect(m.logoBytes, isNull);
    });
  });

  group('SettingsModel.toJson', () {
    test('round-trips through fromJson/toJson', () {
      final ts = Timestamp.fromMillisecondsSinceEpoch(1000);
      final original = SettingsModel(
        companyName: 'My Shop',
        currency: 'PKR',
        pairsPerCarton: 20,
        updatedAt: ts,
      );
      final json = original.toJson();
      final restored = SettingsModel.fromJson(json);
      expect(restored.companyName, original.companyName);
      expect(restored.currency, original.currency);
      expect(restored.pairsPerCarton, original.pairsPerCarton);
    });
  });
}
