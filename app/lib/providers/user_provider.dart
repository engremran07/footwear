import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../firebase_options.dart';
import '../models/user_model.dart';
import 'auth_provider.dart';

final allUsersProvider = StreamProvider.autoDispose<List<UserModel>>((ref) {
  // Admin-only list query: guard so non-admin credentials never subscribe,
  // preventing PERMISSION_DENIED during auth transitions.
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null || !user.isAdmin) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection(Collections.users)
      .where('active', isEqualTo: true)
      .orderBy('display_name')
      .limit(100)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => UserModel.fromJson(d.data(), d.id)).toList());
});

final sellersProvider = StreamProvider.autoDispose<List<UserModel>>((ref) {
  // Admin-only list query: guard to prevent PERMISSION_DENIED for seller creds.
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null || !user.isAdmin) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection(Collections.users)
      .where('role', isEqualTo: 'seller')
      .where('active', isEqualTo: true)
      .limit(100)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => UserModel.fromJson(d.data(), d.id)).toList());
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
          password: password,
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
          'assigned_route_name':
              normalizedRole == 'seller' ? assignedRouteName : null,
          'active': true,
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

  Future<void> updateUser(String uid, Map<String, dynamic> data) async {
    final db = FirebaseFirestore.instance;
    final updateData = <String, dynamic>{...data};
    if (updateData['role'] is String) {
      updateData['role'] = _normalizeRole(updateData['role'] as String);
    }
    final updatedRole = updateData['role'] as String?;
    final updatedRouteId = updateData['assigned_route_id'] as String?;
    if (updatedRole == 'seller' &&
        (updatedRouteId == null || updatedRouteId.trim().isEmpty)) {
      throw ArgumentError('Seller accounts require an assigned route.');
    }
    await db
        .collection(Collections.users)
        .doc(uid)
        .update({...updateData, 'updated_at': Timestamp.now()});
    // If route assignment changed, update route doc
    final newRouteId = data['assigned_route_id'] as String?;
    final displayName = data['display_name'] as String?;
    if (newRouteId != null && displayName != null) {
      await db.collection(Collections.routes).doc(newRouteId).update({
        'assigned_seller_id': uid,
        'assigned_seller_name': displayName,
        'updated_at': Timestamp.now(),
      });
    }
  }

  /// Clear route assignment from a route doc when seller is unassigned
  Future<void> clearRouteAssignment(String routeId) async {
    await FirebaseFirestore.instance
        .collection(Collections.routes)
        .doc(routeId)
        .update({
      'assigned_seller_id': null,
      'assigned_seller_name': null,
      'updated_at': Timestamp.now(),
    });
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
        UserManagementNotifier.new);
