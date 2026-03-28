import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../models/user_model.dart';

final allUsersProvider = StreamProvider<List<UserModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.users)
      .orderBy('display_name')
      .limit(100)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => UserModel.fromJson(d.data(), d.id)).toList());
});

final sellersProvider = StreamProvider<List<UserModel>>((ref) {
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
    if (normalized == 'manager') return 'manager';
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
      // Use secondary app to avoid signing out current admin
      final secondaryApp = await Firebase.initializeApp(
        name: 'secondary_${DateTime.now().millisecondsSinceEpoch}',
        options: Firebase.app().options,
      );
      try {
        final cred = await FirebaseAuth.instanceFor(app: secondaryApp)
            .createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
        final uid = cred.user!.uid;
        final db = FirebaseFirestore.instance;
        await db.collection(Collections.users).doc(uid).set({
          'email': email.trim(),
          'display_name': displayName.trim(),
          'role': normalizedRole,
          'phone': phone,
          'assigned_route_id': assignedRouteId,
          'assigned_route_name': assignedRouteName,
          'active': true,
          'created_at': Timestamp.now(),
          'updated_at': Timestamp.now(),
        });
        // If seller with route, update route's assigned seller
        if (normalizedRole == 'seller' && assignedRouteId != null) {
          await db.collection(Collections.routes).doc(assignedRouteId).update({
            'assigned_seller_id': uid,
            'assigned_seller_name': displayName.trim(),
            'updated_at': Timestamp.now(),
          });
        }
      } finally {
        await secondaryApp.delete();
      }
    });
  }

  Future<void> updateUser(String uid, Map<String, dynamic> data) async {
    final db = FirebaseFirestore.instance;
    final updateData = <String, dynamic>{...data};
    if (updateData['role'] is String) {
      updateData['role'] = _normalizeRole(updateData['role'] as String);
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

  Future<void> adminUpdateSellerAuth({
    required String targetUid,
    String? newEmail,
    String? newPassword,
  }) async {
    final trimmedUid = targetUid.trim();
    final trimmedEmail = newEmail?.trim();
    final trimmedPassword = newPassword?.trim();

    if (trimmedUid.isEmpty) {
      throw ArgumentError('targetUid must not be empty');
    }
    if ((trimmedEmail == null || trimmedEmail.isEmpty) &&
        (trimmedPassword == null || trimmedPassword.isEmpty)) {
      return;
    }

    final callable = FirebaseFunctions.instance.httpsCallable('manageUserAuth');
    await callable.call({
      'targetUid': trimmedUid,
      if (trimmedEmail != null && trimmedEmail.isNotEmpty)
        'newEmail': trimmedEmail,
      if (trimmedPassword != null && trimmedPassword.isNotEmpty)
        'newPassword': trimmedPassword,
    });
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

  /// Sends a password reset email to the given address via Firebase Auth.
  /// Works on both Spark and Blaze plans — no backend function required.
  Future<void> sendPasswordResetEmail(String email) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('email must not be empty');
    }
    await FirebaseAuth.instance.sendPasswordResetEmail(email: trimmed);
  }
}

final userManagementNotifierProvider =
    AsyncNotifierProvider<UserManagementNotifier, void>(
        UserManagementNotifier.new);
