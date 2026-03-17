import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/purchase_order_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);
  final sampleItems = [
    {'product_id': 'p1', 'product_name': 'Shoe A', 'sku': 'SKU-001', 'size': '42', 'qty': 10, 'unit_cost': 25.0},
  ];
  final base = <String, dynamic>{
    'supplier_id': 's1',
    'supplier_name': 'Best Leather Co',
    'items': sampleItems,
    'total': 250.0,
    'status': 'draft',
    'expected_delivery': null,
    'inventory_batch_id': null,
    'received_at': null,
    'notes': null,
    'created_by': 'user1',
    'created_at': ts,
    'updated_at': ts,
  };

  group('PurchaseOrderModel.fromJson', () {
    test('parses required fields', () {
      final m = PurchaseOrderModel.fromJson(base, 'po1');
      expect(m.id, 'po1');
      expect(m.supplierId, 's1');
      expect(m.supplierName, 'Best Leather Co');
      expect(m.total, 250.0);
      expect(m.status, 'draft');
      expect(m.createdBy, 'user1');
    });

    test('parses items list', () {
      final m = PurchaseOrderModel.fromJson(base, 'po1');
      expect(m.items, hasLength(1));
      expect(m.items.first['product_id'], 'p1');
      expect(m.items.first['qty'], 10);
    });

    test('optional fields null', () {
      final m = PurchaseOrderModel.fromJson(base, 'po1');
      expect(m.expectedDelivery, isNull);
      expect(m.inventoryBatchId, isNull);
      expect(m.receivedAt, isNull);
      expect(m.notes, isNull);
    });

    test('received PO parses batch and timestamps', () {
      final m = PurchaseOrderModel.fromJson({
        ...base,
        'status': 'received',
        'inventory_batch_id': 'b1',
        'received_at': ts,
      }, 'po2');
      expect(m.status, 'received');
      expect(m.inventoryBatchId, 'b1');
      expect(m.receivedAt, ts);
    });

    test('defaults for empty json', () {
      final m = PurchaseOrderModel.fromJson({}, 'po3');
      expect(m.status, 'draft');
      expect(m.items, isEmpty);
      expect(m.total, 0.0);
    });
  });

  group('PurchaseOrderModel.toJson + copyWith', () {
    test('round-trip preserves items', () {
      final original = PurchaseOrderModel.fromJson(base, 'po1');
      final restored = PurchaseOrderModel.fromJson(original.toJson(), 'po1');
      expect(restored.items, hasLength(1));
      expect(restored.supplierId, original.supplierId);
    });

    test('copyWith changes status', () {
      final m = PurchaseOrderModel.fromJson(base, 'po1');
      final copy = m.copyWith(status: 'sent');
      expect(copy.status, 'sent');
      expect(copy.supplierId, m.supplierId);
    });
  });
}
