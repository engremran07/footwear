import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import '../core/constants/collections.dart';
import '../models/user_model.dart';

final _logger = Logger();

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

final authUserProvider = StreamProvider<UserModel?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (user) {
      if (user == null) return Stream.value(null);
      return FirebaseFirestore.instance
          .collection(Collections.users)
          .doc(user.uid)
          .snapshots()
          .map((doc) {
        if (!doc.exists) return null;
        return UserModel.fromJson(doc.data()!, doc.id);
      });
    },
    loading: () => Stream.value(null),
    error: (_, __) => Stream.value(null),
  );
});

class AuthNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> signIn(String emailOrUsername, String password,
      {bool rememberMe = true}) async {
    state = const AsyncLoading();
    final nextState = await AsyncValue.guard(() async {
      try {
        if (kIsWeb) {
          try {
            if (!rememberMe) {
              await FirebaseAuth.instance.setPersistence(Persistence.SESSION);
            } else {
              await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
            }
          } catch (e) {
            _logger.w('Persistence error: $e');
          }
        }

        String email = emailOrUsername.trim();

        // If not an email, look up by display_name in Firestore
        if (!email.contains('@')) {
          try {
            final snap = await FirebaseFirestore.instance
                .collection(Collections.users)
                .where('display_name', isEqualTo: email)
                .limit(1)
                .get();
            if (snap.docs.isEmpty) {
              throw FirebaseAuthException(
                code: 'user-not-found',
                message: 'No user found with that username',
              );
            }
            email = (snap.docs.first.data()['email'] as String).trim();
          } catch (e) {
            _logger.e('Username lookup failed: $e');
            rethrow;
          }
        }

        if (email.contains('@')) {
          email = email.toLowerCase();
        }

        // Sign in with email and password
        final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );

        // Ensure linked app profile exists; otherwise routing appears to "do nothing".
        final uid = cred.user?.uid;
        if (uid == null) {
          throw FirebaseAuthException(
            code: 'user-not-found',
            message: 'Authenticated user is missing UID',
          );
        }

        final usersRef =
            FirebaseFirestore.instance.collection(Collections.users);
        final userDoc = await usersRef.doc(uid).get();

        if (!userDoc.exists) {
          _logger.w(
              'Signed in user has no profile document: $uid. Attempting self-heal.');

          final legacyByEmail =
              await usersRef.where('email', isEqualTo: email).limit(1).get();

          if (legacyByEmail.docs.isNotEmpty) {
            final data = legacyByEmail.docs.first.data();
            await usersRef.doc(uid).set({
              ...data,
              'email': email,
              'active': data['active'] ?? true,
              'updated_at': Timestamp.now(),
              'created_at': data['created_at'] ?? Timestamp.now(),
            }, SetOptions(merge: true));
          } else {
            final display = cred.user?.displayName?.trim();
            await usersRef.doc(uid).set({
              'email': email,
              'display_name': (display != null && display.isNotEmpty)
                  ? display
                  : email.split('@').first,
              'role': 'seller',
              'active': true,
              'created_at': Timestamp.now(),
              'updated_at': Timestamp.now(),
            }, SetOptions(merge: true));
          }
        }

        final refreshedDoc = await usersRef.doc(uid).get();
        final isActive = refreshedDoc.data()?['active'] == true;
        if (!isActive) {
          await FirebaseAuth.instance.signOut();
          throw FirebaseAuthException(
            code: 'user-disabled',
            message: 'User account is inactive',
          );
        }
      } on FirebaseAuthException catch (e) {
        _logger.e('Auth error [${e.code}]: ${e.message}');
        rethrow;
      } catch (e) {
        _logger.e('Sign-in error: $e');
        rethrow;
      }
    });

    state = nextState;

    // Re-throw async state errors so caller UI can show user-facing feedback.
    if (nextState.hasError && nextState.error != null) {
      final st = nextState.stackTrace;
      if (st != null) {
        Error.throwWithStackTrace(nextState.error!, st);
      }
      throw nextState.error!;
    }
  }

  Future<void> signOut() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await FirebaseAuth.instance.signOut();
    });
  }

  Future<void> changePassword(
      String currentPassword, String newPassword) async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null || firebaseUser.email == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No user signed in',
      );
    }
    final credential = EmailAuthProvider.credential(
      email: firebaseUser.email!,
      password: currentPassword,
    );
    await firebaseUser.reauthenticateWithCredential(credential);
    await firebaseUser.updatePassword(newPassword);
  }
}

final authNotifierProvider =
    AsyncNotifierProvider<AuthNotifier, void>(AuthNotifier.new);
