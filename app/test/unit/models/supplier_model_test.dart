import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/supplier_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);
  final base = <String, dynamic>{
    'name': 'Best Leather Co',
    'contact_name': 'Tariq Ali',
    'phone': '+923001234567',
    'email': null,
    'address': null,
    'payment_terms': 'Net 30',
    'total_purchased': 100000.0,
    'last_order_at': null,
    'active': true,
    'created_at': ts,
    'updated_at': ts,
  };

  group('SupplierModel.fromJson', () {
    test('parses required fields', () {
      final m = SupplierModel.fromJson(base, 's1');
      expect(m.id, 's1');
      expect(m.name, 'Best Leather Co');
      expect(m.contactName, 'Tariq Ali');
      expect(m.phone, '+923001234567');
      expect(m.paymentTerms, 'Net 30');
      expect(m.totalPurchased, 100000.0);
      expect(m.active, isTrue);
    });

    test('optional fields null', () {
      final m = SupplierModel.fromJson(base, 's1');
      expect(m.email, isNull);
      expect(m.address, isNull);
      expect(m.lastOrderAt, isNull);
    });

    test('optional fields parsed when present', () {
      final m = SupplierModel.fromJson({
        ...base,
        'email': 'supplier@example.com',
        'address': 'Karachi Industrial Zone',
        'last_order_at': ts,
      }, 's2');
      expect(m.email, 'supplier@example.com');
      expect(m.address, 'Karachi Industrial Zone');
      expect(m.lastOrderAt, ts);
    });

    test('defaults for empty json', () {
      final m = SupplierModel.fromJson({}, 's3');
      expect(m.name, '');
      expect(m.totalPurchased, 0.0);
      expect(m.active, isTrue);
    });
  });

  group('SupplierModel.toJson + copyWith', () {
    test('round-trip', () {
      final original = SupplierModel.fromJson({...base, 'email': 'a@b.com'}, 's1');
      final restored = SupplierModel.fromJson(original.toJson(), 's1');
      expect(restored.name, original.name);
      expect(restored.email, original.email);
    });

    test('copyWith changes active', () {
      final m = SupplierModel.fromJson(base, 's1');
      final copy = m.copyWith(active: false);
      expect(copy.active, isFalse);
      expect(copy.name, m.name);
    });
  });
}
