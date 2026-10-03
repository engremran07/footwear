import 'package:cloud_firestore/cloud_firestore.dart';
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

final tenantProvider = StreamProvider.family<TenantModel?, String>((
  ref,
  tenantId,
) {
  final currentUser = ref.watch(authUserProvider).value;
  if (currentUser == null) return const Stream<TenantModel?>.empty();

  if (currentUser.isSuperAdmin) {
    return FirebaseFirestore.instance
        .collection(Collections.tenants)
        .doc(tenantId)
        .snapshots()
        .map((doc) {
          if (!doc.exists) return null;
          return TenantModel.fromJson(doc.data()!, doc.id);
        });
  }

  if (!currentUser.isTenantAdmin) return const Stream<TenantModel?>.empty();
  final tenantIdForUser = TenantScope.normalize(currentUser.tenantId);
  if (tenantIdForUser != tenantId) return const Stream<TenantModel?>.empty();

  return FirebaseFirestore.instance
      .collection(Collections.tenants)
      .doc(tenantId)
      .snapshots()
      .map((doc) {
        if (!doc.exists) return null;
        return TenantModel.fromJson(doc.data()!, doc.id);
      });
});

/// Workspace-scoped users (admin + sellers) for the enhanced users management screen.
/// Super admin can select any workspace; tenant_admin sees only their workspace.
/// No role filtering — context is implicit from the workspace selection.
final tenantUsersProvider = StreamProvider.family<List<UserModel>, String>((
  ref,
  tenantId,
) {
  final currentUser = ref.watch(authUserProvider).value;
  if (currentUser == null) return const Stream<List<UserModel>>.empty();

  if (currentUser.isSuperAdmin) {
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
  }

  if (!currentUser.isTenantAdmin) return const Stream<List<UserModel>>.empty();
  final tenantIdForUser = TenantScope.normalize(currentUser.tenantId);
  if (tenantIdForUser != tenantId) return const Stream<List<UserModel>>.empty();

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

/// Inactive users for a specific workspace (super admin or tenant admin only)
final allInactiveUsersForTenantProvider =
    StreamProvider.family<List<UserModel>, String>((ref, tenantId) {
      final currentUser = ref.watch(authUserProvider).value;
      if (currentUser == null) return const Stream<List<UserModel>>.empty();

      if (currentUser.isSuperAdmin) {
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
      }

      if (!currentUser.isTenantAdmin) {
        return const Stream<List<UserModel>>.empty();
      }
      final tenantIdForUser = TenantScope.normalize(currentUser.tenantId);
      if (tenantIdForUser != tenantId) {
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
    final compact = value.trim().toLowerCase();
    final slug = compact.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return slug
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  Future<void> createTenant({
    required String name,
    required String slug,
    required bool requireDevicePairing,
    required bool allowAdminResetOnly,
    required int maxDevicesAllowed,
    String? ownerUserId,
  }) async {
    final actingUser = await ref.read(authUserProvider.future);
    if (actingUser == null || !actingUser.active || !actingUser.isSuperAdmin) {
      throw StateError('Active platform super-admin access is required');
    }
    final tenantSlug = slug.trim().isEmpty
        ? _slugify(name)
        : slug.trim().toLowerCase();
    if (name.trim().isEmpty) throw ArgumentError('Workspace name is required');
    final normalizedLimit = maxDevicesAllowed.clamp(1, 999);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final docId = tenantSlug.isEmpty
          ? 'workspace-${DateTime.now().millisecondsSinceEpoch}'
          : tenantSlug;
      final db = FirebaseFirestore.instance;
      final tenantRef = db.collection(Collections.tenants).doc(docId);
      final settingsRef = db.collection(Collections.settings).doc(docId);
      await db.runTransaction<void>((transaction) async {
        final tenantSnapshot = await transaction.get(tenantRef);
        final settingsSnapshot = await transaction.get(settingsRef);
        if (tenantSnapshot.exists) {
          throw StateError('Workspace slug already exists: $docId');
        }
        if (settingsSnapshot.exists) {
          throw StateError('Workspace settings already exist: $docId');
        }
        transaction.set(tenantRef, {
          'name': name.trim(),
          'slug': tenantSlug,
          'tenant_id': docId,
          'created_by': actingUser.id,
          'active': true,
          'is_trial': false,
          'require_device_pairing': requireDevicePairing,
          'allow_admin_reset_only': allowAdminResetOnly,
          'max_devices_allowed': normalizedLimit,
          'created_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
          'owner_user_id': ownerUserId,
        });
        transaction.set(settingsRef, {
          'tenant_id': docId,
          'company_name': name.trim(),
          'currency': 'SAR',
          'pairs_per_carton': 12,
          'require_admin_approval_for_seller_transaction_edits': false,
          'last_invoice_number': 0,
          'updated_at': FieldValue.serverTimestamp(),
        });
      });
    });
  }

  Future<void> updateTenant(
    String tenantId, {
    required String name,
    required String slug,
    required bool requireDevicePairing,
    required bool allowAdminResetOnly,
    required int maxDevicesAllowed,
    String? ownerUserId,
  }) async {
    final normalizedLimit = maxDevicesAllowed.clamp(1, 999);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await FirebaseFirestore.instance
          .collection(Collections.tenants)
          .doc(tenantId)
          .set({
            'name': name.trim(),
            'slug': slug.trim().toLowerCase(),
            'tenant_id': tenantId,
            'require_device_pairing': requireDevicePairing,
            'allow_admin_reset_only': allowAdminResetOnly,
            'max_devices_allowed': normalizedLimit,
            'owner_user_id': ownerUserId,
            'updated_at': Timestamp.now(),
          }, SetOptions(merge: true));
    });
  }
}

final tenantManagementNotifierProvider =
    AsyncNotifierProvider<TenantManagementNotifier, void>(
      TenantManagementNotifier.new,
    );
