import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/order_item_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);
  final base = <String, dynamic>{
    'order_id': 'o1',
    'product_id': 'p1',
    'product_name': 'Test Shoe',
    'size': '42',
    'qty': 2,
    'unit_price': 50.0,
    'subtotal': 100.0,
    'inventory_batch_id': null,
    'status': 'pending',
    'created_at': ts,
    'updated_at': ts,
  };

  group('OrderItemModel.fromJson', () {
    test('parses all fields', () {
      final m = OrderItemModel.fromJson(base, 'oi1');
      expect(m.id, 'oi1');
      expect(m.orderId, 'o1');
      expect(m.productId, 'p1');
      expect(m.productName, 'Test Shoe');
      expect(m.size, '42');
      expect(m.qty, 2);
      expect(m.unitPrice, 50.0);
      expect(m.subtotal, 100.0);
      expect(m.status, 'pending');
      expect(m.inventoryBatchId, isNull);
    });

    test('parses inventoryBatchId when present', () {
      final m = OrderItemModel.fromJson({...base, 'inventory_batch_id': 'bx1'}, 'oi2');
      expect(m.inventoryBatchId, 'bx1');
    });

    test('defaults for empty json', () {
      final m = OrderItemModel.fromJson({}, 'oi3');
      expect(m.status, 'pending');
      expect(m.qty, 0);
      expect(m.unitPrice, 0.0);
      expect(m.subtotal, 0.0);
    });
  });

  group('OrderItemModel.toJson + copyWith', () {
    test('round-trip preserves data', () {
      final original = OrderItemModel.fromJson(base, 'oi1');
      final restored = OrderItemModel.fromJson(original.toJson(), 'oi1');
      expect(restored.qty, original.qty);
      expect(restored.subtotal, original.subtotal);
    });

    test('copyWith changes status', () {
      final m = OrderItemModel.fromJson(base, 'oi1');
      final copy = m.copyWith(status: 'dispatched');
      expect(copy.status, 'dispatched');
      expect(copy.qty, m.qty);
    });
  });
}
