import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/constants/collections.dart';
import '../core/models/access_usage_summary.dart';
import '../core/models/tenant_model.dart';
import '../core/services/device_installation.dart';
import '../core/utils/tenant_scope.dart';
import '../models/device_registration_model.dart';
import '../models/session_model.dart';
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

final userSessionsProvider = StreamProvider.family<List<SessionModel>, String>((
  ref,
  userId,
) {
  final currentUser = ref.watch(authUserProvider).value;
  final tenantId = TenantScope.normalize(currentUser?.tenantId);
  if (currentUser == null || tenantId == null) {
    return const Stream<List<SessionModel>>.empty();
  }

  return FirebaseFirestore.instance
      .collection(Collections.users)
      .doc(userId)
      .collection(Collections.sessions)
      .where('tenant_id', isEqualTo: tenantId)
      .where('user_id', isEqualTo: userId)
      .limit(AccessUsageSummary.maximumSlotsPerUser)
      .snapshots()
      .map(
        (snap) => snap.docs
            .map((doc) => SessionModel.fromJson(doc.data(), doc.id))
            .toList(),
      );
});

final deviceRegistrationsProvider =
    StreamProvider.family<List<DeviceRegistrationModel>, String>((ref, userId) {
      final currentUser = ref.watch(authUserProvider).value;
      final tenantId = TenantScope.normalize(currentUser?.tenantId);
      if (currentUser == null || tenantId == null) {
        return const Stream<List<DeviceRegistrationModel>>.empty();
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
        (actingUser.isSuperAdmin
            ? actingUser.activeWorkspaceId == tenantId
            : actingUser.isTenantAdmin && actingUser.tenantId == tenantId);
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
}

class SessionManagementNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<SessionModel> registerCurrentAccess({
    required String userId,
    required String tenantId,
  }) async {
    final currentUser = await ref.read(authUserProvider.future);
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

    state = const AsyncLoading();
    try {
      final deviceRecords = await userRef
        .collection(Collections.deviceRegistrations)
        .where('tenant_id', isEqualTo: tenantId)
        .where('user_id', isEqualTo: userId)
        .get();
      final sessionRecords = await userRef
        .collection(Collections.sessions)
        .where('tenant_id', isEqualTo: tenantId)
        .where('user_id', isEqualTo: userId)
        .get();
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
        final deviceSnapshots =
            List<DocumentSnapshot<Map<String, dynamic>>?>.filled(
              AccessUsageSummary.maximumSlotsPerUser,
              null,
            );
        final sessionSnapshots =
            List<DocumentSnapshot<Map<String, dynamic>>?>.filled(
              AccessUsageSummary.maximumSlotsPerUser,
              null,
            );
        for (final snapshot in deviceRecords.docs) {
          final slotNumber = (snapshot.data()['slot_number'] as num?)?.toInt();
          if (slotNumber == null ||
              slotNumber < 0 ||
              slotNumber >= deviceSnapshots.length ||
              snapshot.id != 'slot_$slotNumber') {
            continue;
          }
          deviceSnapshots[slotNumber] = await transaction.get(
            snapshot.reference,
          );
        }
        for (final snapshot in sessionRecords.docs) {
          final slotNumber = (snapshot.data()['slot_number'] as num?)?.toInt();
          if (slotNumber == null ||
              slotNumber < 0 ||
              slotNumber >= sessionSnapshots.length ||
              snapshot.id != 'slot_$slotNumber') {
            continue;
          }
          sessionSnapshots[slotNumber] = await transaction.get(
            snapshot.reference,
          );
        }

        final now = DateTime.now();
        final activeDevices = deviceSnapshots
            .where((snapshot) => snapshot?.data()?['status'] == 'active')
            .toList();
        final existingDeviceIndex = deviceSnapshots.indexWhere(
          (snapshot) =>
              snapshot?.data()?['status'] == 'active' &&
              snapshot?.data()?['device_id'] == metadata.installationId,
        );
        final deviceIndex = existingDeviceIndex >= 0
            ? existingDeviceIndex
            : _firstReusableDeviceSlot(
                deviceSnapshots,
                tenant.maxDevicesAllowed,
              );
        if (existingDeviceIndex < 0 &&
            (activeDevices.length >= tenant.maxDevicesAllowed ||
                deviceIndex < 0)) {
          throw StateError('device-limit-reached');
        }

        final deviceRef = deviceRefs[deviceIndex];
        final deviceSnapshot = deviceSnapshots[deviceIndex];
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
          'status': 'active',
          'last_seen_at': FieldValue.serverTimestamp(),
        };
        if (deviceSnapshot == null ||
            !deviceSnapshot.exists ||
            deviceSnapshot.data()?['status'] != 'active') {
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
          if (activeSessions.length >= tenant.maxActiveSessionsAllowed) {
            throw StateError('session-limit-reached');
          }
          sessionIndex = _firstReusableSessionSlot(
            sessionSnapshots,
            tenant.maxActiveSessionsAllowed,
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
        return SessionModel.fromJson({
          ...sessionData,
          'created_at': priorSession?['created_at'] ?? Timestamp.now(),
        }, sessionRef.id);
      });
      state = const AsyncData(null);
      return session;
    } catch (error, stack) {
      state = AsyncError(error, stack);
      rethrow;
    }
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

  Future<void> revokeDevice(String userId, String slotId) async {
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
    final isOwner = currentUser.id == userId;
    final isWorkspaceAdmin = currentUser.isSuperAdmin
        ? currentUser.activeWorkspaceId == device.tenantId
        : (currentUser.isAdmin || currentUser.isTenantAdmin) &&
              currentUser.tenantId == device.tenantId;
    if (!snapshot.exists || (!isOwner && !isWorkspaceAdmin)) {
      throw StateError('Permission denied');
    }
    await deviceRef.update({
      'status': 'revoked',
      'revoked_at': FieldValue.serverTimestamp(),
      'revoked_by': currentUser.id,
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
    int maxSlots,
  ) {
    for (var index = 0; index < maxSlots; index++) {
      final data = snapshots[index]?.data();
      if (data == null || data['status'] != 'active') return index;
    }
    return -1;
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
