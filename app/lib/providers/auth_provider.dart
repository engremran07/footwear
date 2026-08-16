import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_brand.dart';
import '../core/constants/collections.dart';
import '../core/services/admin_identity_service.dart';
import '../core/utils/role_utils.dart';
import '../core/utils/tenant_scope.dart';
import '../models/user_model.dart';
import 'alert_provider.dart';
import 'dashboard_provider.dart';
import 'inventory_transaction_provider.dart';
import 'invoice_provider.dart';
import 'product_provider.dart';
import 'route_provider.dart';
import 'seller_inventory_provider.dart';
import 'settings_provider.dart';
import 'shop_provider.dart';
import 'transaction_provider.dart';
import 'user_provider.dart';
import 'notification_provider.dart';
import 'history_provider.dart';

final _logger = Logger();
const rememberMePrefKey = 'auth.remember_me';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final authStateProvider = StreamProvider.autoDispose<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

/// Monitors idToken refresh events to detect when Firebase Console disables
/// an account (3-way sync Path 3). On each token refresh the Firebase SDK
/// returns a FirebaseAuthException(code: 'user-disabled') if the account has
/// been disabled server-side, which we map to a forced sign-out.
final authTokenGuardProvider = StreamProvider.autoDispose<void>((ref) async* {
  await for (final user in FirebaseAuth.instance.idTokenChanges()) {
    if (user == null) continue;
    try {
      await user.getIdToken(true); // force server round-trip
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-disabled' || e.code == 'user-token-expired') {
        // Account was disabled in Firebase Console — sign out immediately
        ref.read(authNotifierProvider.notifier).signOut();
      }
    } catch (e) {
      _logger.w('Auth token guard skipped: $e');
    }
  }
});

final authUserProvider = StreamProvider.autoDispose<UserModel?>((ref) {
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
    error: (_, _) => Stream.value(null),
  );
});

class AuthNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> _runPostSignInSelfHeal({
    required String uid,
    required String role,
  }) async {
    final normalizedRole = role.trim().toLowerCase();
    if (!isPrivilegedRoleName(normalizedRole)) return;

    try {
      final globalSettingsRef = FirebaseFirestore.instance
          .collection(Collections.settings)
          .doc('global');
      final settingsSnap = await globalSettingsRef.get();
      if (!settingsSnap.exists) {
        await globalSettingsRef.set({
          'company_name': 'My Business',
          'currency': 'SAR',
          'pairs_per_carton': 12,
          'require_admin_approval_for_seller_transaction_edits': false,
          'updated_at': Timestamp.now(),
          'tenant_id': TenantScope.globalTenantId,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      _logger.w('Post-sign-in settings self-heal skipped: $e');
    }

    try {
      await ref
          .read(routeNotifierProvider.notifier)
          .reconcileRouteShopCounters();
    } catch (e) {
      _logger.w('Post-sign-in route counter self-heal skipped: $e');
    }
  }

  void _invalidateRoleScopedProviders() {
    // Invalidate only the role-scoped providers that need to reset on sign-out.
    // Listing all 28 providers was causing 28 concurrent Firestore listener
    // restarts — a quota spike and UI jank. autoDispose providers self-cancel
    // when no widget watches them, so we only need to reset the core ones.
    ref.invalidate(authUserProvider);
    // NOTE: do NOT explicitly invalidate dashboardStatsProvider here.
    // It is a non-autoDispose Provider that watches authUserProvider (autoDispose).
    // Invalidating both in the same call causes Riverpod 3's priority queue
    // to throw "No lowest priority node found" — it cannot order the rebuild of
    // a dependent before its dependency. dashboardStatsProvider will rebuild
    // automatically when authUserProvider rebuilds.
    // SM-01: Also invalidate the last-good cache so stale stats from the
    // previous session do not flash briefly when a new user signs in.
    ref.invalidate(lastGoodDashboardStatsProvider);
    ref.invalidate(settingsProvider);
    ref.invalidate(allTransactionsProvider);
    ref.invalidate(shopsAnalyticsTransactionsProvider);
    ref.invalidate(pendingEditRequestsProvider);
    ref.invalidate(allInvoicesProvider);
    ref.invalidate(roleAwareInvoicesProvider);
    ref.invalidate(sellerInvoicesProvider);
    ref.invalidate(sellersProvider);
    ref.invalidate(allVariantsProvider);
    // A§4-R17: admin-only providers must be invalidated to prevent data leak
    // across sessions (e.g. admin logs out, seller logs in on same device).
    ref.invalidate(routesProvider);
    ref.invalidate(shopsProvider);
    ref.invalidate(allUsersProvider);
    ref.invalidate(inactiveUsersProvider);
    ref.invalidate(adminAllSellerInventoryProvider);
    ref.invalidate(
      sellerInventoryProvider,
    ); // invalidate all family instances (S7 defense-in-depth)
    ref.invalidate(allInventoryTransactionsProvider);
    ref.invalidate(outstandingShopsProvider);
    // Seller multi-route shops provider — autoDispose but invalidate for
    // defense-in-depth against session data leak.
    ref.invalidate(sellerAllShopsProvider);
    ref.invalidate(routesBySellerProvider);
    // Export providers: admin-only, must be flushed on sign-out so a seller
    // session cannot access cached data from a prior admin session.
    ref.invalidate(sellerTransactionsExportProvider);
    ref.invalidate(sellerInventoryExportProvider);
    ref.invalidate(alertCountsProvider);
    // Notification + history providers scoped to role — flush on session change.
    ref.invalidate(notificationsProvider);
    ref.invalidate(recentTransactionsProvider);
  }

  Future<void> signIn(
    String emailOrUsername,
    String password, {
    bool rememberMe = true,
  }) async {
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
                code: 'invalid-credential',
                message: 'Invalid username or password',
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

        final usersRef = FirebaseFirestore.instance.collection(
          Collections.users,
        );
        final userDoc = await usersRef.doc(uid).get();

        if (!userDoc.exists) {
          _logger.w(
            'Signed in user has no profile document: $uid. Attempting self-heal.',
          );
          // DI-05: clear offline persistence so stale pre-flush cache docs do
          // not serve incorrect state during the self-heal bootstrap flow.
          try {
            await FirebaseFirestore.instance.clearPersistence();
          } catch (e) {
            _logger.w(
              'Missing profile self-heal persistence clear skipped: $e',
            );
          }

          final legacyByEmail = await usersRef
              .where('email', isEqualTo: email)
              .limit(1)
              .get();

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
            final existingPrivilegedLink = await usersRef
                .where(
                  'role',
                  whereIn: ['admin', 'manager', 'tenant_admin', 'super_admin'],
                )
                .limit(1)
                .get();
            if (existingPrivilegedLink.docs.isNotEmpty) {
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
              'display_name': (display != null && display.isNotEmpty)
                  ? display
                  : 'Admin',
              'role': 'admin',
              'tenant_id': TenantScope.globalTenantId,
              'active': true,
              'created_by': uid,
              'created_at': Timestamp.now(),
              'updated_at': Timestamp.now(),
            }, SetOptions(merge: true));
          }
        }

        final refreshedDoc = await usersRef.doc(uid).get();
        final userData = refreshedDoc.data();
        final isActive = userData?['active'] == true;
        final normalizedRole = (userData?['role'] as String? ?? '').trim();
        String? tenantId = TenantScope.normalize(userData?['tenant_id'] as String?);

        if (tenantId == null) {
          tenantId = TenantScope.globalTenantId;
          await usersRef.doc(uid).set({
            'tenant_id': tenantId,
            'updated_at': Timestamp.now(),
          }, SetOptions(merge: true));
        }

        if (normalizedRole.toLowerCase() == 'super_admin') {
          await usersRef.doc(uid).set({
            'role': 'super_admin',
            'tenant_id': tenantId,
            'active': true,
            'updated_at': Timestamp.now(),
          }, SetOptions(merge: true));
        }
        if (!isActive) {
          await FirebaseAuth.instance.signOut();
          throw FirebaseAuthException(
            code: 'user-disabled',
            message: 'User account is inactive',
          );
        }

        await _runPostSignInSelfHeal(uid: uid, role: normalizedRole);

        // ── Email-verified sync (Auth → Firestore, non-blocking) ──────────
        // Reload Auth user to get latest emailVerified from Firebase servers.
        // If Auth says verified but Firestore doesn't, sync it now so the
        // Riverpod stream reflects the real state without requiring re-login.
        try {
          await FirebaseAuth.instance.currentUser?.reload();
          final isVerified =
              FirebaseAuth.instance.currentUser?.emailVerified ?? false;
          if (isVerified) {
            await usersRef.doc(uid).update({
              'email_verified': true,
              'updated_at': Timestamp.now(),
            });
          }
        } catch (e) {
          _logger.w('Email verification sync skipped: $e');
        }
        // ─────────────────────────────────────────────────────────────────

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(rememberMePrefKey, rememberMe);

        _invalidateRoleScopedProviders();
        // S-01: Crashlytics context keys for crash correlation (FIND-008)
        if (!kIsWeb) {
          FirebaseCrashlytics.instance.setUserIdentifier(uid);
          FirebaseCrashlytics.instance.setCustomKey('role', normalizedRole);
          if (tenantId.isNotEmpty) {
            FirebaseCrashlytics.instance.setCustomKey('tenant_id', tenantId);
          }
          FirebaseCrashlytics.instance.setCustomKey(
            'app_version',
            AppBrand.versionDisplay,
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

  Future<void> setDevicePairingState(
    String targetUserId, {
    required bool enabled,
    String? pairingId,
  }) async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      throw StateError('Not authenticated');
    }

    final actorDoc = await FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(authUser.uid)
        .get();
    final actorData = actorDoc.data();
    final actorRole = (actorData?['role'] as String? ?? '').trim();
    if (!isPrivilegedRoleName(actorRole)) {
      throw StateError('Only admin or super admin can manage device pairing');
    }

    await FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(targetUserId)
        .set({
          'device_pairing_enabled': enabled,
          'device_pairing_id': enabled
              ? (pairingId ?? 'paired:$targetUserId')
              : null,
          'device_pairing_reset_by': enabled ? null : authUser.uid,
          'updated_at': Timestamp.now(),
        }, SetOptions(merge: true));
  }

  Future<void> resetDevicePairing(String targetUserId) async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      throw StateError('Not authenticated');
    }

    final actorDoc = await FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(authUser.uid)
        .get();
    final actorData = actorDoc.data();
    final actorRole = (actorData?['role'] as String? ?? '').trim();
    if (!isPrivilegedRoleName(actorRole)) {
      throw StateError('Only admin or super admin can reset device pairing');
    }

    await FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(targetUserId)
        .set({
          'device_pairing_enabled': false,
          'device_pairing_id': null,
          'device_pairing_reset_by': authUser.uid,
          'updated_at': Timestamp.now(),
        }, SetOptions(merge: true));
  }

  Future<void> signOut() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (kIsWeb) {
        try {
          await FirebaseAuth.instance.setPersistence(Persistence.NONE);
        } catch (e) {
          _logger.w('Sign-out persistence reset skipped: $e');
        }
      }
      await FirebaseAuth.instance.signOut();
      try {
        await FirebaseFirestore.instance.clearPersistence();
      } catch (e) {
        _logger.w('Sign-out Firestore cache clear skipped: $e');
      }
      // Clear cached SA OAuth2 token so next admin session gets a fresh one.
      AdminIdentityService.instance.clearCache();
      // S-01: Clear Crashlytics identity on sign-out (FIND-008)
      if (!kIsWeb) {
        FirebaseCrashlytics.instance.setUserIdentifier('');
        FirebaseCrashlytics.instance.setCustomKey('role', 'signed_out');
      }
      _invalidateRoleScopedProviders();
    });
  }

  /// Reload Firebase Auth state from server and sync [email_verified] to
  /// Firestore when it is confirmed verified. This is called on every app
  /// resume so that users who verify their email while the app is backgrounded
  /// see the status update immediately without having to sign out and back in.
  /// [signIn()] already handles the sync at login time; this method covers the
  /// "already authenticated" path where [signIn()] never runs again.
  Future<void> syncEmailVerification() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      // Reload from Firebase Auth servers to get latest emailVerified state.
      await user.reload();
      final fresh = FirebaseAuth.instance.currentUser;
      if (fresh?.emailVerified != true) return;
      // Only hit Firestore if the flag isn't already set — avoids redundant writes.
      final doc = await FirebaseFirestore.instance
          .collection(Collections.users)
          .doc(fresh!.uid)
          .get();
      if (!doc.exists || doc.data()?['email_verified'] == true) return;
      await FirebaseFirestore.instance
          .collection(Collections.users)
          .doc(fresh.uid)
          .update({'email_verified': true, 'updated_at': Timestamp.now()});
    } catch (e) {
      _logger.w('Email verification resync skipped: $e');
    }
  }

  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
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
    final trimmedNew = newPassword.trim();
    if (trimmedNew.length < 8) {
      throw FirebaseAuthException(
        code: 'weak-password',
        message: 'Password is too weak. Use at least 8 characters.',
      );
    }
    await firebaseUser.reauthenticateWithCredential(credential);
    await firebaseUser.updatePassword(trimmedNew);
  }

  Future<void> sendPasswordReset(String emailOrUsername) async {
    var normalizedInput = emailOrUsername.trim();
    if (normalizedInput.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'Email or username is required',
      );
    }

    if (!normalizedInput.contains('@')) {
      final snap = await FirebaseFirestore.instance
          .collection(Collections.users)
          .where('display_name', isEqualTo: normalizedInput)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) {
        throw FirebaseAuthException(
          code: 'invalid-credential',
          message: 'Invalid username or password',
        );
      }
      normalizedInput = (snap.docs.first.data()['email'] as String? ?? '')
          .trim();
    }

    final normalizedEmail = normalizedInput.toLowerCase();
    if (normalizedEmail.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'Email is required',
      );
    }

    await FirebaseAuth.instance.sendPasswordResetEmail(email: normalizedEmail);
  }
}

final authNotifierProvider = AsyncNotifierProvider<AuthNotifier, void>(
  AuthNotifier.new,
);
