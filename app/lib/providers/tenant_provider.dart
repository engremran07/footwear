import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

import '../core/constants/collections.dart';
import '../core/models/access_usage_summary.dart';
import '../core/models/tenant_model.dart';
import '../core/models/workspace_admin_access_policy.dart';
import '../core/services/device_installation.dart';
import '../core/utils/session_access_policy.dart';
import '../core/utils/tenant_scope.dart';
import '../models/device_registration_model.dart';
import '../models/session_model.dart';
import '../models/user_model.dart';
import 'auth_provider.dart';

final logger = Logger();

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
    return FirebaseFirestore.instance
        .collection(Collections.tenants)
        .doc(tenantId)
        .snapshots()
        .map((doc) {
          if (!doc.exists) return null;
          return TenantModel.fromJson(doc.data()!, doc.id);
        });
  }

  final tenantIdForUser = TenantScope.normalize(currentUser.tenantId);
  if (!currentUser.active || tenantIdForUser != tenantId) {
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
    if (currentUser.activeWorkspaceId != tenantId) {
      return Stream.value(const <UserModel>[]);
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
        if (currentUser.activeWorkspaceId != tenantId) {
          return Stream.value(const <UserModel>[]);
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

final userSessionsProvider = StreamProvider.autoDispose
    .family<List<SessionModel>, String>((ref, userId) {
      final (currentUserId, currentTenantId) = ref.watch(
        authUserProvider.select(
          (userState) => (
            userState.value?.id,
            TenantScope.normalize(userState.value?.tenantId),
          ),
        ),
      );
      if (currentUserId == null || currentTenantId == null) {
        return Stream.value(const <SessionModel>[]);
      }

      return FirebaseFirestore.instance
          .collection(Collections.users)
          .doc(userId)
          .collection(Collections.sessions)
          .where('tenant_id', isEqualTo: currentTenantId)
          .where('user_id', isEqualTo: userId)
          .limit(AccessUsageSummary.maximumSlotsPerUser)
          .snapshots()
          .map(
            (snap) => snap.docs
                .map((doc) => SessionModel.fromJson(doc.data(), doc.id))
                .toList(),
          );
    });

final platformSessionsProvider = StreamProvider.autoDispose<List<SessionModel>>(
  (ref) {
    final user = ref.watch(authUserProvider).value;
    if (user == null || !user.isSuperAdmin || !user.active) {
      return Stream.value(const <SessionModel>[]);
    }
    return FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(user.id)
        .collection(Collections.platformSessions)
        .where('user_id', isEqualTo: user.id)
        .limit(SessionAccessPolicy.platformMaxDevicesAllowed)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => SessionModel.fromJson(doc.data(), doc.id))
              .toList(),
        );
  },
);

final deviceRegistrationsProvider = StreamProvider.autoDispose
    .family<List<DeviceRegistrationModel>, String>((ref, userId) {
      final currentUser = ref.watch(authUserProvider).value;
      final tenantId = TenantScope.normalize(currentUser?.tenantId);
      if (currentUser == null || tenantId == null) {
        return Stream.value(const <DeviceRegistrationModel>[]);
      }
      return FirebaseFirestore.instance
          .collection(Collections.users)
          .doc(userId)
          .collection(Collections.deviceRegistrations)
          .where('tenant_id', isEqualTo: tenantId)
          .where('user_id', isEqualTo: userId)
          .limit(AccessUsageSummary.maximumSlotsPerUser)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map(
                  (doc) => DeviceRegistrationModel.fromJson(doc.data(), doc.id),
                )
                .toList(),
          );
    });

final tenantDeviceRegistryProvider =
    StreamProvider.family<List<DeviceRegistrationModel>, String>((
      ref,
      tenantId,
    ) {
      final currentUser = ref.watch(authUserProvider).value;
      if (currentUser == null ||
          (!currentUser.isSuperAdmin && currentUser.tenantId != tenantId) ||
          (currentUser.isSuperAdmin &&
              currentUser.activeWorkspaceId != tenantId)) {
        return const Stream<List<DeviceRegistrationModel>>.empty();
      }
      return FirebaseFirestore.instance
          .collectionGroup(Collections.deviceRegistrations)
          .where('tenant_id', isEqualTo: tenantId)
          .limit(200)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map(
                  (doc) => DeviceRegistrationModel.fromJson(doc.data(), doc.id),
                )
                .toList(),
          );
    });

final tenantSessionRegistryProvider =
    StreamProvider.family<List<SessionModel>, String>((ref, tenantId) {
      final currentUser = ref.watch(authUserProvider).value;
      if (currentUser == null ||
          (!currentUser.isSuperAdmin && currentUser.tenantId != tenantId) ||
          (currentUser.isSuperAdmin &&
              currentUser.activeWorkspaceId != tenantId)) {
        return const Stream<List<SessionModel>>.empty();
      }
      return FirebaseFirestore.instance
          .collectionGroup(Collections.sessions)
          .where('tenant_id', isEqualTo: tenantId)
          .limit(200)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((doc) => SessionModel.fromJson(doc.data(), doc.id))
                .toList(),
          );
    });

final currentDeviceInstallationProvider =
    FutureProvider<DeviceInstallationMetadata>(
      (ref) => DeviceInstallation.current(),
    );

final workspaceAdminAccessPolicyProvider = StreamProvider.autoDispose
    .family<WorkspaceAdminAccessPolicy, String>((ref, userId) {
      final user = ref.watch(authUserProvider).value;
      if (user == null || !user.active || !user.isAdmin) {
        return Stream.value(const WorkspaceAdminAccessPolicy());
      }
      return FirebaseFirestore.instance
          .collection(Collections.settings)
          .doc(WorkspaceAdminAccessPolicy.documentId)
          .snapshots()
          .map(
            (snapshot) => WorkspaceAdminAccessPolicy.fromJson(snapshot.data()),
          );
    });

class WorkspaceAdminAccessPolicyNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> updatePolicy({
    required int maxDevicesAllowed,
    required int maxActiveSessionsAllowed,
  }) async {
    if (maxDevicesAllowed < 1 ||
        maxDevicesAllowed > AccessUsageSummary.maximumSlotsPerUser ||
        maxActiveSessionsAllowed < 1 ||
        maxActiveSessionsAllowed > AccessUsageSummary.maximumSlotsPerUser) {
      throw ArgumentError('Access limits must be between 1 and 10.');
    }
    final user = await ref.read(authUserProvider.future);
    if (user == null || !user.active || !user.isSuperAdmin) {
      throw StateError('Active platform super-admin access is required.');
    }
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      await FirebaseFirestore.instance
          .collection(Collections.settings)
          .doc(WorkspaceAdminAccessPolicy.documentId)
          .set({
            'workspace_admin_max_devices_allowed': maxDevicesAllowed,
            'workspace_admin_max_active_sessions_allowed':
                maxActiveSessionsAllowed,
            'updated_by': user.id,
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    });
    state = result;
    if (result.hasError) {
      Error.throwWithStackTrace(
        result.error!,
        result.stackTrace ?? StackTrace.current,
      );
    }
  }
}

final workspaceAdminAccessPolicyNotifierProvider =
    AsyncNotifierProvider<WorkspaceAdminAccessPolicyNotifier, void>(
      WorkspaceAdminAccessPolicyNotifier.new,
    );

final activeSessionCountProvider = Provider.family<AsyncValue<int>, String>(
  (ref, userId) => ref
      .watch(userSessionsProvider(userId))
      .whenData(
        (sessions) => sessions
            .where((session) => session.status == 'active')
            .where(
              (session) =>
                  session.expiresAt?.toDate().isAfter(DateTime.now()) ?? false,
            )
            .length,
      ),
);

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

  void _validateAccessLimits(int devices, int sessions) {
    if (devices < 1 || devices > AccessUsageSummary.maximumSlotsPerUser) {
      throw ArgumentError.value(
        devices,
        'maxDevicesAllowed',
        'Must be between 1 and ${AccessUsageSummary.maximumSlotsPerUser}.',
      );
    }
    if (sessions < 1 || sessions > AccessUsageSummary.maximumSlotsPerUser) {
      throw ArgumentError.value(
        sessions,
        'maxActiveSessionsAllowed',
        'Must be between 1 and ${AccessUsageSummary.maximumSlotsPerUser}.',
      );
    }
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

  Future<void> createTenant({
    required String name,
    required String slug,
    required bool requireDevicePairing,
    required bool allowAdminResetOnly,
    required int maxDevicesAllowed,
    required int maxActiveSessionsAllowed,
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

    _validateAccessLimits(maxDevicesAllowed, maxActiveSessionsAllowed);
    final normalizedLimit = maxDevicesAllowed;
    final normalizedSessionLimit = maxActiveSessionsAllowed;

    await _runTenantWrite(() async {
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
          'max_active_sessions_allowed': normalizedSessionLimit,
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
    required int maxActiveSessionsAllowed,
    String? ownerUserId,
  }) async {
    final actingUser = await ref.read(authUserProvider.future);
    final canManage =
        actingUser != null &&
        actingUser.active &&
        actingUser.isSuperAdmin &&
        actingUser.activeWorkspaceId == tenantId;
    if (!canManage) {
      throw StateError('Authorized workspace administration is required.');
    }
    _validateAccessLimits(maxDevicesAllowed, maxActiveSessionsAllowed);
    final normalizedLimit = maxDevicesAllowed;
    final normalizedSessionLimit = maxActiveSessionsAllowed;

    await _runTenantWrite(() async {
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
            'max_active_sessions_allowed': normalizedSessionLimit,
            'owner_user_id': ownerUserId,
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    });
  }

  Future<void> updateTenantAccessLimits(
    String tenantId, {
    required int maxDevicesAllowed,
    required int maxActiveSessionsAllowed,
  }) async {
    final actingUser = await ref.read(authUserProvider.future);
    final canManage =
        actingUser != null &&
        actingUser.active &&
        ((actingUser.isSuperAdmin &&
                actingUser.activeWorkspaceId == tenantId) ||
            (actingUser.isTenantAdmin && actingUser.tenantId == tenantId));
    if (!canManage) {
      throw StateError('Workspace access policy administration is required.');
    }
    _validateAccessLimits(maxDevicesAllowed, maxActiveSessionsAllowed);
    await _runTenantWrite(() async {
      await FirebaseFirestore.instance
          .collection(Collections.tenants)
          .doc(tenantId)
          .update({
            'max_devices_allowed': maxDevicesAllowed,
            'max_active_sessions_allowed': maxActiveSessionsAllowed,
            'updated_at': FieldValue.serverTimestamp(),
          });
    });
  }
}

class SessionManagementNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<UserModel?> _currentProfileFor(String userId) async {
    if (FirebaseAuth.instance.currentUser?.uid != userId) return null;
    final profile = await FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(userId)
        .get(const GetOptions(source: Source.server));
    if (FirebaseAuth.instance.currentUser?.uid != userId || !profile.exists) {
      return null;
    }
    return UserModel.fromJson(profile.data()!, profile.id);
  }

  Future<SessionModel> registerCurrentAccess({
    required String userId,
    required String tenantId,
    bool isRenewal = false,
  }) async {
    final currentUser = await _currentProfileFor(userId);
    final tenantMatches =
        currentUser != null &&
        (currentUser.isSuperAdmin
            ? currentUser.activeWorkspaceId == tenantId
            : currentUser.tenantId == tenantId);
    if (currentUser == null ||
        !currentUser.active ||
        currentUser.id != userId ||
        !tenantMatches) {
      throw StateError('Active workspace access is required.');
    }

    final metadata = await DeviceInstallation.current();
    final db = FirebaseFirestore.instance;
    final tenantRef = db.collection(Collections.tenants).doc(tenantId);
    final userRef = db.collection(Collections.users).doc(userId);
    final deviceRefs = List.generate(
      AccessUsageSummary.maximumSlotsPerUser,
      (index) => userRef
          .collection(Collections.deviceRegistrations)
          .doc('slot_$index'),
    );
    final sessionRefs = List.generate(
      AccessUsageSummary.maximumSlotsPerUser,
      (index) => userRef.collection(Collections.sessions).doc('slot_$index'),
    );
    final isWorkspaceAdmin = currentUser.isAdmin && !currentUser.isSuperAdmin;
    final workspaceAdminPolicyRef = db
        .collection(Collections.settings)
        .doc(WorkspaceAdminAccessPolicy.documentId);

    state = const AsyncLoading();
    try {
      final session = await db.runTransaction<SessionModel>((
        transaction,
      ) async {
        final tenantSnapshot = await transaction.get(tenantRef);
        if (!tenantSnapshot.exists) {
          throw StateError('Workspace policy unavailable.');
        }
        final tenant = TenantModel.fromJson(
          tenantSnapshot.data()!,
          tenantSnapshot.id,
        );
        final adminPolicySnapshot = isWorkspaceAdmin
            ? await transaction.get(workspaceAdminPolicyRef)
            : null;
        final adminPolicy = WorkspaceAdminAccessPolicy.fromJson(
          adminPolicySnapshot?.data(),
        );
        final maxDeviceSlots = isWorkspaceAdmin
            ? adminPolicy.maxDevicesAllowed
            : tenant.maxDevicesAllowed;
        final maxSessionSlots = isWorkspaceAdmin
            ? adminPolicy.maxActiveSessionsAllowed
            : tenant.maxActiveSessionsAllowed;
        final deviceSnapshots =
            await Future.wait<DocumentSnapshot<Map<String, dynamic>>?>(
              deviceRefs.map((deviceRef) => transaction.get(deviceRef)),
            );
        for (var index = 0; index < deviceSnapshots.length; index++) {
          final snapshot = deviceSnapshots[index];
          if (snapshot?.exists != true) continue;
          final data = snapshot!.data();
          if (data?['user_id'] != userId ||
              data?['tenant_id'] != tenantId ||
              data?['slot_id'] != snapshot.id ||
              (data?['slot_number'] as num?)?.toInt() != index) {
            throw StateError('invalid-device-slot-record');
          }
        }
        final sessionSnapshots =
            await Future.wait<DocumentSnapshot<Map<String, dynamic>>?>(
              sessionRefs.map((sessionRef) => transaction.get(sessionRef)),
            );
        for (var index = 0; index < sessionSnapshots.length; index++) {
          final snapshot = sessionSnapshots[index];
          if (snapshot?.exists != true) continue;
          final data = snapshot!.data();
          if (data?['user_id'] != userId ||
              data?['tenant_id'] != tenantId ||
              data?['slot_id'] != snapshot.id ||
              (data?['slot_number'] as num?)?.toInt() != index) {
            throw StateError('invalid-session-slot-record');
          }
        }

        final now = DateTime.now();
        final staleDeviceCutoff = now.subtract(const Duration(days: 30));
        final occupiedDevices = deviceSnapshots.where((snapshot) {
          final data = snapshot?.data();
          if (data?['status'] == 'pending') return true;
          if (data?['status'] != 'active') return false;
          final lastSeenAt = data?['last_seen_at'];
          return lastSeenAt is! Timestamp ||
              lastSeenAt.toDate().isAfter(staleDeviceCutoff);
        }).toList();
        final existingDeviceIndex = deviceSnapshots.indexWhere(
          (snapshot) =>
              snapshot?.data()?['status'] == 'active' &&
              snapshot?.data()?['device_id'] == metadata.installationId,
        );
        final pendingDeviceIndex = deviceSnapshots.indexWhere(
          (snapshot) =>
              snapshot?.data()?['status'] == 'pending' &&
              snapshot?.data()?['device_id'] == metadata.installationId,
        );
        if (pendingDeviceIndex >= 0) {
          return _pendingSession(
            userId,
            tenantId,
            metadata,
            pendingDeviceIndex,
          );
        }
        final blockedDeviceIndex = deviceSnapshots.indexWhere(
          (snapshot) =>
              snapshot?.data()?['status'] == 'blocked' &&
              snapshot?.data()?['device_id'] == metadata.installationId,
        );
        if (blockedDeviceIndex >= 0) throw StateError('device-blocked');
        final revokedDeviceIndex = deviceSnapshots.indexWhere(
          (snapshot) =>
              snapshot?.data()?['status'] == 'revoked' &&
              snapshot?.data()?['device_id'] == metadata.installationId,
        );
        if (SessionAccessPolicy.shouldRejectRevokedAccessDuringRenewal(
          isRenewal: isRenewal,
          hasRevokedRecord: revokedDeviceIndex >= 0,
        )) {
          throw StateError('device-session-revoked');
        }
        if (revokedDeviceIndex >= 0 &&
            (tenant.allowAdminResetOnly || isWorkspaceAdmin)) {
          throw StateError('device-admin-reset-required');
        }
        final staleDeviceIndex = deviceSnapshots.indexWhere((snapshot) {
          final data = snapshot?.data();
          final lastSeenAt = data?['last_seen_at'];
          return data?['status'] == 'active' &&
              lastSeenAt is Timestamp &&
              !lastSeenAt.toDate().isAfter(staleDeviceCutoff);
        });
        final deviceIndex = existingDeviceIndex >= 0
            ? existingDeviceIndex
            : revokedDeviceIndex >= 0
            ? revokedDeviceIndex
            : staleDeviceIndex >= 0
            ? staleDeviceIndex
            : _firstReusableDeviceSlot(
                deviceSnapshots,
                maxDeviceSlots,
                now: now,
                allowRevoked: !tenant.allowAdminResetOnly,
              );
        if (existingDeviceIndex < 0 &&
            (occupiedDevices.length >= maxDeviceSlots || deviceIndex < 0)) {
          throw StateError('device-limit-reached');
        }

        final deviceRef = deviceRefs[deviceIndex];
        final deviceSnapshot = deviceSnapshots[deviceIndex];
        final isStaleDevice =
            deviceSnapshot?.data()?['status'] == 'active' &&
            (deviceSnapshot?.data()?['last_seen_at'] is Timestamp) &&
            !(deviceSnapshot!.data()!['last_seen_at'] as Timestamp)
                .toDate()
                .isAfter(staleDeviceCutoff);
        final requiresApproval = SessionAccessPolicy.requiresDeviceApproval(
          pairingRequired: tenant.requireDevicePairing,
          hasActiveDevice: existingDeviceIndex >= 0 && !isStaleDevice,
        );
        final deviceData = {
          'user_id': userId,
          'tenant_id': tenantId,
          'slot_id': deviceRef.id,
          'slot_number': deviceIndex,
          'device_id': metadata.installationId,
          'brand': metadata.brand,
          'model': metadata.model,
          'platform': metadata.platform,
          'os_version': metadata.osVersion,
          'app_version': metadata.appVersion,
          'status': requiresApproval ? 'pending' : 'active',
          'last_seen_at': FieldValue.serverTimestamp(),
        };
        if (deviceSnapshot == null ||
            !deviceSnapshot.exists ||
            deviceSnapshot.data()?['status'] != 'active' ||
            isStaleDevice) {
          transaction.set(deviceRef, {
            ...deviceData,
            'registered_at': FieldValue.serverTimestamp(),
          });
        } else {
          transaction.update(deviceRef, {
            'last_seen_at': FieldValue.serverTimestamp(),
            'app_version': metadata.appVersion,
          });
        }

        if (requiresApproval) {
          return _pendingSession(userId, tenantId, metadata, deviceIndex);
        }

        final hasRevokedDeviceSession = sessionSnapshots.any(
          (snapshot) =>
              snapshot?.data()?['device_id'] == metadata.installationId &&
              snapshot?.data()?['status'] == 'revoked',
        );
        if (SessionAccessPolicy.shouldRejectRevokedAccessDuringRenewal(
          isRenewal: isRenewal,
          hasRevokedRecord: hasRevokedDeviceSession,
        )) {
          throw StateError('session-revoked');
        }

        final activeSessions = <int>[];
        var existingSessionIndex = -1;
        for (var index = 0; index < sessionSnapshots.length; index++) {
          final data = sessionSnapshots[index]?.data();
          if (data?['status'] != 'active') continue;
          final expiresAt = data?['expires_at'];
          if (expiresAt is Timestamp && expiresAt.toDate().isAfter(now)) {
            activeSessions.add(index);
            if (data?['device_id'] == metadata.installationId) {
              existingSessionIndex = index;
            }
          }
        }

        var sessionIndex = existingSessionIndex;
        if (sessionIndex < 0) {
          if (activeSessions.length >= maxSessionSlots) {
            throw StateError('session-limit-reached');
          }
          sessionIndex = _firstReusableSessionSlot(
            sessionSnapshots,
            maxSessionSlots,
            now,
          );
          if (sessionIndex < 0) throw StateError('session-limit-reached');
        }

        final sessionRef = sessionRefs[sessionIndex];
        final priorSession = sessionSnapshots[sessionIndex]?.data();
        final sessionId = existingSessionIndex >= 0
            ? (priorSession?['session_id'] as String? ?? sessionRef.id)
            : const Uuid().v4();
        final sessionData = {
          'user_id': userId,
          'tenant_id': tenantId,
          'slot_id': sessionRef.id,
          'slot_number': sessionIndex,
          'device_slot_id': deviceRef.id,
          'session_id': sessionId,
          'device_id': metadata.installationId,
          'device_brand': metadata.brand,
          'device_model': metadata.model,
          'platform': metadata.platform,
          'status': 'active',
          'last_seen_at': FieldValue.serverTimestamp(),
          'expires_at': Timestamp.fromDate(
            now.add(const Duration(hours: 7, minutes: 50)),
          ),
        };
        if (existingSessionIndex >= 0) {
          transaction.update(sessionRef, {
            'device_slot_id': deviceRef.id,
            'last_seen_at': FieldValue.serverTimestamp(),
            'expires_at': sessionData['expires_at'],
          });
        } else {
          transaction.set(sessionRef, {
            ...sessionData,
            'created_at': FieldValue.serverTimestamp(),
          });
        }
        final localNow = Timestamp.now();
        final createdAt = priorSession?['created_at'] as Timestamp? ?? localNow;
        return SessionModel.fromPendingWriteData(
          {...sessionData, 'created_at': createdAt},
          sessionRef.id,
          createdAt: createdAt,
          lastSeenAt: localNow,
        );
      });
      if (session.status != 'pending') {
        final deviceSlotId = SessionAccessPolicy.deviceSlotIdForSession(
          session,
          deviceId: metadata.installationId,
        );
        if (deviceSlotId == null) {
          throw StateError('device-session-mismatch');
        }
        final committedDevice = await userRef
            .collection(Collections.deviceRegistrations)
            .doc(deviceSlotId)
            .get(const GetOptions(source: Source.server));
        if (!committedDevice.exists ||
            committedDevice.data()?['device_id'] != metadata.installationId) {
          throw StateError('device-session-mismatch');
        }
        final serverSeenAt = committedDevice.data()?['last_seen_at'];
        if (serverSeenAt is Timestamp &&
            SessionAccessPolicy.isClockSkewed(
              deviceNow: DateTime.now(),
              serverNow: serverSeenAt.toDate(),
            )) {
          try {
            await terminateCurrentSession(userId);
          } catch (cleanupError) {
            logger.w('Clock-skew session rollback failed: $cleanupError');
          }
          throw StateError('device-clock-skew');
        }
      }
      state = const AsyncData(null);
      return session;
    } catch (error, stack) {
      state = AsyncError(error, stack);
      rethrow;
    }
  }

  Future<SessionModel> registerPlatformSession({
    required String userId,
    bool isRenewal = false,
  }) async {
    final user = await _currentProfileFor(userId);
    if (user == null ||
        !user.active ||
        !user.isSuperAdmin ||
        user.id != userId) {
      throw StateError('Active platform access is required.');
    }
    final metadata = await DeviceInstallation.current();
    final userRef = FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(userId);
    final collection = userRef.collection(Collections.platformSessions);
    final sessionRefs = List.generate(
      SessionAccessPolicy.platformMaxDevicesAllowed,
      (index) => collection.doc('slot_$index'),
    );
    return FirebaseFirestore.instance.runTransaction<SessionModel>((
      transaction,
    ) async {
      final snapshots = await Future.wait(sessionRefs.map(transaction.get));
      for (var index = 0; index < snapshots.length; index++) {
        final snapshot = snapshots[index];
        if (!snapshot.exists) continue;
        final data = snapshot.data();
        if (data?['user_id'] != userId ||
            data?['slot_id'] != snapshot.id ||
            (data?['slot_number'] as num?)?.toInt() != index) {
          throw StateError('invalid-platform-session-slot');
        }
      }

      final now = DateTime.now();
      final activeIndex = snapshots.indexWhere((snapshot) {
        final data = snapshot.data();
        final expiresAt = data?['expires_at'];
        return data?['device_id'] == metadata.installationId &&
            data?['status'] == 'active' &&
            expiresAt is Timestamp &&
            expiresAt.toDate().isAfter(now);
      });
      final activeSessionCount = snapshots.where((snapshot) {
        final data = snapshot.data();
        final expiresAt = data?['expires_at'];
        return data?['status'] == 'active' &&
            expiresAt is Timestamp &&
            expiresAt.toDate().isAfter(now);
      }).length;
      if (activeIndex < 0 &&
          activeSessionCount >=
              SessionAccessPolicy.platformMaxActiveSessionsAllowed) {
        throw StateError('platform-session-limit-reached');
      }
      final revokedIndex = snapshots.indexWhere(
        (snapshot) =>
            snapshot.data()?['device_id'] == metadata.installationId &&
            snapshot.data()?['status'] == 'revoked',
      );
      if (SessionAccessPolicy.shouldRejectRevokedAccessDuringRenewal(
        isRenewal: isRenewal,
        hasRevokedRecord: revokedIndex >= 0,
      )) {
        throw StateError('session-revoked');
      }
      var slotIndex = activeIndex;
      if (slotIndex < 0) {
        if (isRenewal && revokedIndex >= 0) {
          throw StateError('session-revoked');
        }
        slotIndex = revokedIndex >= 0
            ? revokedIndex
            : snapshots.indexWhere((snapshot) {
                final data = snapshot.data();
                final expiresAt = data?['expires_at'];
                return !snapshot.exists ||
                    data?['status'] == 'revoked' ||
                    (expiresAt is Timestamp &&
                        !expiresAt.toDate().isAfter(now));
              });
        if (slotIndex < 0) throw StateError('platform-device-limit-reached');
      }

      final sessionRef = sessionRefs[slotIndex];
      final previousData = snapshots[slotIndex].data();
      final sessionId = activeIndex >= 0
          ? (previousData?['session_id'] as String? ?? sessionRef.id)
          : const Uuid().v4();
      final sessionData = {
        'user_id': userId,
        'slot_id': sessionRef.id,
        'slot_number': slotIndex,
        'session_id': sessionId,
        'device_id': metadata.installationId,
        'device_brand': metadata.brand,
        'device_model': metadata.model,
        'platform': metadata.platform,
        'status': 'active',
        'last_seen_at': FieldValue.serverTimestamp(),
        'expires_at': Timestamp.fromDate(
          now.add(const Duration(hours: 7, minutes: 50)),
        ),
      };
      if (activeIndex >= 0) {
        transaction.update(sessionRef, {
          'last_seen_at': sessionData['last_seen_at'],
          'expires_at': sessionData['expires_at'],
        });
      } else {
        transaction.set(sessionRef, {
          ...sessionData,
          'created_at': FieldValue.serverTimestamp(),
        });
      }
      final localNow = Timestamp.now();
      final createdAt = previousData?['created_at'] as Timestamp? ?? localNow;
      return SessionModel.fromPendingWriteData(
        {...sessionData, 'tenant_id': 'platform', 'created_at': createdAt},
        sessionRef.id,
        createdAt: createdAt,
        lastSeenAt: localNow,
      );
    });
  }

  Future<void> terminatePlatformSession(String userId, String sessionId) async {
    final user = await ref.read(authUserProvider.future);
    if (user == null ||
        !user.active ||
        !user.isSuperAdmin ||
        user.id != userId) {
      throw StateError('Active platform access is required.');
    }
    final sessionRef = FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(userId)
        .collection(Collections.platformSessions)
        .doc(sessionId);
    final session = await sessionRef.get();
    if (!session.exists || session.data()?['user_id'] != userId) {
      throw StateError('Platform session not found.');
    }
    await sessionRef.update({
      'status': 'revoked',
      'revoked_at': FieldValue.serverTimestamp(),
      'terminated_by': user.id,
    });
  }

  Future<void> terminateCurrentPlatformSession(String userId) async {
    final user = await ref.read(authUserProvider.future);
    if (user == null || user.id != userId || !user.isSuperAdmin) return;
    final metadata = await DeviceInstallation.current();
    final sessions = await FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(userId)
        .collection(Collections.platformSessions)
        .where('user_id', isEqualTo: userId)
        .limit(20)
        .get(const GetOptions(source: Source.server));
    final currentSession = sessions.docs.where(
      (doc) =>
          doc.data()['device_id'] == metadata.installationId &&
          doc.data()['status'] == 'active',
    );
    if (currentSession.isEmpty) return;
    await terminatePlatformSession(userId, currentSession.first.id);
  }

  Future<void> terminateSession(
    String userId,
    String slotId, {
    String? reason,
  }) async {
    final currentUser = await ref.read(authUserProvider.future);
    if (currentUser == null || !currentUser.active) {
      throw StateError('Not authenticated');
    }
    final sessionRef = FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(userId)
        .collection(Collections.sessions)
        .doc(slotId);
    final snapshot = await sessionRef.get();
    final session = SessionModel.fromJson(
      snapshot.data() ?? <String, dynamic>{},
      snapshot.id,
    );
    final isOwner = currentUser.id == userId;
    final isWorkspaceAdmin = currentUser.isSuperAdmin
        ? currentUser.activeWorkspaceId == session.tenantId
        : (currentUser.isAdmin || currentUser.isTenantAdmin) &&
              currentUser.tenantId == session.tenantId;
    if (!snapshot.exists || (!isOwner && !isWorkspaceAdmin)) {
      throw StateError('Permission denied');
    }
    await sessionRef.update({
      'status': 'revoked',
      'revoked_at': FieldValue.serverTimestamp(),
      'termination_reason': (reason ?? 'terminated_by_admin').trim(),
      'terminated_by': currentUser.id,
    });
  }

  Future<void> approveDevice(String userId, String slotId) async {
    final currentUser = await ref.read(authUserProvider.future);
    if (currentUser == null || !currentUser.active) {
      throw StateError('Not authenticated');
    }
    final deviceRef = FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(userId)
        .collection(Collections.deviceRegistrations)
        .doc(slotId);
    final snapshot = await deviceRef.get();
    final device = DeviceRegistrationModel.fromJson(
      snapshot.data() ?? <String, dynamic>{},
      snapshot.id,
    );
    final isWorkspaceAdmin = currentUser.isSuperAdmin
        ? currentUser.activeWorkspaceId == device.tenantId
        : (currentUser.isAdmin || currentUser.isTenantAdmin) &&
              currentUser.tenantId == device.tenantId;
    if (!snapshot.exists ||
        currentUser.id == userId ||
        !isWorkspaceAdmin ||
        device.status != 'pending') {
      throw StateError('Permission denied');
    }
    await deviceRef.update({
      'status': 'active',
      'approved_at': FieldValue.serverTimestamp(),
      'approved_by': currentUser.id,
    });
  }

  Future<void> revokeDevice(String userId, String slotId) =>
      _setDeviceAccess(userId, slotId, block: false);

  Future<void> blockDevice(String userId, String slotId) =>
      _setDeviceAccess(userId, slotId, block: true);

  Future<void> _setDeviceAccess(
    String userId,
    String slotId, {
    required bool block,
  }) async {
    final currentUser = await ref.read(authUserProvider.future);
    if (currentUser == null || !currentUser.active) {
      throw StateError('Not authenticated');
    }
    final db = FirebaseFirestore.instance;
    final userRef = db.collection(Collections.users).doc(userId);
    final deviceRef = userRef
        .collection(Collections.deviceRegistrations)
        .doc(slotId);
    final sessionRefs = List.generate(
      AccessUsageSummary.maximumSlotsPerUser,
      (index) => userRef.collection(Collections.sessions).doc('slot_$index'),
    );
    await db.runTransaction<void>((transaction) async {
      final snapshots = await Future.wait([
        transaction.get(deviceRef),
        ...sessionRefs.map(transaction.get),
      ]);
      final deviceSnapshot = snapshots.first;
      if (!deviceSnapshot.exists) throw StateError('Device not found');
      final device = DeviceRegistrationModel.fromJson(
        deviceSnapshot.data() ?? <String, dynamic>{},
        deviceSnapshot.id,
      );
      final isOwner = currentUser.id == userId;
      final isWorkspaceAdmin = currentUser.isSuperAdmin
          ? currentUser.activeWorkspaceId == device.tenantId
          : (currentUser.isAdmin || currentUser.isTenantAdmin) &&
                currentUser.tenantId == device.tenantId;
      if (isOwner && isWorkspaceAdmin) {
        throw StateError('Permission denied');
      }
      if (!isOwner && !isWorkspaceAdmin) {
        throw StateError('Permission denied');
      }
      if (isOwner && !isWorkspaceAdmin) {
        final tenant = await transaction.get(
          db.collection(Collections.tenants).doc(device.tenantId),
        );
        if (tenant.data()?['allow_admin_reset_only'] != false) {
          throw StateError('device-admin-reset-required');
        }
      }
      if (block && !isWorkspaceAdmin) throw StateError('Permission denied');
      final nextStatus = block ? 'blocked' : 'revoked';
      transaction.update(deviceRef, {
        'status': nextStatus,
        'revoked_at': FieldValue.serverTimestamp(),
        'revoked_by': currentUser.id,
      });
      for (var index = 1; index < snapshots.length; index++) {
        final sessionSnapshot = snapshots[index];
        final data = sessionSnapshot.data();
        if (!sessionSnapshot.exists ||
            data?['device_id'] != device.deviceId ||
            data?['status'] != 'active') {
          continue;
        }
        transaction.update(sessionRefs[index - 1], {
          'status': 'revoked',
          'revoked_at': FieldValue.serverTimestamp(),
          'termination_reason': block ? 'device_blocked' : 'device_removed',
          'terminated_by': currentUser.id,
        });
      }
    });
  }

  Future<void> resetDevice(String userId, String slotId) async {
    final currentUser = await ref.read(authUserProvider.future);
    if (currentUser == null || !currentUser.active) {
      throw StateError('Not authenticated');
    }
    final deviceRef = FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(userId)
        .collection(Collections.deviceRegistrations)
        .doc(slotId);
    final snapshot = await deviceRef.get();
    final device = DeviceRegistrationModel.fromJson(
      snapshot.data() ?? <String, dynamic>{},
      snapshot.id,
    );
    final canReset = currentUser.isSuperAdmin
        ? currentUser.activeWorkspaceId == device.tenantId
        : (currentUser.isAdmin || currentUser.isTenantAdmin) &&
              currentUser.tenantId == device.tenantId;
    if (!snapshot.exists ||
        currentUser.id == userId ||
        !canReset ||
        device.status != 'revoked') {
      throw StateError('Permission denied');
    }
    await deviceRef.update({
      'status': 'active',
      'registered_at': FieldValue.serverTimestamp(),
      'last_seen_at': FieldValue.serverTimestamp(),
      'approved_at': FieldValue.serverTimestamp(),
      'approved_by': currentUser.id,
    });
  }

  Future<void> terminateCurrentSession(String userId) async {
    final currentUser = await ref.read(authUserProvider.future);
    final tenantId = TenantScope.normalize(currentUser?.tenantId);
    if (currentUser == null || currentUser.id != userId || tenantId == null) {
      return;
    }
    final metadata = await DeviceInstallation.current();
    final sessions = await FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(userId)
        .collection(Collections.sessions)
        .where('tenant_id', isEqualTo: tenantId)
        .where('user_id', isEqualTo: userId)
        .where('device_id', isEqualTo: metadata.installationId)
        .limit(1)
        .get();
    if (sessions.docs.isEmpty) return;
    await terminateSession(userId, sessions.docs.first.id, reason: 'logout');
  }

  int _firstReusableDeviceSlot(
    List<DocumentSnapshot<Map<String, dynamic>>?> snapshots,
    int maxSlots, {
    required DateTime now,
    required bool allowRevoked,
  }) {
    for (var index = 0; index < maxSlots; index++) {
      final data = snapshots[index]?.data();
      final lastSeenAt = data?['last_seen_at'];
      if (data == null ||
          data['status'] == null ||
          (allowRevoked && data['status'] == 'revoked') ||
          (data['status'] == 'active' &&
              lastSeenAt is Timestamp &&
              !lastSeenAt.toDate().isAfter(
                now.subtract(const Duration(days: 30)),
              ))) {
        return index;
      }
    }
    return -1;
  }

  SessionModel _pendingSession(
    String userId,
    String tenantId,
    DeviceInstallationMetadata metadata,
    int slotNumber,
  ) {
    final timestamp = Timestamp.now();
    return SessionModel(
      id: 'pending',
      userId: userId,
      tenantId: tenantId,
      deviceId: metadata.installationId,
      platform: metadata.platform,
      status: 'pending',
      createdAt: timestamp,
      lastSeenAt: timestamp,
    );
  }

  int _firstReusableSessionSlot(
    List<DocumentSnapshot<Map<String, dynamic>>?> snapshots,
    int maxSlots,
    DateTime now,
  ) {
    for (var index = 0; index < maxSlots; index++) {
      final data = snapshots[index]?.data();
      final expiresAt = data?['expires_at'];
      if (data == null ||
          data['status'] != 'active' ||
          (expiresAt is Timestamp && !expiresAt.toDate().isAfter(now))) {
        return index;
      }
    }
    return -1;
  }
}

final tenantManagementNotifierProvider =
    AsyncNotifierProvider<TenantManagementNotifier, void>(
      TenantManagementNotifier.new,
    );

final sessionManagementNotifierProvider =
    AsyncNotifierProvider<SessionManagementNotifier, void>(
      SessionManagementNotifier.new,
    );
