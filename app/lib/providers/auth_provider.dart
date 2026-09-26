import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_brand.dart';
import '../core/constants/collections.dart';
import '../core/utils/device_pairing.dart';
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
    required String? tenantId,
  }) async {
    final normalizedRole = role.trim().toLowerCase();
    if (!isPrivilegedRoleName(normalizedRole)) return;

    try {
      final settingsDocId =
          TenantScope.normalize(tenantId) ?? TenantScope.globalTenantId;
      final settingsRef = FirebaseFirestore.instance
          .collection(Collections.settings)
          .doc(settingsDocId);
      final settingsSnap = await settingsRef.get();
      if (!settingsSnap.exists) {
        await settingsRef.set({
          'company_name': 'My Business',
          'currency': 'SAR',
          'pairs_per_carton': 12,
          'require_admin_approval_for_seller_transaction_edits': false,
          'tenant_id': settingsDocId,
          'updated_at': Timestamp.now(),
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
    String emailAddress,
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

        final email = emailAddress.trim().toLowerCase();
        if (email.isEmpty || !email.contains('@')) {
          throw FirebaseAuthException(
            code: 'invalid-email',
            message: 'Enter the email address registered to this account.',
          );
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
          await FirebaseAuth.instance.signOut();
          _invalidateRoleScopedProviders();
          throw FirebaseAuthException(
            code: 'permission-denied',
            message:
                'User profile is not provisioned. Contact your workspace administrator.',
          );
        }

        final refreshedDoc = await usersRef.doc(uid).get();
        final userData = refreshedDoc.data();
        final isActive = userData?['active'] == true;
        final normalizedRole = (userData?['role'] as String? ?? '').trim();

        // P1-5 FIX: Check role BEFORE tenant_id self-heal. Super admin must
        // never carry a tenant_id (it's tenant-independent everywhere else).
        // For non-super_admin roles, ensure tenant_id is set to __global__ if null.
        final isSuperAdmin = normalizedRole.toLowerCase() == 'super_admin';
        String? tenantId;
        if (!isSuperAdmin) {
          tenantId = TenantScope.normalize(userData?['tenant_id'] as String?);
          if (tenantId == null) {
            tenantId = TenantScope.globalTenantId;
            await usersRef.doc(uid).set({
              'tenant_id': tenantId,
              'updated_at': Timestamp.now(),
            }, SetOptions(merge: true));
          }
        } else {
          // Super admin: ensure no tenant_id is set by deleting it if present.
          // Use FieldValue.delete() so it won't be re-stamped.
          if (userData?['tenant_id'] != null) {
            await usersRef.doc(uid).set({
              'role': 'super_admin',
              'tenant_id': FieldValue.delete(),
              'active': true,
              'updated_at': Timestamp.now(),
            }, SetOptions(merge: true));
          }
        }
        if (!isActive) {
          await FirebaseAuth.instance.signOut();
          throw FirebaseAuthException(
            code: 'user-disabled',
            message: 'User account is inactive',
          );
        }

        await _runPostSignInSelfHeal(
          uid: uid,
          role: normalizedRole,
          tenantId: tenantId,
        );

        // ── Email-verified sync (Auth → Firestore, non-blocking) ──────────
        // Reload Auth user to get latest emailVerified from Firebase servers.
        // If Auth says verified but Firestore doesn't, sync it now so the
        // Riverpod stream reflects the real state without requiring re-login.
        try {
          await FirebaseAuth.instance.currentUser?.reload();
          final isVerified =
              FirebaseAuth.instance.currentUser?.emailVerified ?? false;
          if (isVerified) {
            final authEmail = FirebaseAuth.instance.currentUser?.email
                ?.trim()
                .toLowerCase();
            final profileEmail = (userData?['email'] as String?)
                ?.trim()
                .toLowerCase();
            await usersRef.doc(uid).update({
              if (authEmail != null && authEmail != profileEmail)
                'email': authEmail,
              if (userData?['email_verified'] != true) 'email_verified': true,
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
          if (tenantId != null && tenantId.isNotEmpty) {
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

    final targetDoc = await FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(targetUserId)
        .get();
    final targetData = targetDoc.data();
    final tenantId =
        (targetData?['tenant_id'] as String?) ??
        (actorData?['tenant_id'] as String?);
    final tenantDoc = tenantId == null || tenantId.isEmpty
        ? null
        : await FirebaseFirestore.instance
              .collection(Collections.tenants)
              .doc(tenantId)
              .get();
    final tenantData = tenantDoc?.data();
    final maxDevicesAllowed =
        ((tenantData?['max_devices_allowed'] as num?) ?? 1).toInt().clamp(
          1,
          999,
        );
    final existingPairings =
        (targetData?['device_pairing_ids'] as List<dynamic>?)
            ?.whereType<String>()
            .toList() ??
        <String>[];

    if (enabled) {
      final normalizedPairingId =
          pairingId ??
          await DevicePairing.generate(
            await DevicePairing.currentDeviceIdentifier(),
            targetUserId,
          );
      final alreadyPaired = existingPairings.contains(normalizedPairingId);
      if (!alreadyPaired && existingPairings.length >= maxDevicesAllowed) {
        throw StateError(
          'Workspace device limit reached ($maxDevicesAllowed).',
        );
      }
      final nextPairings = alreadyPaired
          ? existingPairings
          : [...existingPairings, normalizedPairingId];
      await FirebaseFirestore.instance
          .collection(Collections.users)
          .doc(targetUserId)
          .set({
            'device_pairing_enabled': true,
            'device_pairing_id': normalizedPairingId,
            'device_pairing_ids': nextPairings,
            'device_pairing_reset_by': null,
            'updated_at': Timestamp.now(),
          }, SetOptions(merge: true));
      return;
    }

    final nextPairings = <String>[];
    await FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(targetUserId)
        .set({
          'device_pairing_enabled': false,
          'device_pairing_id': null,
          'device_pairing_ids': nextPairings,
          'device_pairing_reset_by': authUser.uid,
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
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser != null) {
        final profile = await FirebaseFirestore.instance
            .collection(Collections.users)
            .doc(authUser.uid)
            .get();
        final profileData = profile.data();
        if ((profileData?['role'] as String? ?? '').trim().toLowerCase() ==
            'super_admin') {
          final workspaceId = profileData?['active_workspace_id'] as String?;
          final reason = profileData?['active_workspace_reason'] as String?;
          final now = Timestamp.now();
          final batch = FirebaseFirestore.instance.batch();
          final accessLogRef = workspaceId != null && reason != null
              ? FirebaseFirestore.instance
                    .collection(Collections.platformAccessLogs)
                    .doc()
              : null;
          batch.update(profile.reference, {
            'active_workspace_id': FieldValue.delete(),
            'active_workspace_reason': FieldValue.delete(),
            'active_workspace_selected_at': FieldValue.delete(),
            'active_workspace_access_log_id': FieldValue.delete(),
            if (accessLogRef != null)
              'last_workspace_access_log_id': accessLogRef.id,
            'updated_at': now,
          });
          if (accessLogRef != null) {
            batch.set(accessLogRef, {
              'actor_user_id': authUser.uid,
              'workspace_id': workspaceId,
              'event_type': 'workspace_access_ended',
              'reason': reason,
              'created_at': FieldValue.serverTimestamp(),
            });
          }
          await batch.commit();
        }
      }
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
      // S-01: Clear Crashlytics identity on sign-out (FIND-008)
      if (!kIsWeb) {
        FirebaseCrashlytics.instance.setUserIdentifier('');
        FirebaseCrashlytics.instance.setCustomKey('role', 'signed_out');
      }
      _invalidateRoleScopedProviders();
    });
  }

  Future<void> selectWorkspace({
    required String workspaceId,
    required String reason,
  }) async {
    final normalizedId = TenantScope.normalize(workspaceId);
    final normalizedReason = reason.trim();
    if (normalizedId == null ||
        normalizedReason.length < 10 ||
        normalizedReason.length > 240) {
      throw ArgumentError(
        'Choose a workspace and enter a reason of at least 10 characters.',
      );
    }
    final user = await ref.read(authUserProvider.future);
    if (user == null || !user.active || !user.isSuperAdmin) {
      throw StateError('Active super-admin access is required.');
    }
    final db = FirebaseFirestore.instance;
    final workspace = await db
        .collection(Collections.tenants)
        .doc(normalizedId)
        .get();
    if (!workspace.exists || workspace.data()?['active'] != true) {
      throw StateError('The selected workspace is unavailable.');
    }
    final batch = db.batch();
    final accessLogRef = db.collection(Collections.platformAccessLogs).doc();
    batch.update(db.collection(Collections.users).doc(user.id), {
      'active_workspace_id': normalizedId,
      'active_workspace_reason': normalizedReason,
      'active_workspace_selected_at': FieldValue.serverTimestamp(),
      'active_workspace_access_log_id': accessLogRef.id,
      'updated_at': FieldValue.serverTimestamp(),
    });
    batch.set(accessLogRef, {
      'actor_user_id': user.id,
      'workspace_id': normalizedId,
      'event_type': 'workspace_access_started',
      'reason': normalizedReason,
      'created_at': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> endWorkspaceAccess() async {
    final user = await ref.read(authUserProvider.future);
    if (user == null || !user.active || !user.isSuperAdmin) {
      throw StateError('Active super-admin access is required.');
    }
    final batch = FirebaseFirestore.instance.batch();
    final workspaceId = user.activeWorkspaceId;
    final reason = user.activeWorkspaceReason;
    final accessLogRef = workspaceId != null && reason != null
        ? FirebaseFirestore.instance
              .collection(Collections.platformAccessLogs)
              .doc()
        : null;
    batch.update(
      FirebaseFirestore.instance.collection(Collections.users).doc(user.id),
      {
        'active_workspace_id': FieldValue.delete(),
        'active_workspace_reason': FieldValue.delete(),
        'active_workspace_selected_at': FieldValue.delete(),
        'active_workspace_access_log_id': FieldValue.delete(),
        if (accessLogRef != null)
          'last_workspace_access_log_id': accessLogRef.id,
        'updated_at': FieldValue.serverTimestamp(),
      },
    );
    if (accessLogRef != null) {
      batch.set(accessLogRef, {
        'actor_user_id': user.id,
        'workspace_id': workspaceId,
        'event_type': 'workspace_access_ended',
        'reason': reason,
        'created_at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
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
      if (fresh == null) return;
      final doc = await FirebaseFirestore.instance
          .collection(Collections.users)
          .doc(fresh.uid)
          .get();
      if (!doc.exists) return;
      final patch = <String, dynamic>{};
      final authEmail = fresh.email?.trim().toLowerCase();
      final profileEmail = (doc.data()?['email'] as String?)
          ?.trim()
          .toLowerCase();
      if (fresh.emailVerified &&
          authEmail != null &&
          authEmail != profileEmail) {
        patch['email'] = authEmail;
      }
      if (fresh.emailVerified && doc.data()?['email_verified'] != true) {
        patch['email_verified'] = true;
      }
      if (patch.isNotEmpty) {
        patch['updated_at'] = Timestamp.now();
        await FirebaseFirestore.instance
            .collection(Collections.users)
            .doc(fresh.uid)
            .update(patch);
      }
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

  Future<void> sendOwnVerificationEmail() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No signed-in user found.',
      );
    }
    if (currentUser.emailVerified) return;
    await currentUser.sendEmailVerification();
  }

  Future<void> requestOwnEmailChange({
    required String currentPassword,
    required String newEmail,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final currentEmail = currentUser?.email?.trim();
    final normalizedNewEmail = newEmail.trim().toLowerCase();
    if (currentUser == null || currentEmail == null || currentEmail.isEmpty) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No signed-in email account found.',
      );
    }
    if (normalizedNewEmail.isEmpty || !normalizedNewEmail.contains('@')) {
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'Enter a valid email address.',
      );
    }
    if (normalizedNewEmail == currentEmail.toLowerCase()) return;
    final credential = EmailAuthProvider.credential(
      email: currentEmail,
      password: currentPassword,
    );
    await currentUser.reauthenticateWithCredential(credential);
    await currentUser.verifyBeforeUpdateEmail(normalizedNewEmail);
  }

  Future<void> sendPasswordReset(String emailAddress) async {
    final normalizedEmail = emailAddress.trim().toLowerCase();
    if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) {
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'Enter a valid email address.',
      );
    }
    await FirebaseAuth.instance.sendPasswordResetEmail(email: normalizedEmail);
  }
}

final authNotifierProvider = AsyncNotifierProvider<AuthNotifier, void>(
  AuthNotifier.new,
);
