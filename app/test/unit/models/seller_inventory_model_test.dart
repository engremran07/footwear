import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/seller_inventory_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);

  final baseJson = <String, dynamic>{
    'seller_id': 's1',
    'seller_name': 'Ali Khan',
    'product_id': 'p1',
    'variant_id': 'v1',
    'variant_name': 'Sandal 40 Brown',
    'quantity_available': 36,
    'active': true,
    'created_at': ts,
    'updated_at': ts,
  };

  group('SellerInventoryModel.fromJson', () {
    test('parses all fields correctly', () {
      final m = SellerInventoryModel.fromJson(baseJson, 'si1');
      expect(m.id, 'si1');
      expect(m.sellerId, 's1');
      expect(m.sellerName, 'Ali Khan');
      expect(m.productId, 'p1');
      expect(m.variantId, 'v1');
      expect(m.variantName, 'Sandal 40 Brown');
      expect(m.quantityAvailable, 36);
      expect(m.active, isTrue);
      expect(m.createdAt, ts);
      expect(m.updatedAt, ts);
    });

    test('missing fields use safe defaults', () {
      final m = SellerInventoryModel.fromJson({}, 'si2');
      expect(m.id, 'si2');
      expect(m.sellerId, '');
      expect(m.sellerName, '');
      expect(m.productId, '');
      expect(m.variantId, '');
      expect(m.variantName, '');
      expect(m.quantityAvailable, 0);
      expect(m.active, isTrue);
    });

    test('active=false parses correctly', () {
      final json = Map<String, dynamic>.from(baseJson)..['active'] = false;
      final m = SellerInventoryModel.fromJson(json, 'si3');
      expect(m.active, isFalse);
    });

    test('zero quantity parses correctly', () {
      final json = Map<String, dynamic>.from(baseJson)
        ..['quantity_available'] = 0;
      final m = SellerInventoryModel.fromJson(json, 'si4');
      expect(m.quantityAvailable, 0);
    });
  });

  group('SellerInventoryModel.toJson', () {
    test('round-trips all fields', () {
      final original = SellerInventoryModel.fromJson(baseJson, 'si1');
      final json = original.toJson();
      final restored = SellerInventoryModel.fromJson(json, 'si1');
      expect(restored.sellerId, original.sellerId);
      expect(restored.sellerName, original.sellerName);
      expect(restored.productId, original.productId);
      expect(restored.variantId, original.variantId);
      expect(restored.variantName, original.variantName);
      expect(restored.quantityAvailable, original.quantityAvailable);
      expect(restored.active, original.active);
      expect(restored.createdAt, original.createdAt);
      expect(restored.updatedAt, original.updatedAt);
    });

    test('toJson excludes id field', () {
      final m = SellerInventoryModel.fromJson(baseJson, 'si1');
      expect(m.toJson().containsKey('id'), isFalse);
    });

    test('toJson preserves all 9 expected keys', () {
      final m = SellerInventoryModel.fromJson(baseJson, 'si1');
      final keys = m.toJson().keys.toSet();
      expect(
        keys,
        containsAll([
          'seller_id',
          'seller_name',
          'product_id',
          'variant_id',
          'variant_name',
          'quantity_available',
          'active',
          'created_at',
          'updated_at',
        ]),
      );
    });

    test('quantity_available reflects updated value', () {
      final json = Map<String, dynamic>.from(baseJson)
        ..['quantity_available'] = 99;
      final m = SellerInventoryModel.fromJson(json, 'si1');
      expect(m.toJson()['quantity_available'], 99);
    });
  });
}
