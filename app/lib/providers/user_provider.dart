import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../core/services/admin_identity_service.dart';
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
  final snap = await query.limit(200).get();
  return snap.docs.map((d) => UserModel.fromJson(d.data(), d.id)).toList();
});

final sellersProvider = StreamProvider.autoDispose<List<UserModel>>((ref) {
  // Account management is separate from tenant/workspace management. This
  // seller roster is still admin-controlled, but tenant_admin cannot use it.
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
      .where('role', isEqualTo: 'seller')
      .where('active', isEqualTo: true)
      .limit(100)
      .snapshots()
      .map(
        (snap) =>
            snap.docs.map((d) => UserModel.fromJson(d.data(), d.id)).toList(),
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

  Future<String> _requireAdminUid() async {
    final authUser = FirebaseAuth.instance.currentUser;
    final adminUid = authUser?.uid.trim() ?? '';
    if (adminUid.isEmpty) {
      throw StateError('No authenticated user found');
    }
    if (!await _isCurrentUserAdmin()) {
      throw StateError('Admin privileges required');
    }
    return adminUid;
  }

  Future<void> createUser({
    required String email,
    required String password,
    required String displayName,
    required String role,
    String? phone,
    List<String> assignedRouteIds = const [],
    List<String> assignedRouteNames = const [],
    String? tenantId,
  }) async {
    final adminUid = await _requireAdminUid();
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final normalizedRole = _normalizeRole(role);
      if (normalizedRole == 'seller' && assignedRouteIds.isEmpty) {
        throw ArgumentError(
          'Seller accounts require at least one assigned route.',
        );
      }

      final trimmedEmail = email.trim().toLowerCase();
      final trimmedName = displayName.trim();
      final trimmedPassword = password.trim();
      if (trimmedPassword.length < 8) {
        throw FirebaseAuthException(
          code: 'weak-password',
          message: 'Password is too weak. Use at least 8 characters.',
        );
      }

      // Use provided tenantId or fall back to current user's tenant
      final effectiveTenantId =
          TenantScope.normalize(tenantId) ??
          TenantScope.normalize(ref.read(authUserProvider).value?.tenantId) ??
          TenantScope.globalTenantId;

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

        // Sign out immediately from the temp app (we only needed the UID)
        await tempAuth.signOut();

        // Write the Firestore profile + route assignment in a batch
        final db = FirebaseFirestore.instance;
        final batch = db.batch();
        final now = Timestamp.now();

        batch.set(db.collection(Collections.users).doc(newUid), {
          'email': trimmedEmail,
          'display_name': trimmedName,
          'role': normalizedRole,
          'tenant_id': effectiveTenantId,
          'assigned_route_ids': normalizedRole == 'seller'
              ? assignedRouteIds
              : [],
          'assigned_route_names': normalizedRole == 'seller'
              ? assignedRouteNames
              : [],
          'active': true,
          'created_by': adminUid,
          'created_at': now,
          'updated_at': now,
        });

        // Add this seller to each assigned route
        if (normalizedRole == 'seller') {
          for (final routeId in assignedRouteIds) {
            if (routeId.trim().isEmpty) continue;
            batch.update(db.collection(Collections.routes).doc(routeId), {
              'assigned_seller_ids': FieldValue.arrayUnion([newUid]),
              'assigned_seller_names': FieldValue.arrayUnion([trimmedName]),
              'updated_at': now,
            });
          }
        }

        await batch.commit();
      } on FirebaseAuthException {
        rethrow; // Let AppErrorMapper handle auth errors (email-in-use, etc.)
      } finally {
        // S-04: Dispose the secondary app to prevent resource leaks
        try {
          await tempApp.delete();
        } catch (_) {}
      }
    });
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
    }

    final hasRoleUpdate = updateData.containsKey('role');
    final hasRouteIdsUpdate = updateData.containsKey('assigned_route_ids');
    final updatedRole = hasRoleUpdate ? updateData['role'] as String? : null;
    final newRouteIds = hasRouteIdsUpdate
        ? List<String>.from(updateData['assigned_route_ids'] as List? ?? [])
        : <String>[];
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
      if (updatedRole == 'seller' && newRouteIds.isEmpty && hasRouteIdsUpdate) {
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

  Future<void> transferUserToWorkspace({
    required String uid,
    required String targetTenantId,
  }) async {
    final trimmedUid = uid.trim();
    final normalizedTarget = TenantScope.normalize(targetTenantId);
    if (trimmedUid.isEmpty ||
        normalizedTarget == null ||
        normalizedTarget.isEmpty) {
      throw ArgumentError('A valid target workspace is required.');
    }

    final actingUser = FirebaseAuth.instance.currentUser;
    if (actingUser == null) {
      throw StateError('No authenticated user found');
    }

    final db = FirebaseFirestore.instance;
    final actingSnap = await db
        .collection(Collections.users)
        .doc(actingUser.uid)
        .get();
    if (!actingSnap.exists) {
      throw StateError('Acting user profile not found.');
    }

    final actingUserModel = UserModel.fromJson(
      actingSnap.data()!,
      actingSnap.id,
    );
    if (!canManageUserAccountsRole(
      roleValueFromUserRole(actingUserModel.role),
    )) {
      throw StateError(
        'Only workspace managers can move users between workspaces.',
      );
    }

    final currentTenant = TenantScope.normalize(
      (await db.collection(Collections.users).doc(trimmedUid).get())
              .data()?['tenant_id']
          as String?,
    );

    if (!actingUserModel.isSuperAdmin) {
      final actingTenant = TenantScope.normalize(actingUserModel.tenantId);
      if (actingTenant == null || actingTenant != normalizedTarget) {
        throw StateError(
          'You can only move users within your current workspace.',
        );
      }
    }

    if (currentTenant == normalizedTarget) {
      return;
    }

    final batch = db.batch();
    batch.update(db.collection(Collections.users).doc(trimmedUid), {
      'tenant_id': normalizedTarget,
      'updated_at': Timestamp.now(),
    });

    await batch.commit();
  }

  Future<void> toggleActive(String uid, bool active) async {
    await _requireAdminUid();
    final trimmedUid = uid.trim();
    if (trimmedUid.isEmpty) {
      throw ArgumentError('uid must not be empty');
    }
    await FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(trimmedUid)
        .update({'active': active, 'updated_at': Timestamp.now()});
  }

  /// Soft-delete: deactivate user + clear route assignments.
  /// Auth account is orphaned but cannot access anything (rules check active).
  Future<void> deleteUser(String uid) async {
    await _requireAdminUid();
    final trimmedUid = uid.trim();
    if (trimmedUid.isEmpty) {
      throw ArgumentError('uid must not be empty');
    }

    final db = FirebaseFirestore.instance;
    final now = Timestamp.now();

    // Read user doc to get display_name for arrayRemove
    final userDoc = await db
        .collection(Collections.users)
        .doc(trimmedUid)
        .get();
    final userName = (userDoc.data()?['display_name'] as String?) ?? '';

    // Clear seller from all assigned routes (array + legacy scalar)
    final routeSnap = await db
        .collection(Collections.routes)
        .where('assigned_seller_ids', arrayContains: trimmedUid)
        .limit(20)
        .get();

    final batch = db.batch();
    for (final routeDoc in routeSnap.docs) {
      batch.update(routeDoc.reference, {
        'assigned_seller_ids': FieldValue.arrayRemove([trimmedUid]),
        'assigned_seller_names': FieldValue.arrayRemove(
          userName.isNotEmpty ? [userName] : [],
        ),
        'updated_at': now,
      });
    }

    // Deactivate the user (soft-delete)
    batch.update(db.collection(Collections.users).doc(trimmedUid), {
      'active': false,
      'assigned_route_ids': [],
      'assigned_route_names': [],
      'updated_at': now,
    });

    await batch.commit();
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
    await _requireAdminUid();
    final trimmedUid = uid.trim();
    if (trimmedUid.isEmpty) throw ArgumentError('uid must not be empty');

    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    final now = Timestamp.now();
    final trimmedName = displayName.trim();

    batch.update(db.collection(Collections.users).doc(trimmedUid), {
      'active': true,
      'assigned_route_ids': routeIds,
      'assigned_route_names': routeNames,
      'updated_at': now,
    });

    for (final routeId in routeIds) {
      if (routeId.trim().isEmpty) continue;
      batch.update(db.collection(Collections.routes).doc(routeId.trim()), {
        'assigned_seller_ids': FieldValue.arrayUnion([trimmedUid]),
        'assigned_seller_names': FieldValue.arrayUnion(
          trimmedName.isNotEmpty ? [trimmedName] : [],
        ),
        'updated_at': now,
      });
    }

    await batch.commit();
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
    final adminUid = await _requireAdminUid();
    final trimmedUid = uid.trim();
    if (trimmedUid.isEmpty) throw ArgumentError('uid must not be empty');
    if (trimmedUid == adminUid || trimmedUid == currentAdminUid.trim()) {
      throw ArgumentError('Admin cannot delete their own account.');
    }

    final db = FirebaseFirestore.instance;
    final userSnap = await db
        .collection(Collections.users)
        .doc(trimmedUid)
        .get();
    if (!userSnap.exists) throw ArgumentError('User not found: $trimmedUid');

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

  // ── Admin 4-Way Sync Auth Pipeline ───────────────────────────────────────

  FirebaseAuthException _mapAdminIdentityError(Object error) {
    final msg = error.toString();
    final lower = msg.toLowerCase();
    if (lower.contains('sa credentials not provisioned')) {
      return FirebaseAuthException(
        code: 'operation-not-allowed',
        message:
            'Admin credentials are not configured. Contact system administrator.',
      );
    }
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return FirebaseAuthException(
        code: 'network-request-failed',
        message: 'Admin identity service request timed out.',
      );
    }
    return FirebaseAuthException(code: 'operation-not-allowed', message: msg);
  }

  /// Admin-only: Update email, password, and/or emailVerified for ANY user.
  ///
  /// 4-way sync:
  ///   1. Firebase Auth  → AdminIdentityService (SA JWT → OAuth2 → REST API)
  ///   2. Firestore      → atomic doc update (email + email_verified fields)
  ///   3. Riverpod       → allUsersProvider / authUserProvider streams auto-fire
  ///   4. UI             → re-renders from Riverpod state (no manual refresh needed)
  ///
  /// Admin self-email changes are synced the same way — the Riverpod authUserProvider
  /// stream picks up the Firestore change and the profile re-renders automatically.
  Future<void> adminUpdateUserAuth({
    required String uid,
    String? newEmail,
    String? newPassword,
    bool? emailVerified,
  }) async {
    await _requireAdminUid();
    final trimmedEmail = newEmail?.trim().toLowerCase();
    final trimmedPassword = newPassword?.trim();

    final hasEmailChange = trimmedEmail != null && trimmedEmail.isNotEmpty;
    final hasPasswordChange =
        trimmedPassword != null && trimmedPassword.isNotEmpty;

    if (hasPasswordChange && trimmedPassword.length < 8) {
      throw FirebaseAuthException(
        code: 'weak-password',
        message: 'Password is too weak. Use at least 8 characters.',
      );
    }

    if (!hasEmailChange && !hasPasswordChange && emailVerified == null) return;

    // Step 1: Update Firebase Auth via SA OAuth2 (Identity Toolkit admin API)
    try {
      await AdminIdentityService.instance.updateAuthUser(
        uid: uid,
        email: hasEmailChange ? trimmedEmail : null,
        password: hasPasswordChange ? trimmedPassword : null,
        // New email → mark unverified; explicit override allowed
        emailVerified: hasEmailChange ? false : emailVerified,
      );
    } catch (e) {
      throw _mapAdminIdentityError(e);
    }

    // Step 2: Sync Firestore (only changed fields — keeps batch minimal)
    final fsUpdate = <String, dynamic>{'updated_at': Timestamp.now()};
    if (hasEmailChange) {
      fsUpdate['email'] = trimmedEmail;
      fsUpdate['email_verified'] = false; // new email, needs re-verification
    }
    if (!hasEmailChange && emailVerified != null) {
      fsUpdate['email_verified'] = emailVerified;
    }

    await FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(uid)
        .update(fsUpdate);
    // Steps 3+4: Riverpod allUsersProvider / authUserProvider are real-time
    // Firestore streams → auto-fire on doc change → UI re-renders.
  }

  /// Admin-only: Send email verification to any user.
  /// Requires both [uid] and [email] — see AdminIdentityService for 3-step flow.
  Future<void> adminSendVerificationEmail(String uid, String email) async {
    await _requireAdminUid();
    try {
      await AdminIdentityService.instance.sendVerificationEmail(
        uid,
        email.trim().toLowerCase(),
      );
    } catch (e) {
      throw _mapAdminIdentityError(e);
    }
  }

  /// Admin-only: Explicitly mark a user's email as verified in Auth + Firestore.
  Future<void> adminMarkEmailVerified(String uid) async {
    await adminUpdateUserAuth(uid: uid, emailVerified: true);
  }
}

final userManagementNotifierProvider =
    AsyncNotifierProvider<UserManagementNotifier, void>(
      UserManagementNotifier.new,
    );
