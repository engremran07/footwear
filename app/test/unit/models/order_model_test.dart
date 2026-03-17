import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/order_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);
  final base = <String, dynamic>{
    'customer_id': 'cust1',
    'customer_name': 'Acme Corp',
    'status': 'pending',
    'total': 500.0,
    'notes': null,
    'created_by': 'user1',
    'created_at': ts,
    'updated_at': ts,
  };

  group('OrderModel.fromJson', () {
    test('parses required fields', () {
      final m = OrderModel.fromJson(base, 'o1');
      expect(m.id, 'o1');
      expect(m.customerId, 'cust1');
      expect(m.customerName, 'Acme Corp');
      expect(m.status, 'pending');
      expect(m.total, 500.0);
      expect(m.createdBy, 'user1');
      expect(m.notes, isNull);
    });

    test('parses notes when present', () {
      final m = OrderModel.fromJson({...base, 'notes': 'Rush order'}, 'o2');
      expect(m.notes, 'Rush order');
    });

    test('defaults for empty json', () {
      final m = OrderModel.fromJson({}, 'o3');
      expect(m.status, 'pending');
      expect(m.total, 0.0);
      expect(m.customerId, '');
    });

    test('handles integer total', () {
      final m = OrderModel.fromJson({...base, 'total': 1000}, 'o4');
      expect(m.total, 1000.0);
    });
  });

  group('OrderModel.toJson', () {
    test('serialises correctly', () {
      final m = OrderModel.fromJson(base, 'o1');
      final json = m.toJson();
      expect(json['customer_id'], 'cust1');
      expect(json['status'], 'pending');
      expect(json['total'], 500.0);
    });

    test('round-trip preserves data', () {
      final original = OrderModel.fromJson(base, 'o1');
      final restored = OrderModel.fromJson(original.toJson(), 'o1');
      expect(restored.customerName, original.customerName);
      expect(restored.total, original.total);
    });
  });

  group('OrderModel.copyWith', () {
    test('changes status', () {
      final m = OrderModel.fromJson(base, 'o1');
      final copy = m.copyWith(status: 'shipped');
      expect(copy.status, 'shipped');
      expect(copy.customerId, m.customerId);
    });

    test('changes total', () {
      final m = OrderModel.fromJson(base, 'o1');
      final copy = m.copyWith(total: 750.0);
      expect(copy.total, 750.0);
    });
  });
}
