import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/product_variant_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);

  final baseJson = <String, dynamic>{
    'product_id': 'p1',
    'variant_name': 'Sandal 40 Brown',
    'quantity_available': 24,
    'active': true,
    'created_at': ts,
    'updated_at': ts,
  };

  group('ProductVariantModel.fromJson', () {
    test('parses all fields correctly', () {
      final m = ProductVariantModel.fromJson(baseJson, 'pv1');
      expect(m.id, 'pv1');
      expect(m.productId, 'p1');
      expect(m.variantName, 'Sandal 40 Brown');
      expect(m.quantityAvailable, 24);
      expect(m.active, isTrue);
      expect(m.createdAt, ts);
      expect(m.updatedAt, ts);
    });

    test('missing fields use safe defaults', () {
      final m = ProductVariantModel.fromJson({}, 'pv2');
      expect(m.id, 'pv2');
      expect(m.productId, '');
      expect(m.variantName, '');
      expect(m.quantityAvailable, 0);
      expect(m.active, isTrue);
    });

    test('active=false parses correctly', () {
      final json = Map<String, dynamic>.from(baseJson)..['active'] = false;
      final m = ProductVariantModel.fromJson(json, 'pv3');
      expect(m.active, isFalse);
    });

    test('zero stock parses correctly', () {
      final json = Map<String, dynamic>.from(baseJson)
        ..['quantity_available'] = 0;
      final m = ProductVariantModel.fromJson(json, 'pv4');
      expect(m.quantityAvailable, 0);
    });
  });

  group('ProductVariantModel.toJson', () {
    test('round-trips all fields', () {
      final original = ProductVariantModel.fromJson(baseJson, 'pv1');
      final json = original.toJson();
      final restored = ProductVariantModel.fromJson(json, 'pv1');
      expect(restored.productId, original.productId);
      expect(restored.variantName, original.variantName);
      expect(restored.quantityAvailable, original.quantityAvailable);
      expect(restored.active, original.active);
      expect(restored.createdAt, original.createdAt);
      expect(restored.updatedAt, original.updatedAt);
    });

    test('toJson excludes id field', () {
      final m = ProductVariantModel.fromJson(baseJson, 'pv1');
      expect(m.toJson().containsKey('id'), isFalse);
    });

    test('toJson preserves quantity_available correctly', () {
      final m = ProductVariantModel.fromJson({
        ...baseJson,
        'quantity_available': 100,
      }, 'pv1');
      expect(m.toJson()['quantity_available'], 100);
    });
  });

  group('ProductVariantModel.copyWith', () {
    test('copyWith changes only the specified field', () {
      final original = ProductVariantModel.fromJson(baseJson, 'pv1');
      final copy = original.copyWith(quantityAvailable: 50);
      expect(copy.quantityAvailable, 50);
      expect(copy.productId, original.productId);
      expect(copy.variantName, original.variantName);
      expect(copy.active, original.active);
    });

    test('copyWith with no args returns equivalent object', () {
      final original = ProductVariantModel.fromJson(baseJson, 'pv1');
      final copy = original.copyWith();
      expect(copy.id, original.id);
      expect(copy.variantName, original.variantName);
      expect(copy.quantityAvailable, original.quantityAvailable);
    });
  });
}
