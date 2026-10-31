import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_brand.dart';
import '../core/constants/collections.dart';
import '../core/utils/auth_refresh_policy.dart';
import '../core/utils/role_utils.dart';
import '../core/utils/tenant_scope.dart';
import '../models/user_model.dart';
import 'alert_provider.dart';
import 'archive_provider.dart';
import 'dashboard_provider.dart';
import 'inventory_transaction_provider.dart';
import 'invoice_provider.dart';
import 'product_provider.dart';
import 'route_provider.dart';
import 'seller_inventory_provider.dart';
import 'settings_provider.dart';
import 'shop_provider.dart';
import 'tenant_provider.dart';
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
    // previous account do not flash briefly when a new user signs in.
    ref.invalidate(lastGoodDashboardStatsProvider);
    ref.invalidate(settingsProvider);
    ref.invalidate(archivedBusinessRecordsProvider);
    ref.invalidate(allTransactionsProvider);
    ref.invalidate(shopsAnalyticsTransactionsProvider);
    ref.invalidate(pendingEditRequestsProvider);
    ref.invalidate(allInvoicesProvider);
    ref.invalidate(roleAwareInvoicesProvider);
    ref.invalidate(sellerInvoicesProvider);
    ref.invalidate(sellersProvider);
    ref.invalidate(allVariantsProvider);
    ref.invalidate(allVariantsExportProvider);
    // A§4-R17: admin-only providers must be invalidated to prevent data leaks
    // across account changes (e.g. an admin logs out and a seller logs in).
    ref.invalidate(routesProvider);
    ref.invalidate(routesExportProvider);
    ref.invalidate(shopsProvider);
    ref.invalidate(shopsExportProvider);
    ref.invalidate(allUsersProvider);
    ref.invalidate(inactiveUsersProvider);
    ref.invalidate(allUsersExportProvider);
    ref.invalidate(adminAllSellerInventoryProvider);
    ref.invalidate(
      sellerInventoryProvider,
    ); // invalidate all family instances (S7 defense-in-depth)
    ref.invalidate(allInventoryTransactionsProvider);
    ref.invalidate(outstandingShopsProvider);
    // Seller multi-route shops provider — autoDispose but invalidate for
    // defense-in-depth against cross-account data exposure.
    ref.invalidate(sellerAllShopsProvider);
    ref.invalidate(routesBySellerProvider);
    // Export providers: admin-only, must be flushed on sign-out so a seller
    // account cannot access cached data from a prior admin account.
    ref.invalidate(sellerTransactionsExportProvider);
    ref.invalidate(allTransactionsExportProvider);
    ref.invalidate(sellerInventoryExportProvider);
    ref.invalidate(alertCountsProvider);
    // Notification + history providers scoped to role — flush on account change.
    ref.invalidate(notificationsProvider);
    ref.invalidate(recentTransactionsProvider);
    ref.invalidate(tenantUsersProvider);
    ref.invalidate(tenantWorkspaceUsersProvider);
    ref.invalidate(allInactiveUsersForTenantProvider);
  }

  Future<void> _signOutIfCurrentUid(String expectedUid) async {
    if (FirebaseAuth.instance.currentUser?.uid != expectedUid) return;
    await FirebaseAuth.instance.signOut();
    if (FirebaseAuth.instance.currentUser == null) {
      _invalidateRoleScopedProviders();
    }
  }

  String _appendWorkspaceAccessEndLog(
    FirebaseFirestore db,
    WriteBatch batch, {
    required String actorUserId,
    required String workspaceId,
    required String reason,
    String? startedLogId,
  }) {
    final normalizedWorkspaceId = TenantScope.normalize(workspaceId);
    final normalizedReason = reason.trim();
    if (normalizedWorkspaceId == null ||
        normalizedReason.length < 10 ||
        normalizedReason.length > 240) {
      throw StateError('The active workspace support context is invalid.');
    }

    final logRef = db.collection(Collections.platformAccessLogs).doc();
    batch.set(logRef, {
      'actor_user_id': actorUserId,
      'workspace_id': normalizedWorkspaceId,
      'event_type': 'workspace_access_ended',
      'reason': normalizedReason,
      if (startedLogId?.trim().isNotEmpty == true)
        'started_log_id': startedLogId!.trim(),
      'created_at': FieldValue.serverTimestamp(),
    });
    return logRef.id;
  }

  Future<UserModel> _requireActiveSuperAdminProfileFromServer() async {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw StateError('Active super-admin access is required.');
    }
    final profile = await FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    if (FirebaseAuth.instance.currentUser?.uid != uid || !profile.exists) {
      throw StateError('Active super-admin access is required.');
    }
    final user = UserModel.fromJson(profile.data()!, profile.id);
    if (!user.active || !user.isSuperAdmin) {
      throw StateError('Active super-admin access is required.');
    }
    return user;
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
          await _signOutIfCurrentUid(uid);
          throw FirebaseAuthException(
            code: 'permission-denied',
            message: 'User profile is not provisioned. Contact your workspace administrator.',
          );
        }

        final userData = userDoc.data();
        final isActive = userData?['active'] == true;
        final normalizedRole = normalizeRoleName(
          userData?['role'] as String? ?? '',
        );
        if (normalizedRole == 'unknown') {
          await _signOutIfCurrentUid(uid);
          throw FirebaseAuthException(
            code: 'invalid-user-role',
            message: 'This account has an unsupported role. Contact your administrator.',
          );
        }

        // Tenant assignment is provisioned by a workspace administrator, never
        // inferred from a client sign-in.
        final isSuperAdmin = normalizedRole == 'super_admin';
        String? tenantId;
        if (!isSuperAdmin) {
          tenantId = TenantScope.normalize(userData?['tenant_id'] as String?);
          if (tenantId == null) {
            await _signOutIfCurrentUid(uid);
            throw FirebaseAuthException(
              code: 'account-not-assigned-to-workspace',
              message: 'Your account is not assigned to a workspace. Contact your administrator.',
            );
          }
        }
        if (!isActive) {
          await _signOutIfCurrentUid(uid);
          throw FirebaseAuthException(
            code: 'user-disabled',
            message: 'User account is inactive',
          );
        }

        // ── Email-verified sync (Auth → Firestore, non-blocking) ──────────
        // Reload Auth user to get latest emailVerified from Firebase servers.
        // If Auth says verified but Firestore doesn't, sync it now so the
        // Riverpod stream reflects the real state without requiring re-login.
        try {
          await FirebaseAuth.instance.currentUser?.reload();
          final freshAuthUser = FirebaseAuth.instance.currentUser;
          if (freshAuthUser != null &&
              freshAuthUser.uid == uid &&
              freshAuthUser.emailVerified) {
            final authEmail = freshAuthUser.email?.trim().toLowerCase();
            final profileEmail = (userData?['email'] as String?)
                ?.trim()
                .toLowerCase();
            final patch = <String, dynamic>{
              if (authEmail != null && authEmail != profileEmail)
                'email': authEmail,
              if (userData?['email_verified'] != true) 'email_verified': true,
            };
            if (patch.isNotEmpty) {
              await freshAuthUser.getIdToken(true);
              if (FirebaseAuth.instance.currentUser?.uid == uid) {
                await usersRef.doc(uid).update({
                  ...patch,
                  'updated_at': Timestamp.now(),
                });
              }
            }
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

  Future<void> verifyAuthAccountOnResume() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final checkedUid = user.uid;
    try {
      await user.reload();
    } on FirebaseAuthException catch (error, stackTrace) {
      if (FirebaseAuth.instance.currentUser?.uid != checkedUid) return;
      if (shouldSignOutAfterAuthRefreshFailure(error.code)) {
        _logger.w('Signing out disabled or missing account: ${error.code}');
        await _signOutIfCurrentUid(checkedUid);
        _invalidateRoleScopedProviders();
      } else {
        _logger.w(
          'Auth account verification deferred: ${error.code}',
          error: error,
          stackTrace: stackTrace,
        );
      }
    } catch (error, stackTrace) {
      _logger.w(
        'Auth account verification deferred',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> signOut({String? expectedUid}) async {
    if (expectedUid != null &&
        FirebaseAuth.instance.currentUser?.uid != expectedUid) {
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final authUser = FirebaseAuth.instance.currentUser;
      if (expectedUid != null && authUser?.uid != expectedUid) return;
      try {
        if (authUser != null) {
          final profile = await FirebaseFirestore.instance
              .collection(Collections.users)
              .doc(authUser.uid)
              .get();
          final profileData = profile.data();
          if ((profileData?['role'] as String? ?? '').trim().toLowerCase() ==
              'super_admin') {
            final workspaceId = TenantScope.normalize(
              profileData?['active_workspace_id'] as String?,
            );
            if (workspaceId != null) {
              final reason =
                  profileData?['active_workspace_reason'] as String? ?? '';
              final batch = FirebaseFirestore.instance.batch();
              final endLogId = _appendWorkspaceAccessEndLog(
                FirebaseFirestore.instance,
                batch,
                actorUserId: authUser.uid,
                workspaceId: workspaceId,
                reason: reason,
                startedLogId:
                    profileData?['active_workspace_access_log_id'] as String?,
              );
              batch.update(profile.reference, {
                'active_workspace_id': FieldValue.delete(),
                'active_workspace_reason': FieldValue.delete(),
                'active_workspace_selected_at': FieldValue.delete(),
                'active_workspace_access_log_id': FieldValue.delete(),
                'last_workspace_access_end_log_id': endLogId,
                'updated_at': Timestamp.now(),
              });
              await batch.commit();
            }
          }
        }
      } catch (e, stack) {
        _logger.e(
          'Workspace exit audit failed during sign-out',
          error: e,
          stackTrace: stack,
        );
      }
      if (FirebaseAuth.instance.currentUser?.uid != authUser?.uid) {
        _logger.w('Sign-out skipped because the current account changed');
        return;
      }
      if (kIsWeb) {
        try {
          await FirebaseAuth.instance.setPersistence(Persistence.NONE);
        } catch (e) {
          _logger.w('Sign-out persistence reset skipped: $e');
        }
      }
      if (FirebaseAuth.instance.currentUser?.uid != authUser?.uid) {
        _logger.w('Sign-out skipped because the current account changed');
        return;
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
    final user = await _requireActiveSuperAdminProfileFromServer();
    final db = FirebaseFirestore.instance;
    final workspace = await db
        .collection(Collections.tenants)
        .doc(normalizedId)
        .get();
    if (!workspace.exists) {
      throw StateError('The selected workspace is unavailable.');
    }
    // Selecting an inactive tenant only establishes audited lifecycle context;
    // Firestore Rules still deny business-data access until it is restored.
    final batch = db.batch();
    final previousWorkspaceId = TenantScope.normalize(user.activeWorkspaceId);
    final previousReason = user.activeWorkspaceReason?.trim();
    final previousEndLogId = previousWorkspaceId == null
        ? null
        : _appendWorkspaceAccessEndLog(
            db,
            batch,
            actorUserId: user.id,
            workspaceId: previousWorkspaceId,
            reason: previousReason ?? '',
            startedLogId: user.activeWorkspaceAccessLogId,
          );
    final accessLogRef = db.collection(Collections.platformAccessLogs).doc();
    batch.update(db.collection(Collections.users).doc(user.id), {
      'active_workspace_id': normalizedId,
      'active_workspace_reason': normalizedReason,
      'active_workspace_selected_at': FieldValue.serverTimestamp(),
      'active_workspace_access_log_id': accessLogRef.id,
      'last_workspace_access_end_log_id': ?previousEndLogId,
      'updated_at': FieldValue.serverTimestamp(),
    });
    batch.set(accessLogRef, {
      'actor_user_id': user.id,
      'workspace_id': normalizedId,
      'event_type': 'workspace_access_started',
      'reason': normalizedReason,
      'created_at': FieldValue.serverTimestamp(),
    });
    ref.invalidate(lastGoodDashboardStatsProvider);
    await batch.commit();
  }

  Future<void> endWorkspaceAccess() async {
    final user = await _requireActiveSuperAdminProfileFromServer();
    final batch = FirebaseFirestore.instance.batch();
    final workspaceId = TenantScope.normalize(user.activeWorkspaceId);
    if (workspaceId == null) return;
    final reason = user.activeWorkspaceReason?.trim() ?? '';
    final endLogId = _appendWorkspaceAccessEndLog(
      FirebaseFirestore.instance,
      batch,
      actorUserId: user.id,
      workspaceId: workspaceId,
      reason: reason,
      startedLogId: user.activeWorkspaceAccessLogId,
    );
    batch.update(
      FirebaseFirestore.instance.collection(Collections.users).doc(user.id),
      {
        'active_workspace_id': FieldValue.delete(),
        'active_workspace_reason': FieldValue.delete(),
        'active_workspace_selected_at': FieldValue.delete(),
        'active_workspace_access_log_id': FieldValue.delete(),
        'last_workspace_access_end_log_id': endLogId,
        'updated_at': FieldValue.serverTimestamp(),
      },
    );
    ref.invalidate(lastGoodDashboardStatsProvider);
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
        await fresh.getIdToken(true);
        if (FirebaseAuth.instance.currentUser?.uid != fresh.uid ||
            FirebaseAuth.instance.currentUser?.emailVerified != true) {
          return;
        }
        await FirebaseFirestore.instance
            .collection(Collections.users)
            .doc(fresh.uid)
            .update({...patch, 'updated_at': Timestamp.now()});
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
    if (currentPassword.isEmpty || newPassword.isEmpty) {
      throw ArgumentError('Passwords must not be empty');
    }
    if (newPassword.length < 8) {
      throw FirebaseAuthException(
        code: 'weak-password',
        message: 'Password is too weak. Use at least 8 characters.',
      );
    }
    await firebaseUser.reauthenticateWithCredential(credential);
    await firebaseUser.updatePassword(newPassword);
  }

  Future<bool> reauthenticateCurrentUser(String password) async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null || firebaseUser.email == null) return false;
    try {
      final credential = EmailAuthProvider.credential(
        email: firebaseUser.email!,
        password: password,
      );
      await firebaseUser.reauthenticateWithCredential(credential);
      return true;
    } on FirebaseAuthException {
      return false;
    }
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
