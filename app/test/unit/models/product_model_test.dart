import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/product_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);
  final sampleJson = <String, dynamic>{
    'sku': 'SKU-001',
    'name': 'Test Shoe',
    'category': 'Sports',
    'sizes': ['40', '41', '42'],
    'cost_price': 25.0,
    'sell_price': 50.0,
    'image_url': null,
    'stock_count': 10,
    'active': true,
    'created_at': ts,
    'updated_at': ts,
  };

  group('ProductModel.fromJson', () {
    test('parses all fields', () {
      final m = ProductModel.fromJson(sampleJson, 'p1');
      expect(m.id, 'p1');
      expect(m.sku, 'SKU-001');
      expect(m.name, 'Test Shoe');
      expect(m.category, 'Sports');
      expect(m.sizes, ['40', '41', '42']);
      expect(m.costPriceDozenPkr, 25.0);
      expect(m.sellPriceDozenSar, 50.0);
      expect(m.imageUrl, isNull);
      expect(m.stockCount, 10);
      expect(m.active, isTrue);
    });

    test('parses imageUrl when present', () {
      final m = ProductModel.fromJson(
          {...sampleJson, 'image_url': 'http://example.com/img.jpg'}, 'p2');
      expect(m.imageUrl, 'http://example.com/img.jpg');
    });

    test('handles integer cost/sell prices (e.g. from Firestore int)', () {
      final m = ProductModel.fromJson(
          {...sampleJson, 'cost_price': 20, 'sell_price': 40}, 'p3');
      expect(m.costPriceDozenPkr, 20.0);
      expect(m.sellPriceDozenSar, 40.0);
    });
  });

  group('ProductModel.toJson', () {
    test('serialises correctly', () {
      final m = ProductModel.fromJson(sampleJson, 'p1');
      final json = m.toJson();
      expect(json['sku'], 'SKU-001');
      expect(json['name'], 'Test Shoe');
      expect(json['sell_price_dozen_sar'], 50.0);
      expect(json['stock_count'], 10);
    });

    test('round-trip preserves data', () {
      final original = ProductModel.fromJson(sampleJson, 'p1');
      final restored = ProductModel.fromJson(original.toJson(), 'p1');
      expect(restored.name, original.name);
      expect(restored.costPriceDozenPkr, original.costPriceDozenPkr);
      expect(restored.sizes, original.sizes);
    });
  });

  group('ProductModel.copyWith', () {
    test('changes name', () {
      final m = ProductModel.fromJson(sampleJson, 'p1');
      final copy = m.copyWith(name: 'New Shoe');
      expect(copy.name, 'New Shoe');
      expect(copy.sku, m.sku);
    });

    test('changes stockCount', () {
      final m = ProductModel.fromJson(sampleJson, 'p1');
      final copy = m.copyWith(stockCount: 99);
      expect(copy.stockCount, 99);
    });
  });
}
