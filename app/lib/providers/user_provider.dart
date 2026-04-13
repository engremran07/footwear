import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../core/services/admin_identity_service.dart';
import '../firebase_options.dart';
import '../models/user_model.dart';
import 'auth_provider.dart';

final allUsersProvider = StreamProvider.autoDispose<List<UserModel>>((ref) {
  // Admin-only list query: guard so non-admin credentials never subscribe,
  // preventing PERMISSION_DENIED during auth transitions.
  final user = ref.watch(authUserProvider).value;
  if (user == null || !user.isAdmin) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection(Collections.users)
      .where('active', isEqualTo: true)
      .orderBy('display_name')
      .limit(100)
      .snapshots()
      .map(
        (snap) =>
            snap.docs.map((d) => UserModel.fromJson(d.data(), d.id)).toList(),
      );
});

final sellersProvider = StreamProvider.autoDispose<List<UserModel>>((ref) {
  // Admin-only list query: guard to prevent PERMISSION_DENIED for seller creds.
  final user = ref.watch(authUserProvider).value;
  if (user == null || !user.isAdmin) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection(Collections.users)
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
  final user = ref.watch(authUserProvider).value;
  if (user == null || !user.isAdmin) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection(Collections.users)
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
    final normalized = role.trim().toLowerCase();
    if (normalized == 'manager') return 'admin';
    if (normalized == 'admin') return 'admin';
    return 'seller';
  }

  Future<void> createUser({
    required String email,
    required String password,
    required String displayName,
    required String role,
    String? phone,
    String? assignedRouteId,
    String? assignedRouteName,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final normalizedRole = _normalizeRole(role);
      final routeId = assignedRouteId?.trim() ?? '';
      if (normalizedRole == 'seller' && routeId.isEmpty) {
        throw ArgumentError('Seller accounts require an assigned route.');
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
          'assigned_route_id': normalizedRole == 'seller' ? routeId : null,
          'assigned_route_name': normalizedRole == 'seller'
              ? assignedRouteName
              : null,
          'active': true,
          'created_by': FirebaseAuth.instance.currentUser!.uid, // RU-04
          'created_at': now,
          'updated_at': now,
        });

        if (normalizedRole == 'seller' && routeId.isNotEmpty) {
          batch.update(db.collection(Collections.routes).doc(routeId), {
            'assigned_seller_id': newUid,
            'assigned_seller_name': trimmedName,
            'updated_at': now,
          });
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
    String? previousRouteId,
  }) async {
    final db = FirebaseFirestore.instance;
    final updateData = <String, dynamic>{...data};
    if (updateData['role'] is String) {
      updateData['role'] = _normalizeRole(updateData['role'] as String);
    }

    final updatedRole = updateData['role'] as String?;
    final normalizedPreviousRouteId = (previousRouteId ?? '').trim();
    final newRouteId = (updateData['assigned_route_id'] as String?)?.trim();
    final displayName = (updateData['display_name'] as String?)?.trim();

    if (updatedRole == 'seller' && (newRouteId == null || newRouteId.isEmpty)) {
      throw ArgumentError('Seller accounts require an assigned route.');
    }

    // Non-seller users must not retain a route assignment.
    if (updatedRole != null && updatedRole != 'seller') {
      updateData['assigned_route_id'] = null;
      updateData['assigned_route_name'] = null;
    } else {
      updateData['assigned_route_id'] = newRouteId;
    }

    // DI-02: use a single WriteBatch for atomicity — user doc + route docs.
    final batch = db.batch();
    final now = Timestamp.now();

    batch.update(db.collection(Collections.users).doc(uid), {
      ...updateData,
      'updated_at': now,
    });

    if (normalizedPreviousRouteId.isNotEmpty &&
        normalizedPreviousRouteId != newRouteId) {
      batch.update(
        db.collection(Collections.routes).doc(normalizedPreviousRouteId),
        {
          'assigned_seller_id': null,
          'assigned_seller_name': null,
          'updated_at': now,
        },
      );
    }

    if (newRouteId != null && newRouteId.isNotEmpty && displayName != null) {
      batch.update(db.collection(Collections.routes).doc(newRouteId), {
        'assigned_seller_id': uid,
        'assigned_seller_name': displayName,
        'updated_at': now,
      });
    }

    await batch.commit();
  }

  Future<void> toggleActive(String uid, bool active) async {
    await FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(uid)
        .update({'active': active, 'updated_at': Timestamp.now()});
  }

  /// Soft-delete: deactivate user + clear route assignments.
  /// Auth account is orphaned but cannot access anything (rules check active).
  Future<void> deleteUser(String uid) async {
    final trimmedUid = uid.trim();
    if (trimmedUid.isEmpty) {
      throw ArgumentError('uid must not be empty');
    }

    final db = FirebaseFirestore.instance;
    final now = Timestamp.now();

    // Clear any route assignments for this seller
    final routeSnap = await db
        .collection(Collections.routes)
        .where('assigned_seller_id', isEqualTo: trimmedUid)
        .limit(20)
        .get();

    final batch = db.batch();
    for (final routeDoc in routeSnap.docs) {
      batch.update(routeDoc.reference, {
        'assigned_seller_id': null,
        'assigned_seller_name': null,
        'updated_at': now,
      });
    }

    // Deactivate the user (soft-delete)
    batch.update(db.collection(Collections.users).doc(trimmedUid), {
      'active': false,
      'updated_at': now,
    });

    await batch.commit();
  }

  /// Send a password-reset email to the seller.
  /// Email is immutable after creation; password can only be reset via email.
  Future<void> sendPasswordResetForSeller({required String email}) async {
    final trimmedEmail = email.trim().toLowerCase();
    if (trimmedEmail.isEmpty) return;
    await FirebaseAuth.instance.sendPasswordResetEmail(email: trimmedEmail);
  }

  /// Reactivates a soft-deleted user and re-assigns them to a route atomically.
  /// DI-06: deleteUser() clears route; must re-assign on reactivation.
  Future<void> reactivateUser({
    required String uid,
    required String routeId,
    required String routeName,
    required String displayName,
  }) async {
    final trimmedUid = uid.trim();
    if (trimmedUid.isEmpty) throw ArgumentError('uid must not be empty');

    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    final now = Timestamp.now();

    batch.update(db.collection(Collections.users).doc(trimmedUid), {
      'active': true,
      'assigned_route_id': routeId.trim().isNotEmpty ? routeId.trim() : null,
      'assigned_route_name': routeId.trim().isNotEmpty
          ? routeName.trim()
          : null,
      'updated_at': now,
    });

    if (routeId.trim().isNotEmpty) {
      batch.update(db.collection(Collections.routes).doc(routeId.trim()), {
        'assigned_seller_id': trimmedUid,
        'assigned_seller_name': displayName.trim(),
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
    final trimmedUid = uid.trim();
    if (trimmedUid.isEmpty) throw ArgumentError('uid must not be empty');
    if (trimmedUid == currentAdminUid.trim()) {
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
