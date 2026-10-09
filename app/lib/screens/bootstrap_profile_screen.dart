import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/app_locale.dart';
import '../core/utils/error_mapper.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../widgets/error_state.dart';

class BootstrapProfileScreen extends ConsumerWidget {
  const BootstrapProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authUser = ref.watch(authStateProvider).value;
    final profileState = ref.watch(authUserProvider);
    final profile = profileState.value;
    final signOutState = ref.watch(authNotifierProvider);
    final hasUnsupportedRole = profile?.role == UserRole.unknown;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('bootstrap_title', ref)),
        actions: [
          TextButton.icon(
            onPressed: signOutState.isLoading
                ? null
                : () => ref.read(authNotifierProvider.notifier).signOut(),
            icon: signOutState.isLoading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      semanticsLabel: tr('loading', ref),
                    ),
                  )
                : const Icon(Icons.logout),
            label: Text(tr('bootstrap_sign_out', ref)),
          ),
        ],
      ),
      body: Column(
        children: [
          if (signOutState.hasError)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 0),
              child: Text(
                tr(AppErrorMapper.key(signOutState.error!), ref),
                key: const ValueKey('bootstrap-signout-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: profileState.when(
              loading: () => Center(
                child: CircularProgressIndicator(
                  semanticsLabel: tr('loading', ref),
                ),
              ),
              error: (error, _) => mappedErrorState(
                error: error,
                ref: ref,
                onRetry: () => ref.invalidate(authUserProvider),
              ),
              data: (profile) => SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr(
                                hasUnsupportedRole
                                    ? 'bootstrap_invalid_role_title'
                                    : 'bootstrap_missing_profile',
                                ref,
                              ),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              tr(
                                'bootstrap_signed_in_as',
                                ref,
                              ).replaceAll('%s', authUser?.email ?? '-'),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              tr(
                                hasUnsupportedRole
                                    ? 'bootstrap_invalid_role_instructions'
                                    : 'bootstrap_instructions',
                                ref,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
