import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/inventory_batch_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);
  final base = <String, dynamic>{
    'product_id': 'prod1',
    'purchase_order_id': null,
    'supplier_id': null,
    'qty_produced': 100,
    'qty_passed': 90,
    'qty_rejected': 10,
    'cost_total': 2500.0,
    'cost_per_pair': 25.0,
    'status': 'in_production',
    'source': 'production',
    'last_qc_id': null,
    'completed_at': null,
    'created_at': ts,
    'updated_at': ts,
  };

  group('InventoryBatchModel.fromJson', () {
    test('parses required fields', () {
      final m = InventoryBatchModel.fromJson(base, 'b1');
      expect(m.id, 'b1');
      expect(m.productId, 'prod1');
      expect(m.qtyProduced, 100);
      expect(m.qtyPassed, 90);
      expect(m.qtyRejected, 10);
      expect(m.costTotal, 2500.0);
      expect(m.costPerPair, 25.0);
      expect(m.status, 'in_production');
      expect(m.source, 'production');
    });

    test('nullable optional fields are null', () {
      final m = InventoryBatchModel.fromJson(base, 'b1');
      expect(m.purchaseOrderId, isNull);
      expect(m.supplierId, isNull);
      expect(m.lastQcId, isNull);
      expect(m.completedAt, isNull);
    });

    test('optional string fields populated when present', () {
      final m = InventoryBatchModel.fromJson({
        ...base,
        'purchase_order_id': 'po1',
        'supplier_id': 's1',
        'last_qc_id': 'qc1',
        'completed_at': ts,
        'source': 'purchase_order',
      }, 'b2');
      expect(m.purchaseOrderId, 'po1');
      expect(m.supplierId, 's1');
      expect(m.lastQcId, 'qc1');
      expect(m.completedAt, ts);
      expect(m.source, 'purchase_order');
    });

    test('defaults for missing fields', () {
      final m = InventoryBatchModel.fromJson({}, 'b3');
      expect(m.productId, '');
      expect(m.qtyProduced, 0);
      expect(m.status, 'draft');
      expect(m.source, 'production');
    });

    test('handles numeric cost as int', () {
      final m = InventoryBatchModel.fromJson({...base, 'cost_total': 3000, 'cost_per_pair': 30}, 'b4');
      expect(m.costTotal, 3000.0);
      expect(m.costPerPair, 30.0);
    });
  });

  group('InventoryBatchModel.toJson', () {
    test('serialises core fields', () {
      final m = InventoryBatchModel.fromJson(base, 'b1');
      final json = m.toJson();
      expect(json['product_id'], 'prod1');
      expect(json['qty_produced'], 100);
      expect(json['status'], 'in_production');
    });
  });

  group('InventoryBatchModel.copyWith', () {
    test('changes status', () {
      final m = InventoryBatchModel.fromJson(base, 'b1');
      final copy = m.copyWith(status: 'qc_passed');
      expect(copy.status, 'qc_passed');
      expect(copy.productId, m.productId);
    });

    test('changes qty fields', () {
      final m = InventoryBatchModel.fromJson(base, 'b1');
      final copy = m.copyWith(qtyPassed: 95, qtyRejected: 5);
      expect(copy.qtyPassed, 95);
      expect(copy.qtyRejected, 5);
    });
  });
}
