import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/inventory_transaction_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);

  final baseJson = <String, dynamic>{
    'type': InventoryTransactionModel.typeTransferOut,
    'seller_id': 's1',
    'seller_name': 'Ali Khan',
    'variant_id': 'v1',
    'variant_name': 'Sandal 40 Brown',
    'product_id': 'p1',
    'quantity': 12,
    'notes': 'Transfer to route 5',
    'created_by': 'admin1',
    'created_at': ts,
  };

  group('InventoryTransactionModel.fromJson', () {
    test('parses all fields correctly', () {
      final m = InventoryTransactionModel.fromJson(baseJson, 'it1');
      expect(m.id, 'it1');
      expect(m.type, InventoryTransactionModel.typeTransferOut);
      expect(m.sellerId, 's1');
      expect(m.sellerName, 'Ali Khan');
      expect(m.variantId, 'v1');
      expect(m.variantName, 'Sandal 40 Brown');
      expect(m.productId, 'p1');
      expect(m.quantity, 12);
      expect(m.notes, 'Transfer to route 5');
      expect(m.createdBy, 'admin1');
      expect(m.createdAt, ts);
    });

    test('missing fields use safe defaults', () {
      final m = InventoryTransactionModel.fromJson({}, 'it2');
      expect(m.id, 'it2');
      expect(m.type, '');
      expect(m.sellerId, '');
      expect(m.sellerName, '');
      expect(m.variantId, '');
      expect(m.variantName, '');
      expect(m.productId, '');
      expect(m.quantity, 0);
      expect(m.notes, isNull);
      expect(m.createdBy, '');
    });

    test('notes field may be null', () {
      final json = Map<String, dynamic>.from(baseJson)..remove('notes');
      final m = InventoryTransactionModel.fromJson(json, 'it3');
      expect(m.notes, isNull);
    });
  });

  group('InventoryTransactionModel.toJson', () {
    test('toJson round-trips all fields', () {
      final original = InventoryTransactionModel.fromJson(baseJson, 'it1');
      final json = original.toJson();
      final restored = InventoryTransactionModel.fromJson(json, 'it1');
      expect(restored.type, original.type);
      expect(restored.sellerId, original.sellerId);
      expect(restored.sellerName, original.sellerName);
      expect(restored.variantId, original.variantId);
      expect(restored.variantName, original.variantName);
      expect(restored.productId, original.productId);
      expect(restored.quantity, original.quantity);
      expect(restored.notes, original.notes);
      expect(restored.createdBy, original.createdBy);
      expect(restored.createdAt, original.createdAt);
    });

    test('toJson excludes id field', () {
      final m = InventoryTransactionModel.fromJson(baseJson, 'it1');
      expect(m.toJson().containsKey('id'), isFalse);
    });
  });

  group('type constants', () {
    test('typeTransferOut has correct value', () {
      expect(InventoryTransactionModel.typeTransferOut, 'transfer_out');
    });
    test('typeReturnToWarehouse has correct value', () {
      expect(
        InventoryTransactionModel.typeReturnToWarehouse,
        'return_to_warehouse',
      );
    });
    test('typeReturnFromShop has correct value', () {
      expect(InventoryTransactionModel.typeReturnFromShop, 'return_from_shop');
    });
    test('typeStockAdjustment has correct value', () {
      expect(InventoryTransactionModel.typeStockAdjustment, 'stock_adjustment');
    });
  });
}
