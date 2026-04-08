import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../models/user_model.dart';
import '../constants/collections.dart';
import '../l10n/app_locale.dart';

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
  DateTime? _lastActivityAt;
  DateTime? _lastActiveWriteAt;
  bool _warningShown = false;
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

  void _registerActivity() {
    final now = DateTime.now();
    if (_lastActivityAt != null &&
        now.difference(_lastActivityAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastActivityAt = now;
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
    _checkAdminSessionExpiry(); // ISSUE-010: also check in foreground on every interaction
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
    // Hard cutoff at 8h
    if (elapsed > widget.adminSessionMax) {
      ref.read(authNotifierProvider.notifier).signOut();
      return;
    }
    // Warn at 7h30m (450 minutes) — show once per session
    if (!_warningShown && elapsed.inMinutes >= 450) {
      _warningShown = true;
      _showSessionExpiryWarning();
    }
  }

  void _showSessionExpiryWarning() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Text(tr('session_expiring_soon', ref)),
        content: Text(tr('session_warning_30min', ref)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('ok', ref)),
          ),
        ],
      ),
    );
  }

  void _updateLastActive() {
    final user = ref.read(authUserProvider).valueOrNull;
    if (user != null) {
      final now = DateTime.now();
      if (_lastActiveWriteAt != null &&
          now.difference(_lastActiveWriteAt!) < const Duration(minutes: 5)) {
        return;
      }
      _lastActiveWriteAt = now;
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
      if (prevUser?.id != nextUser?.id && nextUser != null) {
        _sessionStartedAt = DateTime.now();
        _lastActiveWriteAt = null;
        _warningShown = false; // reset warning flag for new session
      }
      // Force logout if user's active flag cleared remotely
      if (nextUser != null && !nextUser.active) {
        ref.read(authNotifierProvider.notifier).signOut();
      }
    });

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _registerActivity(),
      onPointerMove: (_) => _registerActivity(),
      child: widget.child,
    );
  }
}
