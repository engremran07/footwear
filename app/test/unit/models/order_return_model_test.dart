import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:footwear_erp/models/order_return_model.dart';

void main() {
  group('ReturnItem', () {
    test('fromMap parses all fields', () {
      final map = {
        'order_item_id': 'oi_001',
        'product_id': 'prod_001',
        'product_name': 'Chelsea Boot',
        'size': '42',
        'qty_returned': 12,
        'condition': 'good',
        'reason': 'wrong_size',
      };
      final item = ReturnItem.fromMap(map);
      expect(item.orderItemId, 'oi_001');
      expect(item.productName, 'Chelsea Boot');
      expect(item.size, '42');
      expect(item.qtyReturned, 12);
      expect(item.condition, 'good');
      expect(item.reason, 'wrong_size');
    });

    test('fromMap uses defaults for missing fields', () {
      final item = ReturnItem.fromMap({});
      expect(item.orderItemId, '');
      expect(item.qtyReturned, 0);
      expect(item.condition, 'good');
      expect(item.reason, 'other');
    });

    test('toMap round-trips correctly', () {
      const item = ReturnItem(
        orderItemId: 'oi_1',
        productId: 'p_1',
        productName: 'Desert Boot',
        size: '40',
        qtyReturned: 20,
        condition: 'damaged',
        reason: 'sole_defect',
      );
      final map = item.toMap();
      expect(map['order_item_id'], 'oi_1');
      expect(map['qty_returned'], 20);
      expect(map['condition'], 'damaged');
      expect(map['reason'], 'sole_defect');
    });

    test('copyWith overrides only specified fields', () {
      const item = ReturnItem(
        orderItemId: 'oi_1',
        productId: 'p_1',
        productName: 'Boot A',
        size: '41',
        qtyReturned: 12,
        condition: 'good',
        reason: 'wrong_size',
      );
      final changed = item.copyWith(qtyReturned: 20, condition: 'damaged');
      expect(changed.orderItemId, 'oi_1');
      expect(changed.qtyReturned, 20);
      expect(changed.condition, 'damaged');
      expect(changed.reason, 'wrong_size'); // unchanged
    });
  });

  group('OrderReturnModel', () {
    final ts = Timestamp.fromDate(DateTime(2026, 3, 1));

    Map<String, dynamic> baseJson() => {
          'order_id': 'ord_001',
          'customer_id': 'cust_001',
          'customer_name': 'Ali Hassan',
          'type': 'partial_return',
          'items': [
            {
              'order_item_id': 'oi_1',
              'product_id': 'p_1',
              'product_name': 'Chelsea Boot',
              'size': '42',
              'qty_returned': 12,
              'condition': 'good',
              'reason': 'wrong_size',
            }
          ],
          'total_qty_returned': 12,
          'refund_amount': 1200.0,
          'replacement_order_id': null,
          'notes': 'Customer changed mind',
          'status': 'pending',
          'approved_by': null,
          'approved_at': null,
          'created_by': 'uid_mgr',
          'created_at': ts,
          'updated_at': ts,
        };

    test('fromJson parses scalar fields', () {
      final model = OrderReturnModel.fromJson(baseJson(), 'ret_001');
      expect(model.id, 'ret_001');
      expect(model.orderId, 'ord_001');
      expect(model.customerName, 'Ali Hassan');
      expect(model.type, 'partial_return');
      expect(model.totalQtyReturned, 12);
      expect(model.refundAmount, 1200.0);
      expect(model.status, 'pending');
      expect(model.createdBy, 'uid_mgr');
    });

    test('fromJson parses items list', () {
      final model = OrderReturnModel.fromJson(baseJson(), 'ret_001');
      expect(model.items.length, 1);
      expect(model.items.first.productName, 'Chelsea Boot');
      expect(model.items.first.qtyReturned, 12);
    });

    test('fromJson handles empty items list', () {
      final json = baseJson();
      json['items'] = [];
      final model = OrderReturnModel.fromJson(json, 'ret_002');
      expect(model.items, isEmpty);
    });

    test('fromJson handles null/missing items', () {
      final json = baseJson();
      json.remove('items');
      final model = OrderReturnModel.fromJson(json, 'ret_003');
      expect(model.items, isEmpty);
    });

    test('fromJson uses defaults for missing optional fields', () {
      final model = OrderReturnModel.fromJson({}, 'ret_empty');
      expect(model.id, 'ret_empty');
      expect(model.orderId, '');
      expect(model.status, 'pending');
      expect(model.refundAmount, 0.0);
      expect(model.totalQtyReturned, 0);
    });

    test('toJson round-trips correcty', () {
      final model = OrderReturnModel.fromJson(baseJson(), 'ret_001');
      final json = model.toJson();
      expect(json['order_id'], 'ord_001');
      expect(json['customer_name'], 'Ali Hassan');
      expect(json['total_qty_returned'], 12);
      expect(json['refund_amount'], 1200.0);
      expect(json['status'], 'pending');
      expect((json['items'] as List).length, 1);
    });

    test('copyWith overrides only specified fields', () {
      final model = OrderReturnModel.fromJson(baseJson(), 'ret_001');
      final updated = model.copyWith(status: 'approved', refundAmount: 600.0);
      expect(updated.id, 'ret_001');
      expect(updated.status, 'approved');
      expect(updated.refundAmount, 600.0);
      expect(updated.customerName, 'Ali Hassan'); // unchanged
    });

    test('status helpers work correctly', () {
      final pending = OrderReturnModel.fromJson(baseJson(), 'r1');
      expect(pending.isPending, true);
      expect(pending.isApproved, false);
      expect(pending.isCompleted, false);

      final approved =
          OrderReturnModel.fromJson({...baseJson(), 'status': 'approved'}, 'r2');
      expect(approved.isApproved, true);
      expect(approved.isPending, false);

      final completed =
          OrderReturnModel.fromJson({...baseJson(), 'status': 'completed'}, 'r3');
      expect(completed.isCompleted, true);

      final rejected =
          OrderReturnModel.fromJson({...baseJson(), 'status': 'rejected'}, 'r4');
      expect(rejected.isRejected, true);
    });

    test('type enum values round-trip', () {
      for (final type in [
        'full_return',
        'partial_return',
        'replacement',
        'damage_claim'
      ]) {
        final model =
            OrderReturnModel.fromJson({...baseJson(), 'type': type}, 'r');
        expect(model.type, type);
      }
    });

    test('replacementOrderId is nullable', () {
      final withReplacement = OrderReturnModel.fromJson(
          {...baseJson(), 'replacement_order_id': 'ord_r01'}, 'r');
      expect(withReplacement.replacementOrderId, 'ord_r01');

      final withoutReplacement = OrderReturnModel.fromJson(baseJson(), 'r2');
      expect(withoutReplacement.replacementOrderId, isNull);
    });
  });
}
