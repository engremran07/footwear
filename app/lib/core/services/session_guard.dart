import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
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
  // Lifecycle tracing is debug-only to avoid release overhead.
  static const bool _enableLifecycleTrace = kDebugMode;
  static const int _maxTraceEvents = 20;
  Timer? _inactivityTimer;
  DateTime? _backgroundedAt;
  DateTime? _sessionStartedAt;
  DateTime? _lastActivityAt;
  DateTime? _lastActiveWriteAt;
  bool _warningShown = false;
  bool _isLocked = false;
  bool _showDebugPanel = false;
  bool _debugPanelRebuildQueued = false;
  final List<String> _traceEvents = <String>[];
  late final AppLifecycleListener _lifecycleListener;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _sessionStartedAt = DateTime.now();
    _trace('init');
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
    final user = ref.read(authUserProvider).value;
    return user?.isAdmin ?? false;
  }

  void _trace(String event, [Map<String, Object?> details = const {}]) {
    if (!_enableLifecycleTrace) return;
    final now = DateTime.now();
    final user = ref.read(authUserProvider).value;
    final role = user == null
        ? 'none'
        : (user.isAdmin ? 'admin' : (user.isSeller ? 'seller' : 'other'));
    final bgForSec = _backgroundedAt == null
        ? 'n/a'
        : now.difference(_backgroundedAt!).inSeconds.toString();
    final sessionForMin = _sessionStartedAt == null
        ? 'n/a'
        : now.difference(_sessionStartedAt!).inMinutes.toString();
    final detailsText = details.entries
        .map((e) => '${e.key}=${e.value}')
        .join(', ');

    final line =
        '[SessionGuard][$event] t=${now.toIso8601String()} '
        'role=$role locked=$_isLocked bgForSec=$bgForSec sessionForMin=$sessionForMin '
        '${detailsText.isEmpty ? '' : 'details{$detailsText}'}';

    debugPrint(line);

    if (kDebugMode) {
      _traceEvents.add(line);
      if (_traceEvents.length > _maxTraceEvents) {
        _traceEvents.removeRange(0, _traceEvents.length - _maxTraceEvents);
      }
      if (_showDebugPanel && mounted && !_debugPanelRebuildQueued) {
        _debugPanelRebuildQueued = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _debugPanelRebuildQueued = false;
          if (mounted) setState(() {});
        });
      }
    }
  }

  void _toggleDebugPanel() {
    if (!kDebugMode) return;
    setState(() => _showDebugPanel = !_showDebugPanel);
  }

  void _clearTraceEvents() {
    if (!kDebugMode) return;
    setState(() => _traceEvents.clear());
  }

  /// Starts inactivity timer for admin only; sellers never get one.
  void _maybeStartInactivityTimer() {
    _inactivityTimer?.cancel();
    _checkAdminSessionExpiry();
    if (!_currentUserIsAdmin) {
      _trace('timer.skip.nonAdmin');
      return; // sellers: no inactivity timeout
    }
    _inactivityTimer = Timer(
      widget.adminInactivityTimeout,
      _onInactivityTimeout,
    );
    _trace('timer.start', {
      'timeoutMin': widget.adminInactivityTimeout.inMinutes,
    });
  }

  void _registerActivity() {
    if (_isLocked) return; // block touch through the lock overlay
    final now = DateTime.now();
    if (_lastActivityAt != null &&
        now.difference(_lastActivityAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastActivityAt = now;
    _trace('activity.registered');
    _maybeStartInactivityTimer();
  }

  void _onInactivityTimeout() {
    _trace('timer.timeout');
    final auth = ref.read(authStateProvider).value;
    if (auth != null) {
      _trace('signout.inactivity');
      ref.read(authNotifierProvider.notifier).signOut();
    }
  }

  // ── Lifecycle callbacks ───────────────────────────────────────────────────

  void _onAppPaused() {
    _trace('lifecycle.pause');
    _backgroundedAt = DateTime.now();
    _inactivityTimer?.cancel();
    _updateLastActive();
  }

  void _onAppResumed() {
    _trace('lifecycle.resume.start');
    // Sync email verification: user may have clicked the link while backgrounded.
    // Fire-and-forget — auth_provider handles all error cases internally.
    ref.read(authNotifierProvider.notifier).syncEmailVerification();
    if (_backgroundedAt != null) {
      final elapsed = DateTime.now().difference(_backgroundedAt!);
      final signOutDelay = _currentUserIsAdmin
          ? widget.adminSignOutDelay
          : widget.sellerSignOutDelay;
      _trace('lifecycle.resume.elapsed', {
        'elapsedSec': elapsed.inSeconds,
        'signoutDelaySec': signOutDelay.inSeconds,
        'lockDelaySec': widget.lockShowDelay.inSeconds,
      });

      if (elapsed >= signOutDelay) {
        // Away too long → sign out entirely
        final auth = ref.read(authStateProvider).value;
        if (auth != null) {
          _trace('signout.backgroundTimeout');
          ref.read(authNotifierProvider.notifier).signOut();
          _backgroundedAt = null;
          return;
        }
      } else if (elapsed >= widget.lockShowDelay) {
        // Away long enough → show lock overlay; keep session alive
        if (mounted) {
          setState(() => _isLocked = true);
          _trace('lock.shown.onResume');
        }
      }
    }
    _backgroundedAt = null;
    _checkAdminSessionExpiry();
    if (!_isLocked) _maybeStartInactivityTimer();
    _trace('lifecycle.resume.end');
  }

  /// Called when user taps or swipes the lock overlay.
  void _unlock() {
    _trace('lock.dismissed');
    setState(() => _isLocked = false);
    _maybeStartInactivityTimer();
  }

  // ── Admin session ceiling ─────────────────────────────────────────────────

  /// S-10: admin/manager hard session ceiling.
  void _checkAdminSessionExpiry() {
    if (_sessionStartedAt == null) return;
    final user = ref.read(authUserProvider).value;
    if (user == null || !user.isAdmin) return;
    final elapsed = DateTime.now().difference(_sessionStartedAt!);
    // Hard cutoff
    if (elapsed >= widget.adminSessionMax) {
      _trace('signout.adminSessionMax', {'elapsedMin': elapsed.inMinutes});
      ref.read(authNotifierProvider.notifier).signOut();
      return;
    }
    // Warn 30 min before ceiling — show once per session
    final warnAt = widget.adminSessionMax - const Duration(minutes: 30);
    if (!_warningShown && elapsed >= warnAt) {
      _warningShown = true;
      _trace('warning.adminSessionExpiring', {'elapsedMin': elapsed.inMinutes});
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
    final user = ref.read(authUserProvider).value;
    if (user != null) {
      final now = DateTime.now();
      if (_lastActiveWriteAt != null &&
          now.difference(_lastActiveWriteAt!) < const Duration(minutes: 5)) {
        _trace('heartbeat.skip.throttled');
        return;
      }
      _lastActiveWriteAt = now;
      _trace('heartbeat.write', {'userId': user.id});
      FirebaseFirestore.instance
          .collection(Collections.users)
          .doc(user.id)
          .update({'last_active': Timestamp.now()})
          .catchError((_) {
            _trace('heartbeat.write.error', {'userId': user.id});
          });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Activate the idToken guard — detects Firebase Console account disabling
    ref.watch(authTokenGuardProvider);

    // Reset session clock on fresh login / role change
    ref.listen<AsyncValue<UserModel?>>(authUserProvider, (prev, next) {
      final prevUser = prev?.value;
      final nextUser = next.value;
      if (prevUser?.id != nextUser?.id && nextUser != null) {
        _sessionStartedAt = DateTime.now();
        _lastActiveWriteAt = null;
        _warningShown = false;
        _isLocked = false;
        _trace('auth.userChanged', {'userId': nextUser.id});
        _maybeStartInactivityTimer();
      }
      // Force logout if user's active flag cleared remotely
      if (nextUser != null && !nextUser.active) {
        _trace('signout.remoteInactiveUser', {'userId': nextUser.id});
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
          if (_isLocked)
            Positioned.fill(child: _AppLockOverlay(onUnlock: _unlock)),
          if (kDebugMode)
            _SessionGuardDebugPanel(
              visible: _showDebugPanel,
              events: _traceEvents,
              onToggle: _toggleDebugPanel,
              onClear: _clearTraceEvents,
            ),
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
// Full-screen, theme-aware (works with both light and dark themes).

class _AppLockOverlay extends ConsumerWidget {
  final VoidCallback onUnlock;
  const _AppLockOverlay({required this.onUnlock});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onUnlock,
      onVerticalDragEnd: (_) => onUnlock(),
      // Full-screen overlay with high-contrast, theme-aware background.
      child: Material(
        color: Colors.transparent,
        child: SizedBox.expand(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [cs.surface, cs.surfaceContainerLowest],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  // Lock icon in a themed circle container
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child:
                        Icon(
                              Icons.lock_outline,
                              size: 48,
                              color: cs.onPrimaryContainer,
                            )
                            .animate(onPlay: (c) => c.repeat())
                            .shimmer(
                              duration: 2400.ms,
                              color: cs.primary.withAlpha(100),
                            ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    tr('lock_screen_session_active', ref),
                    style: tt.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr('lock_screen_tap_to_continue', ref),
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const Spacer(flex: 4),
                  // Pulsing pill indicator at bottom
                  Container(
                        width: 56,
                        height: 5,
                        decoration: BoxDecoration(
                          color: cs.primary,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .fadeIn(duration: 700.ms)
                      .then()
                      .fadeOut(duration: 700.ms),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionGuardDebugPanel extends StatelessWidget {
  final bool visible;
  final List<String> events;
  final VoidCallback onToggle;
  final VoidCallback onClear;

  const _SessionGuardDebugPanel({
    required this.visible,
    required this.events,
    required this.onToggle,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Stack(
      children: [
        // Hidden trigger: long-press top-right corner to show/hide panel.
        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onLongPress: onToggle,
            child: const SizedBox(width: 36, height: 36),
          ),
        ),
        if (visible)
          Positioned(
            top: 48,
            right: 8,
            left: 8,
            child: Material(
              color: cs.surface,
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 320),
                decoration: BoxDecoration(
                  border: Border.all(color: cs.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'SessionGuard Trace (debug)',
                              style: tt.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: onClear,
                            child: const Text('Clear'),
                          ),
                          IconButton(
                            onPressed: onToggle,
                            icon: const Icon(Icons.close),
                            tooltip: 'Hide debug panel',
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.all(10),
                        itemCount: events.length,
                        itemBuilder: (context, index) {
                          final line = events[events.length - 1 - index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              line,
                              style: tt.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
