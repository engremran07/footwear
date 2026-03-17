import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/user_model.dart';

void main() {
  group('UserRole', () {
    test('all enum values exist', () {
      expect(UserRole.values, containsAll([
        UserRole.admin,
        UserRole.manager,
        UserRole.viewer,
        UserRole.workerPk,
        UserRole.workerKsa,
      ]));
    });
  });

  group('UserModel.fromJson', () {
    final baseJson = <String, dynamic>{
      'email': 'test@example.com',
      'display_name': 'Test User',
      'role': 'admin',
      'active': true,
      'created_at': Timestamp.fromMillisecondsSinceEpoch(0),
      'updated_at': Timestamp.fromMillisecondsSinceEpoch(0),
    };

    test('parses admin role', () {
      final m = UserModel.fromJson(baseJson, 'uid1');
      expect(m.id, 'uid1');
      expect(m.role, UserRole.admin);
      expect(m.isAdmin, isTrue);
      expect(m.isManager, isTrue);
      expect(m.canWrite, isTrue);
      expect(m.isWorker, isFalse);
    });

    test('parses manager role', () {
      final m = UserModel.fromJson({...baseJson, 'role': 'manager'}, 'uid2');
      expect(m.role, UserRole.manager);
      expect(m.isAdmin, isFalse);
      expect(m.isManager, isTrue);
      expect(m.canWrite, isTrue);
    });

    test('parses viewer role', () {
      final m = UserModel.fromJson({...baseJson, 'role': 'viewer'}, 'uid3');
      expect(m.role, UserRole.viewer);
      expect(m.isAdmin, isFalse);
      expect(m.isManager, isFalse);
      expect(m.canWrite, isFalse);
    });

    test('parses worker_pk role', () {
      final m = UserModel.fromJson({...baseJson, 'role': 'worker_pk'}, 'uid4');
      expect(m.role, UserRole.workerPk);
      expect(m.isWorker, isTrue);
    });

    test('parses worker_ksa role', () {
      final m = UserModel.fromJson({...baseJson, 'role': 'worker_ksa'}, 'uid5');
      expect(m.role, UserRole.workerKsa);
      expect(m.isWorker, isTrue);
    });

    test('unknown role defaults to viewer', () {
      final m = UserModel.fromJson({...baseJson, 'role': 'unknown_xyz'}, 'uid6');
      expect(m.role, UserRole.viewer);
    });

    test('missing fields use defaults', () {
      final m = UserModel.fromJson({'role': 'viewer'}, 'uid7');
      expect(m.email, '');
      expect(m.displayName, '');
      expect(m.active, isTrue);
    });

    test('optional workerId is null when absent', () {
      final m = UserModel.fromJson(baseJson, 'uid8');
      expect(m.workerId, isNull);
    });

    test('optional workerId is parsed when present', () {
      final m = UserModel.fromJson({...baseJson, 'worker_id': 'w1'}, 'uid9');
      expect(m.workerId, 'w1');
    });
  });

  group('UserModel.toJson', () {
    test('round-trips through fromJson/toJson', () {
      final ts = Timestamp.fromMillisecondsSinceEpoch(1000);
      final original = UserModel(
        id: 'id1',
        email: 'a@b.com',
        displayName: 'Alice',
        role: UserRole.manager,
        workerId: null,
        active: true,
        createdAt: ts,
        updatedAt: ts,
      );
      final json = original.toJson();
      final restored = UserModel.fromJson(json, 'id1');
      expect(restored.email, original.email);
      expect(restored.displayName, original.displayName);
      expect(restored.role, original.role);
      expect(restored.active, original.active);
    });

    test('all roles round-trip toJson/fromJson without loss', () {
      final ts = Timestamp.fromMillisecondsSinceEpoch(0);
      for (final role in UserRole.values) {
        final m = UserModel(
          id: 'x',
          email: 'e',
          displayName: 'd',
          role: role,
          workerId: null,
          active: true,
          createdAt: ts,
          updatedAt: ts,
        );
        final restored = UserModel.fromJson(m.toJson(), 'x');
        expect(restored.role, role,
            reason: 'Role $role did not survive round-trip');
      }
    });
  });

  group('UserModel.copyWith', () {
    final ts = Timestamp.fromMillisecondsSinceEpoch(0);
    final base = UserModel(
      id: 'id',
      email: 'orig@test.com',
      displayName: 'Orig',
      role: UserRole.viewer,
      workerId: null,
      active: true,
      createdAt: ts,
      updatedAt: ts,
    );

    test('copyWith preserves unchanged fields', () {
      final copy = base.copyWith(email: 'new@test.com');
      expect(copy.email, 'new@test.com');
      expect(copy.displayName, base.displayName);
      expect(copy.role, base.role);
    });

    test('copyWith changes role', () {
      final copy = base.copyWith(role: UserRole.admin);
      expect(copy.role, UserRole.admin);
      expect(copy.isAdmin, isTrue);
    });
  });
}
