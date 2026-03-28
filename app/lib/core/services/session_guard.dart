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
class SessionGuard extends ConsumerStatefulWidget {
  final Widget child;
  final Duration timeoutDuration;
  final Duration backgroundLockDelay;

  const SessionGuard({
    super.key,
    required this.child,
    this.timeoutDuration = const Duration(minutes: 15),
    this.backgroundLockDelay = const Duration(minutes: 2),
  });

  @override
  ConsumerState<SessionGuard> createState() => _SessionGuardState();
}

class _SessionGuardState extends ConsumerState<SessionGuard>
    with WidgetsBindingObserver {
  Timer? _inactivityTimer;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resetInactivityTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt = DateTime.now();
      _inactivityTimer?.cancel();
      _updateLastActive();
    } else if (state == AppLifecycleState.resumed) {
      if (_backgroundedAt != null) {
        final elapsed = DateTime.now().difference(_backgroundedAt!);
        if (elapsed > widget.backgroundLockDelay) {
          // Force re-auth after extended background time
          final auth = ref.read(authStateProvider).valueOrNull;
          if (auth != null) {
            ref.read(authNotifierProvider.notifier).signOut();
          }
        }
      }
      _backgroundedAt = null;
      _resetInactivityTimer();
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
    // Force logout if user's active flag is set to false
    ref.listen<AsyncValue<UserModel?>>(authUserProvider, (prev, next) {
      next.whenData((user) {
        if (user != null && !user.active) {
          ref.read(authNotifierProvider.notifier).signOut();
        }
      });
    });

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetInactivityTimer(),
      onPointerMove: (_) => _resetInactivityTimer(),
      child: widget.child,
    );
  }
}
