import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/collections.dart';
import '../core/models/tenant_model.dart';
import '../core/utils/tenant_scope.dart';
import '../models/user_model.dart';
import 'auth_provider.dart';

final tenantsProvider = StreamProvider.autoDispose<List<TenantModel>>((ref) {
  final currentUser = ref.watch(authUserProvider).value;
  if (currentUser == null) return const Stream.empty();

  if (currentUser.isSuperAdmin) {
    return FirebaseFirestore.instance
        .collection(Collections.tenants)
        .orderBy('name')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => TenantModel.fromJson(doc.data(), doc.id))
              .toList(),
        );
  }

  if (!currentUser.isTenantAdmin) return const Stream.empty();
  final tenantId = TenantScope.normalize(currentUser.tenantId);
  if (tenantId == null) return const Stream.empty();

  return FirebaseFirestore.instance
      .collection(Collections.tenants)
      .where('tenant_id', isEqualTo: tenantId)
      .orderBy('name')
      .snapshots()
      .map(
        (snap) => snap.docs
            .map((doc) => TenantModel.fromJson(doc.data(), doc.id))
            .toList(),
      );
});

final tenantProvider = StreamProvider.autoDispose.family<TenantModel?, String>((
  ref,
  tenantId,
) {
  final currentUser = ref.watch(authUserProvider).value;
  if (currentUser == null) return Stream.value(null);

  if (currentUser.isSuperAdmin) {
    if (currentUser.activeWorkspaceId != tenantId) return Stream.value(null);
  } else if (!currentUser.active ||
      TenantScope.normalize(currentUser.tenantId) != tenantId) {
    return Stream.value(null);
  }

  return FirebaseFirestore.instance
      .collection(Collections.tenants)
      .doc(tenantId)
      .snapshots()
      .map((doc) {
        if (!doc.exists) return null;
        return TenantModel.fromJson(doc.data()!, doc.id);
      });
});

/// Workspace-scoped active users for ownership and account-management flows.
final tenantUsersProvider = StreamProvider.family<List<UserModel>, String>((
  ref,
  tenantId,
) {
  final currentUser = ref.watch(authUserProvider).value;
  if (currentUser == null ||
      (currentUser.isSuperAdmin
          ? currentUser.activeWorkspaceId != tenantId
          : !currentUser.isTenantAdmin ||
                TenantScope.normalize(currentUser.tenantId) != tenantId)) {
    return const Stream<List<UserModel>>.empty();
  }

  return FirebaseFirestore.instance
      .collection(Collections.users)
      .where('tenant_id', isEqualTo: tenantId)
      .where('active', isEqualTo: true)
      .orderBy('display_name')
      .snapshots()
      .map(
        (snap) => snap.docs
            .map((doc) => UserModel.fromJson(doc.data(), doc.id))
            .toList(),
      );
});

final allInactiveUsersForTenantProvider =
    StreamProvider.family<List<UserModel>, String>((ref, tenantId) {
      final currentUser = ref.watch(authUserProvider).value;
      if (currentUser == null ||
          (currentUser.isSuperAdmin
              ? currentUser.activeWorkspaceId != tenantId
              : !currentUser.isTenantAdmin ||
                    TenantScope.normalize(currentUser.tenantId) != tenantId)) {
        return const Stream<List<UserModel>>.empty();
      }

      return FirebaseFirestore.instance
          .collection(Collections.users)
          .where('tenant_id', isEqualTo: tenantId)
          .where('active', isEqualTo: false)
          .orderBy('display_name')
          .snapshots()
          .map(
            (snap) => snap.docs
                .map((doc) => UserModel.fromJson(doc.data(), doc.id))
                .toList(),
          );
    });

class TenantManagementNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  String _slugify(String value) {
    final slug = value.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '-',
    );
    return slug
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  Future<void> _runTenantWrite(Future<void> Function() operation) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(operation);
    state = result;
    if (result.hasError) {
      Error.throwWithStackTrace(
        result.error!,
        result.stackTrace ?? StackTrace.current,
      );
    }
  }

  Future<String> createTenant({
    required String name,
    required String slug,
    String? ownerUserId,
  }) async {
    final actingUser = await ref.read(authUserProvider.future);
    if (actingUser == null || !actingUser.active || !actingUser.isSuperAdmin) {
      throw StateError('Active platform super-admin access is required');
    }

    final tenantName = name.trim();
    if (tenantName.isEmpty) throw ArgumentError('Workspace name is required');
    final tenantSlug = slug.trim().isEmpty
        ? _slugify(tenantName)
        : _slugify(slug);
    final docId = tenantSlug.isEmpty
        ? 'workspace-${DateTime.now().millisecondsSinceEpoch}'
        : tenantSlug;

    await _runTenantWrite(() async {
      final db = FirebaseFirestore.instance;
      final tenantRef = db.collection(Collections.tenants).doc(docId);
      final settingsRef = db.collection(Collections.settings).doc(docId);

      await db.runTransaction<void>((transaction) async {
        final tenantSnapshot = await transaction.get(tenantRef);
        final settingsSnapshot = await transaction.get(settingsRef);
        if (tenantSnapshot.exists || settingsSnapshot.exists) {
          throw StateError('Workspace slug already exists: $docId');
        }

        transaction.set(tenantRef, {
          'name': tenantName,
          'slug': tenantSlug,
          'tenant_id': docId,
          'created_by': actingUser.id,
          'active': true,
          'is_trial': false,
          'created_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
          'owner_user_id': ownerUserId,
        });
        transaction.set(settingsRef, {
          'tenant_id': docId,
          'company_name': tenantName,
          'currency': 'SAR',
          'pairs_per_carton': 12,
          'require_admin_approval_for_seller_transaction_edits': false,
          'last_invoice_number': 0,
          'updated_at': FieldValue.serverTimestamp(),
        });
      });
    });
    return docId;
  }

  Future<void> updateTenant(
    String tenantId, {
    required String name,
    required String slug,
    String? ownerUserId,
  }) async {
    final actingUser = await ref.read(authUserProvider.future);
    if (actingUser == null ||
        !actingUser.active ||
        !actingUser.isSuperAdmin ||
        actingUser.activeWorkspaceId != tenantId) {
      throw StateError('Authorized workspace administration is required.');
    }
    final tenantName = name.trim();
    final tenantSlug = _slugify(slug);
    if (tenantName.isEmpty || tenantSlug.isEmpty) {
      throw ArgumentError('Workspace name and slug are required.');
    }
    if (ownerUserId != null) {
      await _validateTenantOwner(tenantId, ownerUserId);
    }

    await _runTenantWrite(() async {
      await FirebaseFirestore.instance
          .collection(Collections.tenants)
          .doc(tenantId)
          .update({
            'name': tenantName,
            'slug': tenantSlug,
            'tenant_id': tenantId,
            'owner_user_id': ownerUserId,
            'updated_at': FieldValue.serverTimestamp(),
          });
    });
  }

  Future<void> assignTenantOwner(String tenantId, String ownerUserId) async {
    var actingUser = await ref.read(authUserProvider.future);
    if (actingUser?.isSuperAdmin == true) {
      final authUid = FirebaseAuth.instance.currentUser?.uid;
      final snapshot = authUid == null
          ? null
          : await FirebaseFirestore.instance
                .collection(Collections.users)
                .doc(authUid)
                .get(const GetOptions(source: Source.server));
      if (snapshot?.exists == true) {
        actingUser = UserModel.fromJson(snapshot!.data()!, snapshot.id);
      }
    }
    if (actingUser == null ||
        !actingUser.active ||
        !actingUser.isSuperAdmin ||
        actingUser.activeWorkspaceId != tenantId) {
      throw StateError('Authorized workspace administration is required.');
    }
    await _validateTenantOwner(tenantId, ownerUserId);
    await _runTenantWrite(() async {
      await FirebaseFirestore.instance
          .collection(Collections.tenants)
          .doc(tenantId)
          .update({
            'owner_user_id': ownerUserId.trim(),
            'updated_at': FieldValue.serverTimestamp(),
          });
    });
  }

  Future<UserModel> _requireSelectedPlatformAdmin(
    String requestedTenantId,
  ) async {
    final tenantId = TenantScope.normalize(requestedTenantId);
    if (tenantId == null || tenantId == TenantScope.globalTenantId) {
      throw ArgumentError('A concrete workspace ID is required.');
    }
    final actingUser = await ref.read(authUserProvider.future);
    if (actingUser == null ||
        !actingUser.active ||
        !actingUser.isSuperAdmin ||
        actingUser.activeWorkspaceId != tenantId ||
        (actingUser.activeWorkspaceReason?.trim().length ?? 0) < 10) {
      throw StateError('Authorized workspace administration is required.');
    }
    return actingUser;
  }

  Future<void> archiveTenant(String tenantId) async {
    final actingUser = await _requireSelectedPlatformAdmin(tenantId);
    final normalizedTenantId = TenantScope.requireTenant(tenantId);

    await _runTenantWrite(() async {
      final db = FirebaseFirestore.instance;
      final tenantRef = db
          .collection(Collections.tenants)
          .doc(normalizedTenantId);
      await db.runTransaction<void>((transaction) async {
        final snapshot = await transaction.get(tenantRef);
        if (!snapshot.exists || snapshot.data()?['active'] != true) {
          throw StateError(
            'Workspace lifecycle status changed. Refresh and retry.',
          );
        }
        transaction.update(tenantRef, {
          'active': false,
          'archived_at': FieldValue.serverTimestamp(),
          'archived_by': actingUser.id,
          'updated_at': FieldValue.serverTimestamp(),
        });
      });
    });
  }

  Future<void> restoreTenant(String tenantId) async {
    await _requireSelectedPlatformAdmin(tenantId);
    final normalizedTenantId = TenantScope.requireTenant(tenantId);

    await _runTenantWrite(() async {
      final db = FirebaseFirestore.instance;
      final tenantRef = db
          .collection(Collections.tenants)
          .doc(normalizedTenantId);
      await db.runTransaction<void>((transaction) async {
        final snapshot = await transaction.get(tenantRef);
        if (!snapshot.exists || snapshot.data()?['active'] == true) {
          throw StateError(
            'Workspace lifecycle status changed. Refresh and retry.',
          );
        }
        transaction.update(tenantRef, {
          'active': true,
          'archived_at': FieldValue.delete(),
          'archived_by': FieldValue.delete(),
          'updated_at': FieldValue.serverTimestamp(),
        });
      });
    });
  }

  Future<void> _validateTenantOwner(String tenantId, String ownerUserId) async {
    final normalizedOwnerId = ownerUserId.trim();
    if (normalizedOwnerId.isEmpty) {
      throw ArgumentError('Workspace owner ID must not be empty.');
    }
    final owner = await FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(normalizedOwnerId)
        .get(const GetOptions(source: Source.server));
    final data = owner.data();
    if (!owner.exists ||
        data?['active'] != true ||
        data?['tenant_id'] != tenantId ||
        (data?['role'] as String?)?.trim().toLowerCase() != 'tenant_admin') {
      throw StateError(
        'Workspace owner must be an active administrator in this workspace.',
      );
    }
  }
}

final tenantManagementNotifierProvider =
    AsyncNotifierProvider<TenantManagementNotifier, void>(
      TenantManagementNotifier.new,
    );
