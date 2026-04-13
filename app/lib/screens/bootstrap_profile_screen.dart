import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/snack_helper.dart';
import '../providers/auth_provider.dart';
import '../providers/bootstrap_provider.dart';

class BootstrapProfileScreen extends ConsumerWidget {
  const BootstrapProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authUser = ref.watch(authStateProvider).value;
    final isLoading = ref.watch(bootstrapNotifierProvider).isLoading;
    final email = (authUser?.email ?? '').trim().toLowerCase();
    final canBootstrap = authUser != null && email.isNotEmpty;

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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('bootstrap_missing_profile', ref),
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
                    Text(tr('bootstrap_instructions', ref)),
                    const SizedBox(height: 20),
                    if (!canBootstrap)
                      Text(
                        tr('bootstrap_not_eligible', ref),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: (!canBootstrap || isLoading)
                            ? null
                            : () => _bootstrap(context, ref),
                        icon: isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppBrand.onPrimary,
                                ),
                              )
                            : const Icon(Icons.build_circle_outlined),
                        label: Text(tr('bootstrap_create_btn', ref)),
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

  Future<void> _bootstrap(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(bootstrapNotifierProvider.notifier)
          .createCurrentAdminProfile();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(successSnackBar(tr('msg_admin_profile_created', ref)));
    } on FirebaseAuthException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(errorSnackBar(e.message ?? e.code));
    } catch (e) {
      if (!context.mounted) return;
      final key = AppErrorMapper.key(e);
      ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(tr(key, ref)));
    }
  }
}
