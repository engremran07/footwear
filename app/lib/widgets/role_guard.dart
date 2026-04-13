import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../models/user_model.dart';

class RoleGuard extends ConsumerWidget {
  final Widget child;
  final bool Function(UserModel) allowed;
  final Widget? fallback;

  const RoleGuard({
    super.key,
    required this.child,
    required this.allowed,
    this.fallback,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider).value;
    if (user == null || !allowed(user)) {
      return fallback ?? const SizedBox.shrink();
    }
    return child;
  }
}
