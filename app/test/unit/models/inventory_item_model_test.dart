import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/inventory_item_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);
  final base = <String, dynamic>{
    'product_id': 'prod1',
    'product_name': 'Test Shoe',
    'sku': 'SKU-001',
    'size': '42',
    'inventory_batch_id': 'batch1',
    'purchase_order_id': null,
    'cost_per_pair': 25.0,
    'status': 'available',
    'order_id': null,
    'order_item_id': null,
    'qc_record_id': null,
    'reserved_at': null,
    'created_at': ts,
    'updated_at': ts,
  };

  group('InventoryItemModel.fromJson', () {
    test('parses all fields', () {
      final m = InventoryItemModel.fromJson(base, 'i1');
      expect(m.id, 'i1');
      expect(m.productId, 'prod1');
      expect(m.productName, 'Test Shoe');
      expect(m.sku, 'SKU-001');
      expect(m.size, '42');
      expect(m.inventoryBatchId, 'batch1');
      expect(m.costPerPair, 25.0);
      expect(m.status, 'available');
    });

    test('nullable fields are null', () {
      final m = InventoryItemModel.fromJson(base, 'i1');
      expect(m.purchaseOrderId, isNull);
      expect(m.orderId, isNull);
      expect(m.orderItemId, isNull);
      expect(m.qcRecordId, isNull);
      expect(m.reservedAt, isNull);
    });

    test('populates optional fields when present', () {
      final m = InventoryItemModel.fromJson({
        ...base,
        'order_id': 'o1',
        'order_item_id': 'oi1',
        'qc_record_id': 'qc1',
        'reserved_at': ts,
      }, 'i2');
      expect(m.orderId, 'o1');
      expect(m.orderItemId, 'oi1');
      expect(m.qcRecordId, 'qc1');
      expect(m.reservedAt, ts);
    });

    test('defaults for empty json', () {
      final m = InventoryItemModel.fromJson({}, 'i3');
      expect(m.status, 'available');
      expect(m.costPerPair, 0.0);
      expect(m.size, isNull);
    });
  });

  group('InventoryItemModel.toJson', () {
    test('round-trip preserves required fields', () {
      final m = InventoryItemModel.fromJson(base, 'i1');
      final json = m.toJson();
      final restored = InventoryItemModel.fromJson(json, 'i1');
      expect(restored.productId, m.productId);
      expect(restored.size, m.size);
      expect(restored.status, m.status);
    });
  });

  group('InventoryItemModel.copyWith', () {
    test('changes status', () {
      final m = InventoryItemModel.fromJson(base, 'i1');
      final copy = m.copyWith(status: 'reserved', orderId: 'o99');
      expect(copy.status, 'reserved');
      expect(copy.orderId, 'o99');
      expect(copy.size, m.size);
    });
  });
}
