import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/app_locale.dart';
import '../core/utils/permission_policy.dart';
import '../core/utils/role_names.dart';
import '../providers/auth_provider.dart';
import 'error_state.dart';
import 'shimmer_loading.dart';

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
    final userState = ref.watch(authUserProvider);
    if (userState.hasError) {
      return Scaffold(
        body: mappedErrorState(
          error: userState.error!,
          ref: ref,
          onRetry: () => ref.invalidate(authUserProvider),
        ),
      );
    }
    if (userState.isLoading) {
      return const Scaffold(body: ShimmerLoading());
    }

    final user = userState.value;
    if (user == null) {
      return Scaffold(
        body: ErrorState(
          message: tr('err_account_not_assigned', ref),
          errorType: ErrorType.permission,
          onRetry: () => ref.invalidate(authUserProvider),
          retryLabel: tr('retry', ref),
        ),
      );
    }
    if (!PermissionPolicy.can(user, capability)) {
      return fallback ??
          Scaffold(
            body: ErrorState(
              message: tr('no_access', ref),
              errorType: ErrorType.permission,
            ),
          );
    }
    return child;
  }
}
