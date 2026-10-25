import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../core/models/tenant_model.dart';
import '../core/utils/firestore_pagination.dart';
import '../core/utils/role_utils.dart';
import '../core/utils/tenant_scope.dart';
import '../firebase_options.dart';
import '../models/user_model.dart';
import 'auth_provider.dart';

final allUsersProvider = StreamProvider.autoDispose<List<UserModel>>((ref) {
  // Account management is separate from tenant/workspace administration.
  // Only legacy admins and super admins can access this provider.
  final canManageUsers = ref.watch(
    authUserProvider.select(
      (s) => canManageUserAccountsRole(
        roleValueFromUserRole(s.value?.role ?? UserRole.seller),
      ),
    ),
  );
  final tenantId = ref.watch(
    authUserProvider.select((s) => TenantScope.normalize(s.value?.tenantId)),
  );
  if (!canManageUsers) return const Stream.empty();
  final query = TenantScope.applyToQuery(
    FirebaseFirestore.instance.collection(Collections.users),
    tenantId: tenantId,
  );
  return query
      .where('active', isEqualTo: true)
      .orderBy('display_name')
      .limit(100)
      .snapshots()
      .map(
        (snap) =>
            snap.docs.map((d) => UserModel.fromJson(d.data(), d.id)).toList(),
      );
});

/// Admin-only one-shot user fetch for export name resolution.
///
/// Fetches ALL users regardless of [active] status so that historical
/// transactions created by now-deactivated sellers still resolve to a
/// display name instead of the "—" fallback. Uses a single `.get()` call
/// (not a stream). NOT autoDispose: callers use ref.read(provider.future)
/// which doesn't subscribe — autoDispose would destroy the provider
/// mid-Firestore-query → StateError. Callers must ref.invalidate() first.
final allUsersExportProvider = FutureProvider<List<UserModel>>((ref) async {
  // Use .future to await the first auth emission instead of reading a
  // potentially-null .value while the StreamProvider is still loading.
  final user = await ref.read(authUserProvider.future);
  if (user == null ||
      !canManageUserAccountsRole(roleValueFromUserRole(user.role))) {
    return const <UserModel>[];
  }
  final tenantId = TenantScope.normalize(user.tenantId);
  final query = TenantScope.applyToQuery(
    FirebaseFirestore.instance.collection(Collections.users),
    tenantId: tenantId,
  );
  final docs = await fetchAllQueryDocuments(query);
  return docs
      .map((document) => UserModel.fromJson(document.data(), document.id))
      .toList();
});

final sellersProvider = StreamProvider.autoDispose<List<UserModel>>((ref) {
  // Route assignments are limited to seller accounts. Operational supervisors
  // already see tenant routes and must not be represented as route sellers.
  final canManageUsers = ref.watch(
    authUserProvider.select(
      (s) => canManageUserAccountsRole(
        roleValueFromUserRole(s.value?.role ?? UserRole.seller),
      ),
    ),
  );
  final tenantId = ref.watch(
    authUserProvider.select((s) => TenantScope.normalize(s.value?.tenantId)),
  );
  if (!canManageUsers) return const Stream.empty();
  final query = TenantScope.applyToQuery(
    FirebaseFirestore.instance.collection(Collections.users),
    tenantId: tenantId,
  );
  return query
      .where('active', isEqualTo: true)
      .limit(100)
      .snapshots()
      .map(
        (snap) => snap.docs
            .map((d) => UserModel.fromJson(d.data(), d.id))
            .where((user) => user.isSeller)
            .toList(),
      );
});

/// Admin-only: inactive (deactivated) users ordered by most recently updated.
final inactiveUsersProvider = StreamProvider.autoDispose<List<UserModel>>((
  ref,
) {
  // Use select() so heartbeat writes to last_active do NOT restart the stream.
  final canManageUsers = ref.watch(
    authUserProvider.select(
      (s) => canManageUserAccountsRole(
        roleValueFromUserRole(s.value?.role ?? UserRole.seller),
      ),
    ),
  );
  final tenantId = ref.watch(
    authUserProvider.select((s) => TenantScope.normalize(s.value?.tenantId)),
  );
  if (!canManageUsers) return const Stream.empty();
  final query = TenantScope.applyToQuery(
    FirebaseFirestore.instance.collection(Collections.users),
    tenantId: tenantId,
  );
  return query
      .where('active', isEqualTo: false)
      .orderBy('updated_at', descending: true)
      .limit(200)
      .snapshots()
      .map(
        (snap) =>
            snap.docs.map((d) => UserModel.fromJson(d.data(), d.id)).toList(),
      );
});

class UserManagementNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  String _normalizeRole(String role) {
    return normalizeRoleName(role);
  }

  Future<bool> _isCurrentUserAdmin() async {
    final cachedUser = ref.read(authUserProvider).value;
    if (cachedUser != null) {
      return canManageUserAccountsRole(roleValueFromUserRole(cachedUser.role));
    }

    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) return false;

    final profileSnap = await FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(authUser.uid)
        .get();
    if (!profileSnap.exists) return false;

    final role = (profileSnap.data()?['role'] as String? ?? '').trim();
    return canManageUserAccountsRole(role);
  }

  Future<UserModel?> _currentProfileFromServer(String userId) async {
    if (FirebaseAuth.instance.currentUser?.uid != userId) return null;
    final profileSnap = await FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(userId)
        .get(const GetOptions(source: Source.server));
    if (FirebaseAuth.instance.currentUser?.uid != userId ||
        !profileSnap.exists) {
      return null;
    }
    return UserModel.fromJson(profileSnap.data()!, profileSnap.id);
  }

  Future<String> _requireAdminUid({String? requiredTenantId}) async {
    final authUser = FirebaseAuth.instance.currentUser;
    final adminUid = authUser?.uid.trim() ?? '';
    if (adminUid.isEmpty) {
      throw StateError('No authenticated user found');
    }
    if (!await _isCurrentUserAdmin()) {
      throw StateError('Admin privileges required');
    }
    final profile = await ref.read(authUserProvider.future);
    if (profile?.isSuperAdmin == true) {
      final currentProfile = await _currentProfileFromServer(adminUid);
      final activeTenantId = TenantScope.normalize(currentProfile?.tenantId);
      if (currentProfile == null ||
          !currentProfile.hasActiveWorkspaceSupportContextFor(
            activeTenantId ?? '',
          ) ||
          activeTenantId == null) {
        throw StateError(
          'Select a workspace support context before managing users.',
        );
      }
      final requestedTenantId = TenantScope.normalize(requiredTenantId);
      if (requestedTenantId != null && requestedTenantId != activeTenantId) {
        throw StateError('Users must belong to the active workspace');
      }
    }
    return adminUid;
  }

  Future<
    ({String adminUid, UserModel admin, UserModel target, String tenantId})
  >
  _requireManageableUser(String uid) async {
    final adminUid = await _requireAdminUid();
    final admin = await _currentProfileFromServer(adminUid);
    if (admin == null || !admin.active) {
      throw StateError('An active user profile is required.');
    }
    final tenantId = TenantScope.requireTenant(admin.tenantId);
    final targetId = uid.trim();
    if (targetId.isEmpty) throw ArgumentError('uid must not be empty');
    if (targetId == adminUid) {
      throw StateError('Administrators cannot disable their own account.');
    }
    final targetSnapshot = await FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(targetId)
        .get(const GetOptions(source: Source.server));
    if (!targetSnapshot.exists) throw StateError('User not found.');
    final target = UserModel.fromJson(
      targetSnapshot.data()!,
      targetSnapshot.id,
    );
    if (target.tenantId != tenantId ||
        target.isSuperAdmin ||
        (!admin.isSuperAdmin && target.role != UserRole.seller)) {
      throw StateError('Workspace user administration is required.');
    }
    return (
      adminUid: adminUid,
      admin: admin,
      target: target,
      tenantId: tenantId,
    );
  }

  Future<void> _setUserActiveAtomically({
    required String userId,
    required String tenantId,
    required bool adminIsSuperAdmin,
    required bool active,
    bool clearRouteAssignments = false,
    String? displayName,
    List<String>? routeIdsToAssign,
    List<String>? routeNamesToAssign,
  }) async {
    final db = FirebaseFirestore.instance;
    final userRef = db.collection(Collections.users).doc(userId);
    final tenantRef = db.collection(Collections.tenants).doc(tenantId);
    final routeSnapshot = clearRouteAssignments
        ? await db
              .collection(Collections.routes)
              .where('tenant_id', isEqualTo: tenantId)
              .where('assigned_seller_ids', arrayContains: userId)
              .limit(20)
              .get(const GetOptions(source: Source.server))
        : null;

    await db.runTransaction<void>((transaction) async {
      final userSnapshot = await transaction.get(userRef);
      final tenantSnapshot = await transaction.get(tenantRef);
      final userData = userSnapshot.data();
      final role = (userData?['role'] as String? ?? '').trim().toLowerCase();
      if (!userSnapshot.exists ||
          userData?['tenant_id'] != tenantId ||
          role == 'super_admin' ||
          (!adminIsSuperAdmin && role != 'seller')) {
        throw StateError('Workspace user administration is required.');
      }

      if (active && userData?['active'] == true) return;
      final tenantData = tenantSnapshot.data();
      if (!tenantSnapshot.exists ||
          tenantData?['active'] != true ||
          tenantData?['active_user_count'] is! int ||
          tenantData?['max_active_users'] != TenantModel.freeSeatLimit) {
        throw StateError('workspace_seat_count_initialization_required');
      }
      final activeUserCount = tenantData!['active_user_count'] as int;
      if (active && activeUserCount >= TenantModel.freeSeatLimit) {
        throw StateError('workspace_seat_limit_reached');
      }

      final seatCountRevision =
          (tenantData['seat_count_revision'] as num?)?.toInt() ?? 0;
      final userUpdate = <String, dynamic>{
        'active': active,
        'updated_at': FieldValue.serverTimestamp(),
      };
      if (clearRouteAssignments) {
        userUpdate['assigned_route_ids'] = <String>[];
        userUpdate['assigned_route_names'] = <String>[];
      }
      if (routeIdsToAssign != null) {
        userUpdate['assigned_route_ids'] = routeIdsToAssign;
        userUpdate['assigned_route_names'] = routeNamesToAssign ?? <String>[];
      }
      transaction.update(userRef, userUpdate);

      transaction.update(tenantRef, {
        'active_user_count': active ? activeUserCount + 1 : activeUserCount - 1,
        'seat_count_revision': seatCountRevision + 1,
        'seat_change_user_id': userId,
        'seat_change_kind': active ? 'add' : 'remove',
        'updated_at': FieldValue.serverTimestamp(),
      });

      if (active) {
        for (final routeId in routeIdsToAssign ?? const <String>[]) {
          if (routeId.trim().isEmpty) continue;
          transaction.update(db.collection(Collections.routes).doc(routeId), {
            'assigned_seller_ids': FieldValue.arrayUnion([userId]),
            'assigned_seller_names': FieldValue.arrayUnion(
              displayName != null && displayName.isNotEmpty
                  ? [displayName]
                  : [],
            ),
            'updated_at': FieldValue.serverTimestamp(),
          });
        }
        return;
      }
      if (routeSnapshot != null) {
        for (final route in routeSnapshot.docs) {
          transaction.update(route.reference, {
            'assigned_seller_ids': FieldValue.arrayRemove([userId]),
            'assigned_seller_names': FieldValue.arrayRemove(
              displayName != null && displayName.isNotEmpty
                  ? [displayName]
                  : [],
            ),
            'updated_at': FieldValue.serverTimestamp(),
          });
        }
      }
    });
  }

  Future<String> createUser({
    required String email,
    required String password,
    required String displayName,
    required String role,
    String? phone,
    List<String> assignedRouteIds = const [],
    List<String> assignedRouteNames = const [],
    String? tenantId,
  }) async {
    final requestedTenantId = TenantScope.normalize(tenantId);
    final adminUid = await _requireAdminUid(
      requiredTenantId: requestedTenantId,
    );
    var actingUser = await ref.read(authUserProvider.future);
    if (actingUser?.isSuperAdmin == true) {
      actingUser = await _currentProfileFromServer(adminUid);
    }
    if (actingUser == null || !actingUser.active) {
      throw StateError('An active user profile is required');
    }
    final owner = actingUser;
    state = const AsyncLoading();
    String? createdUserId;
    state = await AsyncValue.guard(() async {
      final normalizedRole = _normalizeRole(role);
      if (normalizedRole == 'super_admin') {
        throw StateError(
          'Platform super-admin accounts require trusted out-of-band provisioning.',
        );
      }
      if (owner.isTenantAdmin &&
          normalizedRole != 'supervisor' &&
          normalizedRole != 'seller') {
        throw StateError(
          'Workspace admins may create only supervisor and seller accounts.',
        );
      }
      if (!owner.isSuperAdmin &&
          !owner.isTenantAdmin &&
          normalizedRole != 'seller') {
        throw StateError('This account cannot assign the requested role.');
      }
      if (normalizedRole == 'seller' && assignedRouteIds.isEmpty) {
        throw ArgumentError(
          'Seller accounts require at least one assigned route.',
        );
      }
      final normalizedRouteIds = normalizedRole == 'seller'
          ? assignedRouteIds.map((id) => id.trim()).toList()
          : <String>[];
      if (normalizedRouteIds.any((id) => id.isEmpty)) {
        throw ArgumentError('Route IDs must not be empty.');
      }
      if (normalizedRouteIds.toSet().length != normalizedRouteIds.length) {
        throw ArgumentError('Route IDs must not contain duplicates.');
      }
      if (normalizedRole == 'seller' && normalizedRouteIds.isEmpty) {
        throw ArgumentError(
          'Seller accounts require at least one assigned route.',
        );
      }

      final trimmedEmail = email.trim().toLowerCase();
      final trimmedName = displayName.trim();
      final trimmedPassword = password.trim();
      final trimmedPhone = phone?.trim();
      if (trimmedPassword.length < 8) {
        throw FirebaseAuthException(
          code: 'weak-password',
          message: 'Password is too weak. Use at least 8 characters.',
        );
      }

      final effectiveTenantId = TenantScope.requireTenant(owner.tenantId);
      if (requestedTenantId != null && requestedTenantId != effectiveTenantId) {
        throw StateError('Users must belong to the active workspace');
      }
      final db = FirebaseFirestore.instance;
      final tenantRef = db
          .collection(Collections.tenants)
          .doc(effectiveTenantId);
      final initialTenant = await tenantRef.get(
        const GetOptions(source: Source.server),
      );
      final initialTenantData = initialTenant.data();
      if (!initialTenant.exists ||
          initialTenantData?['active'] != true ||
          initialTenantData?['active_user_count'] is! int ||
          initialTenantData?['max_active_users'] != TenantModel.freeSeatLimit) {
        throw StateError('workspace_seat_count_initialization_required');
      }
      if ((initialTenantData!['active_user_count'] as int) >=
          TenantModel.freeSeatLimit) {
        throw StateError('workspace_seat_limit_reached');
      }

      // Use a secondary FirebaseApp so the admin stays signed in
      FirebaseApp? tempApp;
      try {
        tempApp = Firebase.app('userCreation');
      } catch (_) {
        tempApp = await Firebase.initializeApp(
          name: 'userCreation',
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      final tempAuth = FirebaseAuth.instanceFor(app: tempApp);

      try {
        // Create the Auth account via the disposable secondary app
        final cred = await tempAuth.createUserWithEmailAndPassword(
          email: trimmedEmail,
          password: trimmedPassword,
        );
        final newUid = cred.user!.uid;
        createdUserId = newUid;
        final userRef = db.collection(Collections.users).doc(newUid);
        final routeRefs = normalizedRouteIds
            .map((routeId) => db.collection(Collections.routes).doc(routeId))
            .toList();
        final now = Timestamp.now();
        try {
          await db.runTransaction<void>((transaction) async {
            final tenantSnapshot = await transaction.get(tenantRef);
            final tenantData = tenantSnapshot.data();
            if (!tenantSnapshot.exists ||
                tenantData?['active'] != true ||
                tenantData?['active_user_count'] is! int ||
                tenantData?['max_active_users'] != TenantModel.freeSeatLimit) {
              throw StateError('workspace_seat_count_initialization_required');
            }
            final activeUserCount = tenantData!['active_user_count'] as int;
            if (activeUserCount >= TenantModel.freeSeatLimit) {
              throw StateError('workspace_seat_limit_reached');
            }

            for (final routeRef in routeRefs) {
              final routeSnapshot = await transaction.get(routeRef);
              if (!routeSnapshot.exists ||
                  routeSnapshot.data()?['tenant_id'] != effectiveTenantId ||
                  routeSnapshot.data()?['active'] != true) {
                throw StateError('Seller route is unavailable.');
              }
            }

            transaction.set(userRef, {
              'email': trimmedEmail,
              'display_name': trimmedName,
              'phone': (trimmedPhone == null || trimmedPhone.isEmpty)
                  ? null
                  : trimmedPhone,
              'email_verified': false,
              'role': normalizedRole,
              'tenant_id': effectiveTenantId,
              'assigned_route_ids': normalizedRouteIds,
              'assigned_route_names': normalizedRole == 'seller'
                  ? assignedRouteNames
                  : [],
              'active': true,
              'created_by': adminUid,
              'created_at': now,
              'updated_at': now,
            });
            transaction.update(tenantRef, {
              'active_user_count': activeUserCount + 1,
              'seat_count_revision':
                  ((tenantData['seat_count_revision'] as num?)?.toInt() ?? 0) +
                  1,
              'seat_change_user_id': newUid,
              'seat_change_kind': 'add',
              'updated_at': FieldValue.serverTimestamp(),
            });
            for (final routeRef in routeRefs) {
              transaction.update(routeRef, {
                'assigned_seller_ids': FieldValue.arrayUnion([newUid]),
                'assigned_seller_names': FieldValue.arrayUnion([trimmedName]),
                'updated_at': FieldValue.serverTimestamp(),
              });
            }
          });
        } on StateError catch (error) {
          if (error.message == 'workspace_seat_limit_reached' ||
              error.message == 'workspace_seat_count_initialization_required') {
            await cred.user!.delete();
            createdUserId = null;
          }
          rethrow;
        } finally {
          await tempAuth.signOut();
        }
      } on FirebaseAuthException {
        rethrow; // Let AppErrorMapper handle auth errors (email-in-use, etc.)
      } finally {
        // S-04: Dispose the secondary app to prevent resource leaks
        try {
          await tempApp.delete();
        } catch (_) {}
      }
    });
    if (state.hasError) {
      Error.throwWithStackTrace(
        state.error!,
        state.stackTrace ?? StackTrace.current,
      );
    }
    return createdUserId!;
  }

  Future<void> updateUser(
    String uid,
    Map<String, dynamic> data, {
    List<String> previousRouteIds = const [],
  }) async {
    final trimmedUid = uid.trim();
    if (trimmedUid.isEmpty) {
      throw ArgumentError('uid must not be empty');
    }

    final actingUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (actingUid.isEmpty) {
      throw StateError('No authenticated user found');
    }

    final isAdmin = await _isCurrentUserAdmin();
    final actingUser = await ref.read(authUserProvider.future);
    if (actingUser == null || !actingUser.active) {
      throw StateError('An active user profile is required');
    }
    final db = FirebaseFirestore.instance;
    final updateData = <String, dynamic>{...data};
    if (updateData['tenant_id'] != null) {
      final normalizedTenant = TenantScope.normalize(
        updateData['tenant_id'].toString(),
      );
      if (normalizedTenant == null || normalizedTenant.isEmpty) {
        throw ArgumentError('tenant_id must not be empty');
      }
      updateData['tenant_id'] = normalizedTenant;
    }
    if (updateData['role'] is String) {
      updateData['role'] = _normalizeRole(updateData['role'] as String);
      if (updateData['role'] == 'super_admin') {
        throw StateError(
          'Platform super-admin roles cannot be granted from the client.',
        );
      }
    }

    if (!actingUser.isSuperAdmin &&
        !actingUser.isTenantAdmin &&
        updateData.containsKey('role')) {
      throw StateError(
        'Only workspace administrators can change workspace roles.',
      );
    }
    if (!actingUser.isSuperAdmin && updateData.containsKey('tenant_id')) {
      throw StateError('Workspace administrators cannot change workspace');
    }

    if (actingUser.isTenantAdmin) {
      final tenantId = TenantScope.requireTenant(actingUser.tenantId);
      final targetSnapshot = await db
          .collection(Collections.users)
          .doc(trimmedUid)
          .get(const GetOptions(source: Source.server));
      final targetData = targetSnapshot.data();
      if (!targetSnapshot.exists ||
          TenantScope.normalize(targetData?['tenant_id'] as String?) !=
              tenantId ||
          (targetData?['role'] as String?)?.trim().toLowerCase() ==
              'super_admin') {
        throw StateError('Workspace user administration is required.');
      }

      final requestedRole = updateData['role'] as String?;
      final targetRole = normalizeRoleName(
        targetData?['role'] as String? ?? '',
      );
      const workspaceRoles = {'supervisor', 'seller'};
      if (!workspaceRoles.contains(targetRole)) {
        throw StateError('Workspace user administration is required.');
      }
      if (requestedRole != null &&
          (!workspaceRoles.contains(requestedRole) ||
              !workspaceRoles.contains(targetRole))) {
        throw StateError(
          'Workspace admins may change only supervisor and seller roles.',
        );
      }

      final tenantSnapshot = await db
          .collection(Collections.tenants)
          .doc(tenantId)
          .get(const GetOptions(source: Source.server));
      final isOwner = tenantSnapshot.data()?['owner_user_id'] == trimmedUid;
      if (isOwner && requestedRole != null) {
        throw StateError(
          'The permanent workspace owner role cannot be changed.',
        );
      }
      if (targetRole == 'tenant_admin' &&
          updateData.keys.any(
            (key) => !{'display_name', 'phone'}.contains(key),
          )) {
        throw StateError(
          'Workspace admins may update only owner contact details.',
        );
      }
      const tenantAdminEditableKeys = {
        'display_name',
        'phone',
        'role',
        'assigned_route_ids',
        'assigned_route_names',
      };
      if (updateData.keys.any(
        (key) => !tenantAdminEditableKeys.contains(key),
      )) {
        throw StateError('Unsupported workspace user update.');
      }
    }

    final hasRoleUpdate = updateData.containsKey('role');
    final hasRouteIdsUpdate = updateData.containsKey('assigned_route_ids');
    final updatedRole = hasRoleUpdate ? updateData['role'] as String? : null;
    final routeIdsValue = updateData['assigned_route_ids'];
    if (hasRouteIdsUpdate && routeIdsValue is! List) {
      throw ArgumentError('assigned_route_ids must be a list.');
    }
    final newRouteIds = routeIdsValue is List
        ? routeIdsValue.map((value) {
            if (value is! String) {
              throw ArgumentError('Route IDs must be strings.');
            }
            return value.trim();
          }).toList()
        : <String>[];
    if (hasRouteIdsUpdate &&
        (newRouteIds.any((routeId) => routeId.isEmpty) ||
            newRouteIds.toSet().length != newRouteIds.length)) {
      throw ArgumentError('Route IDs must be non-empty and unique.');
    }
    if (hasRouteIdsUpdate) {
      updateData['assigned_route_ids'] = newRouteIds;
    }
    final displayName = (updateData['display_name'] as String?)?.trim();

    if (!isAdmin) {
      const allowedSelfKeys = {'display_name'};
      if (actingUid != trimmedUid) {
        throw StateError('Only admins can update other users');
      }
      final disallowedKeys = updateData.keys
          .where((key) => !allowedSelfKeys.contains(key))
          .toList();
      if (disallowedKeys.isNotEmpty) {
        throw StateError(
          'Only admins can update role, route, or account status',
        );
      }
      updateData.remove('assigned_route_ids');
      updateData.remove('assigned_route_names');
      updateData.remove('role');
    } else {
      if (updatedRole == 'seller' &&
          (!hasRouteIdsUpdate || newRouteIds.isEmpty)) {
        throw ArgumentError(
          'Seller accounts require at least one assigned route.',
        );
      }

      // Non-seller users must not retain a route assignment.
      if (updatedRole != null && updatedRole != 'seller') {
        updateData['assigned_route_ids'] = [];
        updateData['assigned_route_names'] = [];
      }
    }

    // DI-02: use a single WriteBatch for atomicity — user doc + route docs.
    final batch = db.batch();
    final now = Timestamp.now();

    batch.update(db.collection(Collections.users).doc(trimmedUid), {
      ...updateData,
      'updated_at': now,
    });

    if (isAdmin && hasRouteIdsUpdate) {
      // Diff: removed routes
      final removedRouteIds = previousRouteIds
          .where((id) => id.isNotEmpty && !newRouteIds.contains(id))
          .toList();
      for (final routeId in removedRouteIds) {
        batch.update(db.collection(Collections.routes).doc(routeId), {
          'assigned_seller_ids': FieldValue.arrayRemove([trimmedUid]),
          'assigned_seller_names': FieldValue.arrayRemove(
            displayName != null ? [displayName] : [],
          ),
          'updated_at': now,
        });
      }

      // Diff: added routes
      final addedRouteIds = newRouteIds
          .where((id) => id.isNotEmpty && !previousRouteIds.contains(id))
          .toList();
      for (final routeId in addedRouteIds) {
        batch.update(db.collection(Collections.routes).doc(routeId), {
          'assigned_seller_ids': FieldValue.arrayUnion([trimmedUid]),
          'assigned_seller_names': FieldValue.arrayUnion(
            displayName != null ? [displayName] : [],
          ),
          'updated_at': now,
        });
      }
    }

    await batch.commit();
  }

  Future<void> toggleActive(String uid, bool active) async {
    final target = await _requireManageableUser(uid);
    await _setUserActiveAtomically(
      userId: target.target.id,
      tenantId: target.tenantId,
      adminIsSuperAdmin: target.admin.isSuperAdmin,
      active: active,
    );
  }

  /// Soft-delete: deactivate user + clear route assignments.
  /// Auth account is orphaned but cannot access anything (rules check active).
  Future<void> deleteUser(String uid) async {
    final target = await _requireManageableUser(uid);
    await _setUserActiveAtomically(
      userId: target.target.id,
      tenantId: target.tenantId,
      adminIsSuperAdmin: target.admin.isSuperAdmin,
      active: false,
      clearRouteAssignments: true,
      displayName: target.target.displayName,
    );
  }

  /// Send a password-reset email to the seller.
  /// Email is immutable after creation; password can only be reset via email.
  Future<void> sendPasswordResetForSeller({required String email}) async {
    await _requireAdminUid();
    final trimmedEmail = email.trim().toLowerCase();
    if (trimmedEmail.isEmpty) return;
    await FirebaseAuth.instance.sendPasswordResetEmail(email: trimmedEmail);
  }

  /// Reactivates a soft-deleted user and re-assigns them to routes atomically.
  /// DI-06: deleteUser() clears routes; must re-assign on reactivation.
  Future<void> reactivateUser({
    required String uid,
    required List<String> routeIds,
    required List<String> routeNames,
    required String displayName,
  }) async {
    final target = await _requireManageableUser(uid);
    if (target.target.active) {
      throw StateError('Only inactive users can be reactivated.');
    }
    if (target.target.role != UserRole.seller) {
      throw StateError(
        'Seller route assignments are required for reactivation.',
      );
    }
    final normalizedRouteIds = routeIds.map((id) => id.trim()).toList();
    if (normalizedRouteIds.isEmpty ||
        normalizedRouteIds.any((routeId) => routeId.isEmpty) ||
        normalizedRouteIds.toSet().length != normalizedRouteIds.length) {
      throw ArgumentError('Seller accounts require valid assigned routes.');
    }
    final trimmedName = displayName.trim();
    await _setUserActiveAtomically(
      userId: target.target.id,
      tenantId: target.tenantId,
      adminIsSuperAdmin: target.admin.isSuperAdmin,
      active: true,
      displayName: trimmedName,
      routeIdsToAssign: normalizedRouteIds,
      routeNamesToAssign: routeNames,
    );
  }

  /// Hard-deletes the Firestore profile of a deactivated user.
  ///
  /// IMPORTANT: On the free Firebase tier (Spark), the Firebase Auth entry
  /// cannot be removed programmatically without the Admin SDK / Cloud Functions.
  /// This method only removes the Firestore document. The Auth entry persists
  /// until manually deleted via the Firebase console.
  ///
  /// Guard: only inactive users can be hard-deleted; admin cannot delete self.
  Future<void> hardDeleteUser(String uid, String currentAdminUid) async {
    final authUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final actor = await ref.read(authUserProvider.future);
    final tenantId = TenantScope.normalize(actor?.tenantId);
    if (authUid.isEmpty ||
        authUid != currentAdminUid.trim() ||
        actor == null ||
        !actor.active ||
        !actor.isSuperAdmin ||
        tenantId == null) {
      throw StateError(
        'Only a super-admin in an active workspace may permanently delete users',
      );
    }
    final trimmedUid = uid.trim();
    if (trimmedUid.isEmpty) throw ArgumentError('uid must not be empty');
    if (trimmedUid == authUid) {
      throw ArgumentError('Admin cannot delete their own account.');
    }

    final db = FirebaseFirestore.instance;
    final userSnap = await db
        .collection(Collections.users)
        .doc(trimmedUid)
        .get();
    if (!userSnap.exists) throw ArgumentError('User not found: $trimmedUid');

    if (TenantScope.normalize(userSnap.data()?['tenant_id'] as String?) !=
        tenantId) {
      throw StateError('User profile is outside the active workspace');
    }

    final isActive = userSnap.data()?['active'] as bool? ?? true;
    if (isActive) {
      throw StateError(
        'Only deactivated users can be permanently deleted. Deactivate first.',
      );
    }

    await db.collection(Collections.users).doc(trimmedUid).delete();
  }

  Future<void> changeOwnPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No signed-in user found.',
      );
    }

    final email = currentUser.email?.trim();
    if (email == null || email.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'Signed-in user email is missing.',
      );
    }

    final trimmedCurrent = currentPassword.trim();
    final trimmedNew = newPassword.trim();
    if (trimmedCurrent.isEmpty || trimmedNew.isEmpty) {
      throw ArgumentError('Passwords must not be empty');
    }
    if (trimmedNew.length < 8) {
      throw FirebaseAuthException(
        code: 'weak-password',
        message: 'Password is too weak. Use at least 8 characters.',
      );
    }

    final credential = EmailAuthProvider.credential(
      email: email,
      password: trimmedCurrent,
    );

    await currentUser.reauthenticateWithCredential(credential);
    await currentUser.updatePassword(trimmedNew);
  }
}

final userManagementNotifierProvider =
    AsyncNotifierProvider<UserManagementNotifier, void>(
      UserManagementNotifier.new,
    );
