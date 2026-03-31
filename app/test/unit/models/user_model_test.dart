import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/user_model.dart';

void main() {
  group('UserRole', () {
    test('has exactly admin and seller', () {
      expect(UserRole.values, containsAll([UserRole.admin, UserRole.seller]));
      expect(UserRole.values.length, 2);
    });
  });

  group('UserModel.fromJson', () {
    final ts = Timestamp.fromMillisecondsSinceEpoch(0);
    final baseJson = <String, dynamic>{
      'email': 'test@example.com',
      'display_name': 'Test User',
      'role': 'admin',
      'active': true,
      'created_at': ts,
      'updated_at': ts,
    };

    test('parses admin role', () {
      final m = UserModel.fromJson(baseJson, 'uid1');
      expect(m.id, 'uid1');
      expect(m.role, UserRole.admin);
      expect(m.isAdmin, isTrue);
      expect(m.isSeller, isFalse);
    });

    test('parses seller role', () {
      final m = UserModel.fromJson({...baseJson, 'role': 'seller'}, 'uid2');
      expect(m.role, UserRole.seller);
      expect(m.isAdmin, isFalse);
      expect(m.isSeller, isTrue);
    });

    test('manager maps to admin (backward compat)', () {
      final m = UserModel.fromJson({...baseJson, 'role': 'manager'}, 'uid3');
      expect(m.role, UserRole.admin);
    });

    test('unknown role defaults to seller', () {
      final m = UserModel.fromJson({...baseJson, 'role': 'xyz'}, 'uid4');
      expect(m.role, UserRole.seller);
    });

    test('missing fields use defaults', () {
      final m = UserModel.fromJson({'role': 'seller'}, 'uid5');
      expect(m.email, '');
      expect(m.displayName, '');
      expect(m.active, isTrue);
    });
  });

  group('UserModel.toJson', () {
    test('round-trips through fromJson/toJson', () {
      final ts = Timestamp.fromMillisecondsSinceEpoch(1000);
      final original = UserModel(
        id: 'id1',
        email: 'a@b.com',
        displayName: 'Alice',
        role: UserRole.admin,
        active: true,
        createdAt: ts,
        updatedAt: ts,
      );
      final json = original.toJson();
      final restored = UserModel.fromJson(json, 'id1');
      expect(restored.email, original.email);
      expect(restored.role, original.role);
    });
  });

  group('UserModel.copyWith', () {
    final ts = Timestamp.fromMillisecondsSinceEpoch(0);
    final base = UserModel(
      id: 'id',
      email: 'orig@test.com',
      displayName: 'Orig',
      role: UserRole.seller,
      active: true,
      createdAt: ts,
      updatedAt: ts,
    );

    test('copies with changed role', () {
      final copy = base.copyWith(role: UserRole.admin);
      expect(copy.role, UserRole.admin);
      expect(copy.email, base.email);
    });

    test('copies with assigned route fields', () {
      final copy = base.copyWith(
        assignedRouteId: 'route-1',
        assignedRouteName: 'North Route',
      );
      expect(copy.assignedRouteId, 'route-1');
      expect(copy.assignedRouteName, 'North Route');
      expect(copy.role, base.role);
    });

    test('copies with active toggled to false', () {
      final copy = base.copyWith(active: false);
      expect(copy.active, isFalse);
      expect(copy.id, base.id);
    });

    test('copyWith preserves identity fields when unchanged', () {
      final copy = base.copyWith(displayName: 'New Name');
      expect(copy.id, base.id);
      expect(copy.email, base.email);
      expect(copy.createdAt, base.createdAt);
    });
  });

  group('UserModel route assignment fields', () {
    final ts = Timestamp.fromMillisecondsSinceEpoch(0);

    test('seller with assigned route parses correctly', () {
      final m = UserModel.fromJson({
        'email': 'seller@test.com',
        'display_name': 'Seller',
        'role': 'seller',
        'active': true,
        'assigned_route_id': 'route-abc',
        'assigned_route_name': 'Route A',
        'created_at': ts,
        'updated_at': ts,
      }, 'seller-uid');
      expect(m.assignedRouteId, 'route-abc');
      expect(m.assignedRouteName, 'Route A');
      expect(m.isSeller, isTrue);
    });

    test('admin has no assigned route', () {
      final m = UserModel.fromJson({
        'email': 'admin@test.com',
        'display_name': 'Admin',
        'role': 'admin',
        'active': true,
        'created_at': ts,
        'updated_at': ts,
      }, 'admin-uid');
      expect(m.assignedRouteId, isNull);
      expect(m.assignedRouteName, isNull);
    });

    test('phone field parses from json', () {
      final m = UserModel.fromJson({
        'email': 'u@test.com',
        'display_name': 'User',
        'role': 'seller',
        'active': true,
        'phone': '+923001234567',
        'created_at': ts,
        'updated_at': ts,
      }, 'phone-uid');
      expect(m.phone, '+923001234567');
    });

    test('phone field defaults to null when absent', () {
      final m = UserModel.fromJson({
        'email': 'u@test.com',
        'role': 'seller',
        'active': true,
        'created_at': ts,
        'updated_at': ts,
      }, 'nophone-uid');
      expect(m.phone, isNull);
    });

    test('toJson includes phone when set', () {
      final m = UserModel(
        id: 'uid',
        email: 'u@test.com',
        displayName: 'U',
        role: UserRole.seller,
        phone: '+1234567890',
        active: true,
        createdAt: ts,
        updatedAt: ts,
      );
      final json = m.toJson();
      expect(json['phone'], '+1234567890');
    });
  });
}
