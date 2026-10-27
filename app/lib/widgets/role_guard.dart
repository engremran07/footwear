import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/utils/permission_policy.dart';
import '../core/utils/role_names.dart';
import '../providers/auth_provider.dart';

class RoleGuard extends ConsumerWidget {
  final Widget child;
  final AppCapability capability;
  final Widget? fallback;

  const RoleGuard({
    super.key,
    required this.child,
    required this.capability,
    this.fallback,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider).value;
    if (!PermissionPolicy.can(user, capability)) {
      return fallback ?? const SizedBox.shrink();
    }
    return child;
  }
}
