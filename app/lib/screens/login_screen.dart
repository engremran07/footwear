import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/snack_helper.dart';
import '../providers/auth_provider.dart';
import '../providers/network_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailC = TextEditingController();
  final _passC = TextEditingController();
  bool _obscure = true;
  bool _remember = true;

  @override
  void dispose() {
    _emailC.dispose();
    _passC.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      await ref.read(authNotifierProvider.notifier).signIn(
            _emailC.text.trim(),
            _passC.text,
            rememberMe: _remember,
          );
      // After successful sign-in, the router will navigate automatically
    } catch (e) {
      if (!mounted) return;

      String errorMessage = tr('err_auth_generic', ref);

      // Interpret Firebase errors
      if (e is FirebaseAuthException) {
        errorMessage = switch (e.code) {
          'user-not-found' => tr('err_user_not_found', ref),
          'wrong-password' => tr('err_invalid_credentials', ref),
          'invalid-credential' => tr('err_invalid_credentials', ref),
          'invalid-login-credentials' => tr('err_invalid_credentials', ref),
          'invalid-email' => tr('err_invalid_email', ref),
          'user-disabled' => tr('err_user_disabled', ref),
          'too-many-requests' => tr('err_too_many_requests', ref),
          'network-request-failed' => tr('err_network', ref),
          'operation-not-allowed' => tr('err_operation_not_allowed', ref),
          'requires-recent-login' => tr('err_requires_recent_login', ref),
          _ => '${tr('err_auth_generic', ref)}: ${e.message}',
        };
      } else if (e.toString().contains('No user found')) {
        errorMessage = tr('err_user_not_found', ref);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        errorSnackBar(errorMessage),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authNotifierProvider).isLoading;
    final theme = Theme.of(context);
    final currentLocale = ref.watch(appLocaleProvider);
    final isOnline = ref.watch(isOnlineProvider);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // Online status indicator (top-left)
            Positioned(
              top: 8,
              left: 8,
              child: isOnline.when(
                data: (online) => Chip(
                  avatar: Icon(
                    online ? Icons.cloud_done : Icons.cloud_off,
                    size: 18,
                    color: online ? Colors.green : Colors.grey,
                  ),
                  label: Text(
                    online ? 'Online' : 'Offline',
                    style: TextStyle(
                      fontSize: 12,
                      color: online ? Colors.green : Colors.grey,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  backgroundColor: (online ? Colors.green : Colors.grey)
                      .withValues(alpha: 0.1),
                ),
                loading: () => Chip(
                  avatar: const Icon(
                    Icons.cloud_queue,
                    size: 18,
                    color: Colors.grey,
                  ),
                  label: const Text(
                    '...',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  backgroundColor: Colors.grey.withValues(alpha: 0.1),
                ),
                error: (_, __) => const Chip(
                  avatar: Icon(Icons.cloud_off, size: 18),
                  label: Text('Offline', style: TextStyle(fontSize: 12)),
                ),
              ),
            ),
            // Language selector top-right
            Positioned(
              top: 8,
              right: 8,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<AppLocale>(
                  value: currentLocale,
                  icon: const Icon(Icons.language, size: 20),
                  borderRadius: BorderRadius.circular(12),
                  items: AppLocale.values
                      .map((l) => DropdownMenuItem(
                            value: l,
                            child: Text(l.label,
                                style: const TextStyle(fontSize: 14)),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      ref.read(appLocaleProvider.notifier).state = v;
                    }
                  },
                ),
              ),
            ),
            // Main login form
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          AppBrand.logoAsset,
                          height: 110,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 16),
                        Text(tr('app_name', ref),
                            style: theme.textTheme.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(tr('sign_in_continue', ref),
                            style: theme.textTheme.bodyMedium),
                        const SizedBox(height: 32),
                        TextFormField(
                          controller: _emailC,
                          decoration: InputDecoration(
                            labelText: tr('email', ref),
                            prefixIcon: const Icon(Icons.person_outline),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) => v == null || v.trim().isEmpty
                              ? tr('required', ref)
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passC,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: tr('password', ref),
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(_obscure
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (v) => v == null || v.isEmpty
                              ? tr('required', ref)
                              : null,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Checkbox(
                              value: _remember,
                              onChanged: (v) => setState(() => _remember = v!),
                            ),
                            Text(tr('remember_me', ref)),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: isLoading ? null : _submit,
                            child: isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : Text(tr('sign_in', ref)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
