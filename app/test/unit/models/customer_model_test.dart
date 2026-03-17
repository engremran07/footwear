import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/customer_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);
  final base = <String, dynamic>{
    'name': 'Acme Corp',
    'phone': '+966501234567',
    'email': null,
    'address': null,
    'city': null,
    'country': 'SAR',
    'balance': 0.0,
    'total_orders': 5,
    'created_at': ts,
    'updated_at': ts,
  };

  group('CustomerModel.fromJson', () {
    test('parses required fields', () {
      final m = CustomerModel.fromJson(base, 'c1');
      expect(m.id, 'c1');
      expect(m.name, 'Acme Corp');
      expect(m.phone, '+966501234567');
      expect(m.country, 'SAR');
      expect(m.balance, 0.0);
      expect(m.totalOrders, 5);
    });

    test('optional fields null by default', () {
      final m = CustomerModel.fromJson(base, 'c1');
      expect(m.email, isNull);
      expect(m.address, isNull);
      expect(m.city, isNull);
    });

    test('optional fields parsed when present', () {
      final m = CustomerModel.fromJson({
        ...base,
        'email': 'test@example.com',
        'address': '123 Main St',
        'city': 'Riyadh',
      }, 'c2');
      expect(m.email, 'test@example.com');
      expect(m.address, '123 Main St');
      expect(m.city, 'Riyadh');
    });

    test('defaults for empty json', () {
      final m = CustomerModel.fromJson({}, 'c3');
      expect(m.name, '');
      expect(m.balance, 0.0);
      expect(m.totalOrders, 0);
    });

    test('handles integer balance', () {
      final m = CustomerModel.fromJson({...base, 'balance': 500}, 'c4');
      expect(m.balance, 500.0);
    });
  });

  group('CustomerModel.toJson', () {
    test('round-trip preserves data', () {
      final original = CustomerModel.fromJson({...base, 'email': 'a@b.com'}, 'c1');
      final restored = CustomerModel.fromJson(original.toJson(), 'c1');
      expect(restored.name, original.name);
      expect(restored.email, original.email);
      expect(restored.balance, original.balance);
    });
  });

  group('CustomerModel.copyWith', () {
    test('changes balance', () {
      final m = CustomerModel.fromJson(base, 'c1');
      final copy = m.copyWith(balance: 1500.0);
      expect(copy.balance, 1500.0);
      expect(copy.name, m.name);
    });

    test('changes totalOrders', () {
      final m = CustomerModel.fromJson(base, 'c1');
      final copy = m.copyWith(totalOrders: 10);
      expect(copy.totalOrders, 10);
    });
  });
}
