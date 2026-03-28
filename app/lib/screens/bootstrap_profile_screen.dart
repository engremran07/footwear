import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/bootstrap_provider.dart';

class BootstrapProfileScreen extends ConsumerWidget {
  const BootstrapProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authUser = ref.watch(authStateProvider).valueOrNull;
    final isLoading = ref.watch(bootstrapNotifierProvider).isLoading;
    final email = (authUser?.email ?? '').trim().toLowerCase();
    final canBootstrap = authUser != null && email == 'admin@footwear.pk';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bootstrap Admin Profile'),
        actions: [
          TextButton.icon(
            onPressed: () => ref.read(authNotifierProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
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
                    const Text(
                      'Account signed in, but user profile is missing.',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    Text('Signed in as: ${authUser?.email ?? '-'}'),
                    const SizedBox(height: 8),
                    const Text(
                      'Use this one-time action to create users/{uid} with admin role. This is restricted to admin@footwear.pk only.',
                    ),
                    const SizedBox(height: 20),
                    if (!canBootstrap)
                      const Text(
                        'This account is not eligible for bootstrap. Sign out and log in with admin@footwear.pk.',
                        style: TextStyle(color: Colors.red),
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
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.build_circle_outlined),
                        label: const Text('Create Admin Profile'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin profile created successfully.')),
      );
    } on FirebaseAuthException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? e.code)),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }
}
