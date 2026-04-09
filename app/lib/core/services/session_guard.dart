import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../models/user_model.dart';
import '../constants/collections.dart';
import '../l10n/app_locale.dart';

/// Role-aware session security: background lock screen + inactivity timeout.
///
/// **Seller behaviour** (field workers, device OS lock is primary guard):
///   - No inactivity timeout — sellers use the app all day in the field.
///   - Background > [lockShowDelay] (1 min)  → show lock overlay (tap to resume).
///   - Background > [sellerSignOutDelay] (8h) → auto sign-out.
///
/// **Admin behaviour** (S-10):
///   - [adminInactivityTimeout] (30 min) inactivity → auto sign-out.
///   - Background > [lockShowDelay] (1 min)   → show lock overlay.
///   - Background > [adminSignOutDelay] (2h)  → auto sign-out.
///   - Hard session ceiling [adminSessionMax] (24h); warning 30 min before.
///
/// Lock overlay: full-screen tap/swipe-anywhere-to-dismiss UI guard.
/// Prevents accidental usage when the app is visible in recent-apps
/// or the device is in a pocket (sweat/touch scenario).
class SessionGuard extends ConsumerStatefulWidget {
  final Widget child;

  /// After this much background time, show the lock overlay (all roles).
  final Duration lockShowDelay;

  /// After this much background time, sign a seller out automatically.
  final Duration sellerSignOutDelay;

  /// After this much background time, sign an admin out automatically.
  final Duration adminSignOutDelay;

  /// Inactivity timeout for admin/manager role only.
  /// Sellers have no inactivity timeout.
  final Duration adminInactivityTimeout;

  /// Admin hard session ceiling (S-10). Warning shown 30 min before cutoff.
  final Duration adminSessionMax;

  const SessionGuard({
    super.key,
    required this.child,
    this.lockShowDelay = const Duration(minutes: 1),
    this.sellerSignOutDelay = const Duration(hours: 8),
    this.adminSignOutDelay = const Duration(hours: 2),
    this.adminInactivityTimeout = const Duration(minutes: 30),
    this.adminSessionMax = const Duration(hours: 24),
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
  bool _isLocked = false;
  late final AppLifecycleListener _lifecycleListener;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _sessionStartedAt = DateTime.now();
    _lifecycleListener = AppLifecycleListener(
      onPause: _onAppPaused,
      onHide: _onAppPaused,
      onResume: _onAppResumed,
    );
    _maybeStartInactivityTimer();
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _inactivityTimer?.cancel();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool get _currentUserIsAdmin {
    final user = ref.read(authUserProvider).valueOrNull;
    return user?.isAdmin ?? false;
  }

  /// Starts inactivity timer for admin only; sellers never get one.
  void _maybeStartInactivityTimer() {
    _inactivityTimer?.cancel();
    _checkAdminSessionExpiry();
    if (!_currentUserIsAdmin) return; // sellers: no inactivity timeout
    _inactivityTimer =
        Timer(widget.adminInactivityTimeout, _onInactivityTimeout);
  }

  void _registerActivity() {
    if (_isLocked) return; // block touch through the lock overlay
    final now = DateTime.now();
    if (_lastActivityAt != null &&
        now.difference(_lastActivityAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastActivityAt = now;
    _maybeStartInactivityTimer();
  }

  void _onInactivityTimeout() {
    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth != null) {
      ref.read(authNotifierProvider.notifier).signOut();
    }
  }

  // ── Lifecycle callbacks ───────────────────────────────────────────────────

  void _onAppPaused() {
    _backgroundedAt = DateTime.now();
    _inactivityTimer?.cancel();
    _updateLastActive();
  }

  void _onAppResumed() {
    if (_backgroundedAt != null) {
      final elapsed = DateTime.now().difference(_backgroundedAt!);
      final signOutDelay = _currentUserIsAdmin
          ? widget.adminSignOutDelay
          : widget.sellerSignOutDelay;

      if (elapsed >= signOutDelay) {
        // Away too long → sign out entirely
        final auth = ref.read(authStateProvider).valueOrNull;
        if (auth != null) {
          ref.read(authNotifierProvider.notifier).signOut();
          _backgroundedAt = null;
          return;
        }
      } else if (elapsed >= widget.lockShowDelay) {
        // Away long enough → show lock overlay; keep session alive
        if (mounted) setState(() => _isLocked = true);
      }
    }
    _backgroundedAt = null;
    _checkAdminSessionExpiry();
    if (!_isLocked) _maybeStartInactivityTimer();
  }

  /// Called when user taps or swipes the lock overlay.
  void _unlock() {
    setState(() => _isLocked = false);
    _maybeStartInactivityTimer();
  }

  // ── Admin session ceiling ─────────────────────────────────────────────────

  /// S-10: admin/manager hard session ceiling.
  void _checkAdminSessionExpiry() {
    if (_sessionStartedAt == null) return;
    final user = ref.read(authUserProvider).valueOrNull;
    if (user == null || !user.isAdmin) return;
    final elapsed = DateTime.now().difference(_sessionStartedAt!);
    // Hard cutoff
    if (elapsed >= widget.adminSessionMax) {
      ref.read(authNotifierProvider.notifier).signOut();
      return;
    }
    // Warn 30 min before ceiling — show once per session
    final warnAt = widget.adminSessionMax - const Duration(minutes: 30);
    if (!_warningShown && elapsed >= warnAt) {
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

  // ── Heartbeat ─────────────────────────────────────────────────────────────

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
          .update({'last_active': Timestamp.now()})
          .catchError((_) {});
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Activate the idToken guard — detects Firebase Console account disabling
    ref.watch(authTokenGuardProvider);

    // Reset session clock on fresh login / role change
    ref.listen<AsyncValue<UserModel?>>(authUserProvider, (prev, next) {
      final prevUser = prev?.valueOrNull;
      final nextUser = next.valueOrNull;
      if (prevUser?.id != nextUser?.id && nextUser != null) {
        _sessionStartedAt = DateTime.now();
        _lastActiveWriteAt = null;
        _warningShown = false;
        _isLocked = false;
        _maybeStartInactivityTimer();
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
      child: Stack(
        children: [
          widget.child,
          if (_isLocked) _AppLockOverlay(onUnlock: _unlock),
        ],
      ),
    );
  }
}

// ── Lock Overlay ──────────────────────────────────────────────────────────────
//
// Shown when the app returns from background after [lockShowDelay].
// Prevents accidental usage (pocket / sweat / recent-apps preview).
// User taps or swipes anywhere to dismiss without re-authentication.

class _AppLockOverlay extends ConsumerWidget {
  final VoidCallback onUnlock;
  const _AppLockOverlay({required this.onUnlock});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onUnlock,
      onVerticalDragEnd: (_) => onUnlock(),
      child: Container(
        color: Colors.black.withAlpha(210),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated lock icon
                const Icon(Icons.lock_outline, size: 72, color: Colors.white)
                    .animate(onPlay: (c) => c.repeat())
                    .shimmer(
                      duration: 2400.ms,
                      color: Colors.white.withAlpha(60),
                    ),
                const SizedBox(height: 24),
                Text(
                  tr('lock_screen_session_active', ref),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('lock_screen_tap_to_continue', ref),
                  style: TextStyle(
                    color: Colors.white.withAlpha(178),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 48),
                // Pulsing pill indicator
                Container(
                  width: 56,
                  height: 6,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(3),
                  ),
                )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .fadeIn(duration: 700.ms)
                    .then()
                    .fadeOut(duration: 700.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
