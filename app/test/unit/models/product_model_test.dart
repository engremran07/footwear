import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/product_model.dart';

void main() {
  group('ProductModel.fromJson', () {
    final ts = Timestamp.fromMillisecondsSinceEpoch(0);
    final baseJson = <String, dynamic>{
      'name': 'Classic Boot',
      'category': 'boots',
      'image_url': 'https://example.com/img.jpg',
      'active': true,
      'created_at': ts,
      'updated_at': ts,
    };

    test('parses all fields correctly', () {
      final m = ProductModel.fromJson(baseJson, 'p1');
      expect(m.id, 'p1');
      expect(m.name, 'Classic Boot');
      expect(m.category, 'boots');
      expect(m.imageUrl, 'https://example.com/img.jpg');
      expect(m.active, isTrue);
    });

    test('missing fields use defaults', () {
      final m = ProductModel.fromJson({}, 'p2');
      expect(m.name, '');
      expect(m.category, '');
      expect(m.imageUrl, isNull);
      expect(m.active, isTrue);
    });
  });

  group('ProductModel.toJson', () {
    test('round-trips through fromJson/toJson', () {
      final ts = Timestamp.fromMillisecondsSinceEpoch(1000);
      final original = ProductModel(
        id: 'p1',
        name: 'Sandal',
        category: 'sandals',
        active: true,
        createdAt: ts,
        updatedAt: ts,
      );
      final json = original.toJson();
      final restored = ProductModel.fromJson(json, 'p1');
      expect(restored.name, original.name);
      expect(restored.category, original.category);
    });
  });
}
