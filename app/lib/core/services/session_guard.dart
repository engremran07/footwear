import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../models/user_model.dart';
import '../constants/collections.dart';

/// Banking-style session security: inactivity timeout + background lock.
///
/// Wraps the entire app to detect user inactivity and app lifecycle changes.
/// After [timeoutDuration] of no taps, auto-signs out. On return from
/// background after [backgroundLockDelay], forces re-auth.
///
/// **Admin 8-hour hard session**: Regardless of activity, admin/manager
/// sessions are forcefully expired after [adminSessionMax] to mitigate
/// stale-session compromise (S-10).
class SessionGuard extends ConsumerStatefulWidget {
  final Widget child;
  final Duration timeoutDuration;
  final Duration backgroundLockDelay;
  final Duration adminSessionMax;

  const SessionGuard({
    super.key,
    required this.child,
    this.timeoutDuration = const Duration(minutes: 15),
    this.backgroundLockDelay = const Duration(minutes: 2),
    this.adminSessionMax = const Duration(hours: 8),
  });

  @override
  ConsumerState<SessionGuard> createState() => _SessionGuardState();
}

class _SessionGuardState extends ConsumerState<SessionGuard> {
  Timer? _inactivityTimer;
  DateTime? _backgroundedAt;
  DateTime? _sessionStartedAt;
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _sessionStartedAt = DateTime.now();
    _lifecycleListener = AppLifecycleListener(
      onPause: _onAppPaused,
      onHide: _onAppPaused,
      onResume: _onAppResumed,
    );
    _resetInactivityTimer();
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _inactivityTimer?.cancel();
    super.dispose();
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(widget.timeoutDuration, _onInactivityTimeout);
  }

  void _onInactivityTimeout() {
    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth != null) {
      ref.read(authNotifierProvider.notifier).signOut();
    }
  }

  void _onAppPaused() {
    _backgroundedAt = DateTime.now();
    _inactivityTimer?.cancel();
    _updateLastActive();
  }

  void _onAppResumed() {
    if (_backgroundedAt != null) {
      final elapsed = DateTime.now().difference(_backgroundedAt!);
      if (elapsed > widget.backgroundLockDelay) {
        final auth = ref.read(authStateProvider).valueOrNull;
        if (auth != null) {
          ref.read(authNotifierProvider.notifier).signOut();
          _backgroundedAt = null;
          return;
        }
      }
    }
    _backgroundedAt = null;
    _checkAdminSessionExpiry();
    _resetInactivityTimer();
  }

  /// S-10: admin/manager hard session limit.
  void _checkAdminSessionExpiry() {
    if (_sessionStartedAt == null) return;
    final user = ref.read(authUserProvider).valueOrNull;
    if (user == null) return;
    if (!user.isAdmin) return;
    final elapsed = DateTime.now().difference(_sessionStartedAt!);
    if (elapsed > widget.adminSessionMax) {
      ref.read(authNotifierProvider.notifier).signOut();
    }
  }

  void _updateLastActive() {
    final user = ref.read(authUserProvider).valueOrNull;
    if (user != null) {
      FirebaseFirestore.instance
          .collection(Collections.users)
          .doc(user.id)
          .update({'last_active': Timestamp.now()}).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // Activate the idToken guard — detects Firebase Console account disabling
    ref.watch(authTokenGuardProvider);

    // Reset session clock on fresh login
    ref.listen<AsyncValue<UserModel?>>(authUserProvider, (prev, next) {
      final prevUser = prev?.valueOrNull;
      final nextUser = next.valueOrNull;
      // New login: reset session start
      if (prevUser == null && nextUser != null) {
        _sessionStartedAt = DateTime.now();
      }
      // Force logout if user's active flag cleared remotely
      if (nextUser != null && !nextUser.active) {
        ref.read(authNotifierProvider.notifier).signOut();
      }
    });

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetInactivityTimer(),
      onPointerMove: (_) => _resetInactivityTimer(),
      child: widget.child,
    );
  }
}
