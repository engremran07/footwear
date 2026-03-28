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
  });
}
