import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/route_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);
  final baseJson = <String, dynamic>{
    'route_number': 5,
    'name': 'North Route',
    'area': 'Industrial',
    'city': 'Jeddah',
    'description': 'Covers northern district',
    'total_shops': 12,
    'assigned_seller_id': 'seller1',
    'assigned_seller_name': 'Ali Khan',
    'active': true,
    'created_by': 'admin1',
    'created_at': ts,
    'updated_at': ts,
  };

  group('RouteModel.fromJson', () {
    test('parses all fields correctly', () {
      final m = RouteModel.fromJson(baseJson, 'r1');
      expect(m.id, 'r1');
      expect(m.routeNumber, 5);
      expect(m.name, 'North Route');
      expect(m.area, 'Industrial');
      expect(m.city, 'Jeddah');
      expect(m.description, 'Covers northern district');
      expect(m.totalShops, 12);
      expect(m.assignedSellerId, 'seller1');
      expect(m.assignedSellerName, 'Ali Khan');
      expect(m.active, isTrue);
      expect(m.createdBy, 'admin1');
    });

    test('missing fields use defaults', () {
      final m = RouteModel.fromJson({}, 'r2');
      expect(m.routeNumber, 0);
      expect(m.name, '');
      expect(m.area, isNull);
      expect(m.city, isNull);
      expect(m.description, isNull);
      expect(m.totalShops, 0);
      expect(m.assignedSellerId, isNull);
      expect(m.assignedSellerName, isNull);
      expect(m.active, isTrue);
    });
  });

  group('RouteModel.toJson', () {
    test('round-trips through fromJson/toJson', () {
      final original = RouteModel.fromJson(baseJson, 'r1');
      final json = original.toJson();
      final restored = RouteModel.fromJson(json, 'r1');
      expect(restored.routeNumber, original.routeNumber);
      expect(restored.name, original.name);
      expect(restored.area, original.area);
      expect(restored.city, original.city);
      expect(restored.totalShops, original.totalShops);
      expect(restored.assignedSellerId, original.assignedSellerId);
      expect(restored.assignedSellerName, original.assignedSellerName);
    });

    test('includes all keys', () {
      final m = RouteModel.fromJson(baseJson, 'r1');
      final json = m.toJson();
      expect(json.containsKey('route_number'), isTrue);
      expect(json.containsKey('name'), isTrue);
      expect(json.containsKey('active'), isTrue);
      expect(json.containsKey('assigned_seller_id'), isTrue);
    });
  });
}
