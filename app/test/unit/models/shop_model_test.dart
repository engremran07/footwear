import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/shop_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);
  final baseJson = <String, dynamic>{
    'name': 'Al-Rashid Shoes',
    'route_id': 'r1',
    'route_number': 3,
    'phone': '+966501234567',
    'address': '123 Main St',
    'area': 'Downtown',
    'city': 'Riyadh',
    'contact_name': 'Ahmed',
    'category': 'VIP',
    'balance': 1500.0,
    'notes': 'VIP customer',
    'latitude': 24.7136,
    'longitude': 46.6753,
    'active': true,
    'created_by': 'uid1',
    'created_at': ts,
    'updated_at': ts,
  };

  group('ShopModel.fromJson', () {
    test('parses all fields correctly', () {
      final m = ShopModel.fromJson(baseJson, 's1');
      expect(m.id, 's1');
      expect(m.name, 'Al-Rashid Shoes');
      expect(m.routeId, 'r1');
      expect(m.routeNumber, 3);
      expect(m.phone, '+966501234567');
      expect(m.address, '123 Main St');
      expect(m.area, 'Downtown');
      expect(m.city, 'Riyadh');
      expect(m.contactName, 'Ahmed');
      expect(m.category, 'VIP');
      expect(m.balance, 1500.0);
      expect(m.notes, 'VIP customer');
      expect(m.latitude, 24.7136);
      expect(m.longitude, 46.6753);
      expect(m.active, isTrue);
      expect(m.createdBy, 'uid1');
    });

    test('missing fields use defaults', () {
      final m = ShopModel.fromJson({}, 's2');
      expect(m.name, '');
      expect(m.routeId, '');
      expect(m.routeNumber, 0);
      expect(m.phone, isNull);
      expect(m.balance, 0);
      expect(m.active, isTrue);
    });

    test('hasLocation is true when both lat/lng present', () {
      final m = ShopModel.fromJson(baseJson, 's3');
      expect(m.hasLocation, isTrue);
    });

    test('hasLocation is false when lat/lng missing', () {
      final m = ShopModel.fromJson({}, 's4');
      expect(m.hasLocation, isFalse);
    });

    test('hasOutstanding is true when balance > 0', () {
      final m = ShopModel.fromJson(baseJson, 's5');
      expect(m.hasOutstanding, isTrue);
    });

    test('hasOutstanding is false when balance is 0', () {
      final m = ShopModel.fromJson({...baseJson, 'balance': 0}, 's6');
      expect(m.hasOutstanding, isFalse);
    });
  });

  group('ShopModel.toJson', () {
    test('round-trips through fromJson/toJson', () {
      final original = ShopModel.fromJson(baseJson, 's1');
      final json = original.toJson();
      final restored = ShopModel.fromJson(json, 's1');
      expect(restored.name, original.name);
      expect(restored.routeId, original.routeId);
      expect(restored.routeNumber, original.routeNumber);
      expect(restored.category, original.category);
      expect(restored.balance, original.balance);
    });

    test('toJson keeps category when present', () {
      final original = ShopModel.fromJson(baseJson, 's1');
      final json = original.toJson();
      expect(json['category'], equals('VIP'));
    });
  });

  group('ShopModel equality', () {
    test('two shops with same id are equal', () {
      final a = ShopModel.fromJson(baseJson, 's1');
      final b = ShopModel.fromJson({...baseJson, 'name': 'Other'}, 's1');
      expect(a, equals(b));
    });

    test('two shops with different ids are not equal', () {
      final a = ShopModel.fromJson(baseJson, 's1');
      final b = ShopModel.fromJson(baseJson, 's2');
      expect(a, isNot(equals(b)));
    });

    test('hashCode is based on id', () {
      final a = ShopModel.fromJson(baseJson, 's1');
      final b = ShopModel.fromJson(baseJson, 's1');
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('lastTransaction fields', () {
    test('fromJson parses lastTransactionType and lastTransactionAmount', () {
      final json = Map<String, dynamic>.from(baseJson)
        ..['last_transaction_type'] = 'cash_in'
        ..['last_transaction_amount'] = 1500.0;
      final shop = ShopModel.fromJson(json, 's1');
      expect(shop.lastTransactionType, equals('cash_in'));
      expect(shop.lastTransactionAmount, equals(1500.0));
    });

    test('fromJson returns null for missing lastTransaction fields', () {
      final shop = ShopModel.fromJson(baseJson, 's1');
      expect(shop.lastTransactionType, isNull);
      expect(shop.lastTransactionAmount, isNull);
    });

    test('copyWith updates category and lastTransaction fields', () {
      final shop = ShopModel.fromJson(baseJson, 's1');
      final updated = shop.copyWith(
        category: 'VIP',
        lastTransactionType: 'cash_out',
        lastTransactionAmount: 2500.0,
      );
      expect(updated.category, equals('VIP'));
      expect(updated.lastTransactionType, equals('cash_out'));
      expect(updated.lastTransactionAmount, equals(2500.0));
    });

    test(
      'copyWith preserves existing lastTransaction fields when not passed',
      () {
        final json = Map<String, dynamic>.from(baseJson)
          ..['last_transaction_type'] = 'return'
          ..['last_transaction_amount'] = 300.0;
        final shop = ShopModel.fromJson(json, 's1');
        final updated = shop.copyWith(name: 'Updated Name');
        expect(updated.lastTransactionType, equals('return'));
        expect(updated.lastTransactionAmount, equals(300.0));
      },
    );
  });
}
