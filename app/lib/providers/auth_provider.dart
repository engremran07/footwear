import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/collections.dart';
import '../models/user_model.dart';
import 'dashboard_provider.dart';
import 'invoice_provider.dart';
import 'settings_provider.dart';
import 'user_provider.dart';

final _logger = Logger();
const rememberMePrefKey = 'auth.remember_me';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

/// Monitors idToken refresh events to detect when Firebase Console disables
/// an account (3-way sync Path 3). On each token refresh the Firebase SDK
/// returns a FirebaseAuthException(code: 'user-disabled') if the account has
/// been disabled server-side, which we map to a forced sign-out.
final authTokenGuardProvider = StreamProvider<void>((ref) async* {
  await for (final user
      in FirebaseAuth.instance.idTokenChanges()) {
    if (user == null) continue;
    try {
      await user.getIdToken(true); // force server round-trip
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-disabled' || e.code == 'user-token-expired') {
        // Account was disabled in Firebase Console — sign out immediately
        ref.read(authNotifierProvider.notifier).signOut();
      }
    } catch (_) {}
  }
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

  void _invalidateRoleScopedProviders() {
    // Invalidate only the role-scoped providers that need to reset on sign-out.
    // Listing all 28 providers was causing 28 concurrent Firestore listener
    // restarts — a quota spike and UI jank. autoDispose providers self-cancel
    // when no widget watches them, so we only need to reset the core ones.
    ref.invalidate(authUserProvider);
    ref.invalidate(dashboardStatsProvider);
    ref.invalidate(settingsProvider);
    ref.invalidate(roleAwareInvoicesProvider);
    ref.invalidate(sellerInvoicesProvider);
    ref.invalidate(sellersProvider);
  }

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
            final isBootstrapAdmin = email == 'admin@footwear.pk';
            if (!isBootstrapAdmin) {
              await FirebaseAuth.instance.signOut();
              throw FirebaseAuthException(
                code: 'permission-denied',
                message:
                    'User profile is not provisioned. Ask admin to create your account with route assignment.',
              );
            }

            final display = cred.user?.displayName?.trim();
            await usersRef.doc(uid).set({
              'email': email,
              'display_name':
                  (display != null && display.isNotEmpty) ? display : 'Admin',
              'role': 'admin',
              'active': true,
              'created_by': uid,
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

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(rememberMePrefKey, rememberMe);

        _invalidateRoleScopedProviders();
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
      _invalidateRoleScopedProviders();
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
