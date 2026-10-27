import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/collections.dart';
import '../core/models/tenant_model.dart';
import '../core/utils/firestore_pagination.dart';
import '../core/utils/permission_policy.dart';
import '../core/utils/role_names.dart';
import '../core/utils/tenant_scope.dart';
import '../models/user_model.dart';
import 'auth_provider.dart';

List<UserModel> _sortUsersByDisplayName(Iterable<UserModel> users) {
  final sorted = users.toList();
  sorted.sort((left, right) {
    final byName = left.displayName.trim().toLowerCase().compareTo(
      right.displayName.trim().toLowerCase(),
    );
    if (byName != 0) return byName;
    final byEmail = left.email.toLowerCase().compareTo(
      right.email.toLowerCase(),
    );
    return byEmail != 0 ? byEmail : left.id.compareTo(right.id);
  });
  return sorted;
}

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
final tenantUsersProvider = StreamProvider.autoDispose
    .family<List<UserModel>, String>((ref, tenantId) {
      final currentUser = ref.watch(authUserProvider).value;
      if (!PermissionPolicy.can(
        currentUser,
        AppCapability.manageUsers,
        tenantId: tenantId,
      )) {
        return const Stream<List<UserModel>>.empty();
      }

      if (currentUser!.isSuperAdmin) {
        final selectedAt = currentUser.activeWorkspaceSelectedAt!.toDate();
        final remaining = selectedAt
            .add(const Duration(hours: 8))
            .difference(DateTime.now());
        final expiryTimer = Timer(remaining, ref.invalidateSelf);
        ref.onDispose(expiryTimer.cancel);
      }

      return FirebaseFirestore.instance
          .collection(Collections.users)
          .where('tenant_id', isEqualTo: tenantId)
          .where('active', isEqualTo: true)
          .snapshots()
          .map(
            (snap) => _sortUsersByDisplayName(
              snap.docs.map((doc) => UserModel.fromJson(doc.data(), doc.id)),
            ),
          );
    });

/// Live member details shown only inside an active, audited workspace context.
final tenantWorkspaceUsersProvider = StreamProvider.autoDispose
    .family<List<UserModel>, String>((ref, tenantId) {
      final currentUser = ref.watch(authUserProvider).value;
      final normalizedTenantId = TenantScope.normalize(tenantId);
      if (currentUser == null || normalizedTenantId == null) {
        return Stream.value(const <UserModel>[]);
      }

      if (currentUser.isSuperAdmin) {
        if (!currentUser.hasActiveWorkspaceSupportContextFor(
          normalizedTenantId,
        )) {
          return Stream.value(const <UserModel>[]);
        }
        final selectedAt = currentUser.activeWorkspaceSelectedAt!.toDate();
        final remaining = selectedAt
            .add(const Duration(hours: 8))
            .difference(DateTime.now());
        if (remaining <= Duration.zero) {
          return Stream.value(const <UserModel>[]);
        }
        final expiryTimer = Timer(remaining, ref.invalidateSelf);
        ref.onDispose(expiryTimer.cancel);
      } else if (!currentUser.isTenantAdmin ||
          !currentUser.active ||
          TenantScope.normalize(currentUser.tenantId) != normalizedTenantId) {
        return Stream.value(const <UserModel>[]);
      }

      return FirebaseFirestore.instance
          .collection(Collections.users)
          .where('tenant_id', isEqualTo: normalizedTenantId)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map(
                  (document) =>
                      UserModel.fromJson(document.data(), document.id),
                )
                .toList(),
          );
    });

final allInactiveUsersForTenantProvider =
    StreamProvider.family<List<UserModel>, String>((ref, tenantId) {
      final currentUser = ref.watch(authUserProvider).value;
      if (!PermissionPolicy.can(
        currentUser,
        AppCapability.manageUsers,
        tenantId: tenantId,
      )) {
        return const Stream<List<UserModel>>.empty();
      }

      if (currentUser!.isSuperAdmin) {
        final selectedAt = currentUser.activeWorkspaceSelectedAt!.toDate();
        final remaining = selectedAt
            .add(const Duration(hours: 8))
            .difference(DateTime.now());
        final expiryTimer = Timer(remaining, ref.invalidateSelf);
        ref.onDispose(expiryTimer.cancel);
      }

      return FirebaseFirestore.instance
          .collection(Collections.users)
          .where('tenant_id', isEqualTo: tenantId)
          .where('active', isEqualTo: false)
          .snapshots()
          .map(
            (snap) => _sortUsersByDisplayName(
              snap.docs.map((doc) => UserModel.fromJson(doc.data(), doc.id)),
            ),
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
          'plan': 'free',
          'active_user_count': 0,
          'max_active_users': TenantModel.freeSeatLimit,
          'seat_count_revision': 0,
          'created_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
          'owner_user_id': ownerUserId,
        });
        transaction.set(settingsRef, {
          'tenant_id': docId,
          'currency': 'SAR',
          'pairs_per_carton': 12,
          'invoice_header': {'name_en': tenantName},
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
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw StateError('Active platform super-admin access is required.');
    }
    final profileSnapshot = await FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    if (!profileSnapshot.exists) {
      throw StateError('Active platform super-admin access is required.');
    }
    final actingUser = UserModel.fromJson(
      profileSnapshot.data()!,
      profileSnapshot.id,
    );
    if (!actingUser.hasActiveWorkspaceSupportContextFor(tenantId)) {
      throw StateError('Authorized workspace administration is required.');
    }
    return actingUser;
  }

  Future<void> reconcileWorkspaceSeatCount(String tenantId) async {
    await _requireSelectedPlatformAdmin(tenantId);
    final normalizedTenantId = TenantScope.requireTenant(tenantId);
    final db = FirebaseFirestore.instance;
    final tenantRef = db
        .collection(Collections.tenants)
        .doc(normalizedTenantId);
    final tenantSnapshot = await tenantRef.get(
      const GetOptions(source: Source.server),
    );
    final tenantData = tenantSnapshot.data();
    if (!tenantSnapshot.exists || tenantData?['active'] != true) {
      throw StateError('An active workspace is required to reconcile seats.');
    }
    final observedRevision =
        (tenantData?['seat_count_revision'] as num?)?.toInt() ?? 0;
    final usersQuery = db
        .collection(Collections.users)
        .where('tenant_id', isEqualTo: normalizedTenantId)
        .where('active', isEqualTo: true);
    final activeUsers = await fetchAllQueryDocuments(usersQuery, pageSize: 200);
    final activeUserCount = activeUsers.where((document) {
      final role = (document.data()['role'] as String? ?? '')
          .trim()
          .toLowerCase();
      return role != 'super_admin';
    }).length;

    await _runTenantWrite(() async {
      await db.runTransaction<void>((transaction) async {
        final snapshot = await transaction.get(tenantRef);
        final data = snapshot.data();
        if (!snapshot.exists || data?['active'] != true) {
          throw StateError(
            'An active workspace is required to reconcile seats.',
          );
        }
        final currentRevision =
            (data?['seat_count_revision'] as num?)?.toInt() ?? 0;
        if (currentRevision != observedRevision) {
          throw StateError('workspace_seat_count_changed_retry');
        }

        transaction.update(tenantRef, {
          'active_user_count': activeUserCount,
          'max_active_users': TenantModel.freeSeatLimit,
          'seat_count_revision': observedRevision + 1,
          'updated_at': FieldValue.serverTimestamp(),
        });
      });
    });
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
