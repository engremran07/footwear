import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/collections.dart';

class BootstrapNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> createCurrentAdminProfile() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser == null) {
        throw StateError('You must be signed in to bootstrap profile.');
      }

      final email = (authUser.email ?? '').trim().toLowerCase();
      if (email.isEmpty) {
        throw StateError(
          'Bootstrap requires a signed-in account with an email address.',
        );
      }

      final db = FirebaseFirestore.instance;
      final userRef = db.collection(Collections.users).doc(authUser.uid);
      final existing = await userRef.get();
      if (existing.exists) {
        return;
      }

      final adminSnap = await db
          .collection(Collections.users)
          .where('role', whereIn: ['admin', 'manager'])
          .limit(1)
          .get();

      if (adminSnap.docs.isNotEmpty &&
          adminSnap.docs.first.id != authUser.uid) {
        throw StateError(
          'An admin profile already exists. Bootstrap is disabled.',
        );
      }

      await userRef.set({
        'email': email,
        'display_name': (authUser.displayName ?? 'Admin').trim(),
        'role': 'admin',
        'active': true,
        'created_at': Timestamp.now(),
        'updated_at': Timestamp.now(),
      });
    });

    if (state.hasError && state.error != null) {
      throw state.error!;
    }
  }
}

final bootstrapNotifierProvider =
    AsyncNotifierProvider<BootstrapNotifier, void>(BootstrapNotifier.new);
