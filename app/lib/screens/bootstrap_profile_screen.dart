import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/app_locale.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';

class BootstrapProfileScreen extends ConsumerWidget {
  const BootstrapProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authUser = ref.watch(authStateProvider).value;
    final profile = ref.watch(authUserProvider).value;
    final hasUnsupportedRole = profile?.role == UserRole.unknown;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('bootstrap_title', ref)),
        actions: [
          TextButton.icon(
            onPressed: () => ref.read(authNotifierProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
            label: Text(tr('bootstrap_sign_out', ref)),
          ),
        ],
      ),
      body: SingleChildScrollView(
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
    );
  }
}
