import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../firebase_options.dart';
import '../models/user_model.dart';

// All users — admin-only list screen in Settings
final allUsersProvider = StreamProvider<List<UserModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.users)
      .orderBy('created_at', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs
          .map((doc) => UserModel.fromJson(doc.data(), doc.id))
          .toList());
});

class UserManagementNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Creates a new Firebase Auth user + Firestore doc WITHOUT signing out
  /// the currently signed-in admin, by using a secondary Firebase App instance.
  Future<void> createUser({
    required String email,
    required String password,
    required String displayName,
    required UserRole role,
    required List<String> permissions,
    String? workerId,
    String factoryAccess = 'both',
    String country = 'KSA',
    String currency = 'SAR',
  }) async {
    state = const AsyncLoading();
    FirebaseApp? secondaryApp;
    try {
      secondaryApp = await Firebase.initializeApp(
        name: 'secondary_${DateTime.now().millisecondsSinceEpoch}',
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      final cred = await secondaryAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final uid = cred.user!.uid;
      final now = Timestamp.now();
      final cleanWorkerId = (workerId != null && workerId.trim().isNotEmpty)
          ? workerId.trim()
          : null;
      await FirebaseFirestore.instance
          .collection(Collections.users)
          .doc(uid)
          .set({
        'email': email.trim(),
        'display_name': displayName.trim(),
        'role': _roleToString(role),
        'permissions': permissions,
        'worker_id': cleanWorkerId,
        'factory_access': factoryAccess,
        'country': country,
        'currency': currency,
        'active': true,
        'created_at': now,
        'updated_at': now,
      });
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    } finally {
      await secondaryApp?.delete();
    }
  }

  Future<void> updateRole(String userId, UserRole role) async {
    state = const AsyncLoading();
    try {
      await FirebaseFirestore.instance
          .collection(Collections.users)
          .doc(userId)
          .update({
        'role': _roleToString(role),
        'updated_at': Timestamp.now(),
      });
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> updatePermissions(
      String userId, List<String> permissions) async {
    state = const AsyncLoading();
    try {
      await FirebaseFirestore.instance
          .collection(Collections.users)
          .doc(userId)
          .update({
        'permissions': permissions,
        'updated_at': Timestamp.now(),
      });
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> updateUser(
    String userId, {
    required UserRole role,
    required List<String> permissions,
    required bool active,
    String factoryAccess = 'both',
    String? country,
    String? currency,
  }) async {
    state = const AsyncLoading();
    try {
      final data = <String, dynamic>{
        'role': _roleToString(role),
        'permissions': permissions,
        'active': active,
        'factory_access': factoryAccess,
        'updated_at': Timestamp.now(),
      };
      if (country != null) data['country'] = country;
      if (currency != null) data['currency'] = currency;
      await FirebaseFirestore.instance
          .collection(Collections.users)
          .doc(userId)
          .update(data);
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> setActive(String userId, {required bool active}) async {
    state = const AsyncLoading();
    try {
      await FirebaseFirestore.instance
          .collection(Collections.users)
          .doc(userId)
          .update({
        'active': active,
        'updated_at': Timestamp.now(),
      });
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final userManagementNotifierProvider =
    AsyncNotifierProvider<UserManagementNotifier, void>(
        UserManagementNotifier.new);

String _roleToString(UserRole r) {
  switch (r) {
    case UserRole.admin:
      return 'admin';
    case UserRole.manager:
      return 'manager';
    case UserRole.workerPk:
      return 'worker_pk';
    case UserRole.workerKsa:
      return 'worker_ksa';
    case UserRole.seller:
      return 'seller';
    case UserRole.viewer:
      return 'viewer';
  }
}
