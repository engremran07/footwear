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
    String? ownerUserId,
  }) async {
    final tenantSlug = slug.trim().isEmpty
        ? _slugify(name)
        : slug.trim().toLowerCase();
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final now = Timestamp.now();
      final docId = tenantSlug.isEmpty
          ? 'workspace-${now.millisecondsSinceEpoch}'
          : tenantSlug;
      await FirebaseFirestore.instance
          .collection(Collections.tenants)
          .doc(docId)
          .set({
            'name': name.trim(),
            'slug': tenantSlug,
            'tenant_id': docId,
            'active': true,
            'is_trial': false,
            'require_device_pairing': requireDevicePairing,
            'allow_admin_reset_only': allowAdminResetOnly,
            'created_at': now,
            'updated_at': now,
            'owner_user_id': ownerUserId,
          }, SetOptions(merge: true));
    });
  }

  Future<void> updateTenant(
    String tenantId, {
    required String name,
    required String slug,
    required bool requireDevicePairing,
    required bool allowAdminResetOnly,
    String? ownerUserId,
  }) async {
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
