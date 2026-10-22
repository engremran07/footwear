import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';

class AuthLifecycleObserver extends ConsumerStatefulWidget {
  final Widget child;

  const AuthLifecycleObserver({super.key, required this.child});

  @override
  ConsumerState<AuthLifecycleObserver> createState() =>
      _AuthLifecycleObserverState();
}

class _AuthLifecycleObserverState extends ConsumerState<AuthLifecycleObserver> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(onResume: _onResume);
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  void _onResume() {
    final auth = ref.read(authNotifierProvider.notifier);
    unawaited(auth.verifyAuthAccountOnResume());
    unawaited(auth.syncEmailVerification());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<UserModel?>>(authUserProvider, (previous, next) {
      final user = next.value;
      if (user != null && !user.active) {
        unawaited(
          ref.read(authNotifierProvider.notifier).signOut(expectedUid: user.id),
        );
      }
    });
    return widget.child;
  }
}
