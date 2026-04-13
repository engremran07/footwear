import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_brand.dart';
import '../core/design/app_tokens.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/snack_helper.dart';
import '../providers/auth_provider.dart';
import '../providers/network_provider.dart';
import '../widgets/app_online_indicator.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailC = TextEditingController();
  final _passC = TextEditingController();
  final _emailFocus = FocusNode();
  bool _obscure = true;
  bool _remember = true;

  // S-02: Brute-force protection
  int _failCount = 0;
  int _lockoutSeconds = 0;
  Timer? _lockoutTimer;

  bool get _isLockedOut => _lockoutSeconds > 0;

  void _startLockout() {
    final duration = switch (_failCount) {
      >= 7 => 120,
      >= 5 => 60,
      _ => 30,
    };
    _lockoutSeconds = duration;
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _lockoutSeconds--;
        if (_lockoutSeconds <= 0) t.cancel();
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _loadRememberedCredentials();
  }

  /// Restore remembered email from SharedPreferences and populate the field.
  Future<void> _loadRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final remembered = prefs.getBool(rememberMePrefKey) ?? true;
    final savedEmail = prefs.getString('auth.saved_email') ?? '';
    if (!mounted) return;
    setState(() {
      _remember = remembered;
      if (remembered && savedEmail.isNotEmpty) {
        _emailC.text = savedEmail;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // If email already pre-filled jump straight to password, otherwise focus email
      if (_emailC.text.isNotEmpty) {
        FocusScope.of(context).nextFocus();
      } else {
        _emailFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _emailC.dispose();
    _passC.dispose();
    _emailFocus.dispose();
    _lockoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isLockedOut) return;
    if (!_formKey.currentState!.validate()) return;

    try {
      await ref
          .read(authNotifierProvider.notifier)
          .signIn(_emailC.text.trim(), _passC.text, rememberMe: _remember);
      _failCount = 0;
      // Persist or clear remembered email for next cold launch
      final prefs = await SharedPreferences.getInstance();
      if (_remember) {
        await prefs.setBool(rememberMePrefKey, true);
        await prefs.setString('auth.saved_email', _emailC.text.trim());
      } else {
        await prefs.setBool(rememberMePrefKey, false);
        await prefs.remove('auth.saved_email');
      }
      // Signal Android autofill framework to offer credential save
      if (mounted) TextInput.finishAutofillContext();
    } catch (e) {
      if (!mounted) return;

      _failCount++;
      if (_failCount >= 3) _startLockout();

      String errorMessage = tr('err_auth_generic', ref);

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

      ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(errorMessage));
    }
  }

  Future<void> _showForgotPassword() async {
    final emailController = TextEditingController(text: _emailC.text.trim());
    final formKey = GlobalKey<FormState>();
    bool sent = false;

    Future<void> submitReset(
      StateSetter setDlgState,
      BuildContext dialogContext,
    ) async {
      if (!formKey.currentState!.validate()) return;
      try {
        await ref
            .read(authNotifierProvider.notifier)
            .sendPasswordReset(emailController.text.trim());
        setDlgState(() => sent = true);
      } on FirebaseAuthException catch (e) {
        if (!dialogContext.mounted) return;
        Navigator.of(dialogContext).pop();
        if (mounted) {
          final errorMessage = switch (e.code) {
            'user-not-found' => tr('err_user_not_found', ref),
            'invalid-email' => tr('err_invalid_email', ref),
            'too-many-requests' => tr('err_too_many_requests', ref),
            'network-request-failed' => tr('err_network', ref),
            _ => e.message ?? tr('err_auth_generic', ref),
          };
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(errorSnackBar(errorMessage));
        }
      } catch (_) {
        if (!dialogContext.mounted) return;
        Navigator.of(dialogContext).pop();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(errorSnackBar(tr('err_auth_generic', ref)));
        }
      }
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(tr('forgot_password', ref)),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('enter_email_to_reset', ref)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: emailController,
                  decoration: InputDecoration(
                    labelText: tr('email', ref),
                    prefixIcon: const Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  autofocus: emailController.text.isEmpty,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? tr('required', ref)
                      : null,
                  onFieldSubmitted: (_) => submitReset(setDlgState, ctx),
                ),
                const SizedBox(height: 12),
                Text(
                  tr('login_reset_email_hint', ref),
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          actions: sent
              ? [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(tr('ok', ref)),
                  ),
                ]
              : [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(tr('cancel', ref)),
                  ),
                  FilledButton(
                    onPressed: () => submitReset(setDlgState, ctx),
                    child: Text(tr('send_reset_email', ref)),
                  ),
                ],
        ),
      ),
    );

    if (sent && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(successSnackBar(tr('reset_email_sent', ref)));
    }
    emailController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authNotifierProvider).isLoading;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final currentLocale = ref.watch(appLocaleProvider);
    final isOnline = ref.watch(isOnlineProvider);
    final isWide = MediaQuery.sizeOf(context).width > 720;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: isWide
            ? _wideLayout(theme, cs, currentLocale, isOnline, isLoading)
            : _narrowLayout(theme, cs, currentLocale, isOnline, isLoading),
      ),
    );
  }

  /// Wide layout: brand panel (40%) + form panel (60%)
  Widget _wideLayout(
    ThemeData theme,
    ColorScheme cs,
    AppLocale currentLocale,
    AsyncValue<bool> isOnline,
    bool isLoading,
  ) {
    return Row(
      children: [
        // Brand panel
        Expanded(
          flex: 4,
          child: _BrandPanel(theme: theme, cs: cs),
        ),
        // Form panel
        Expanded(
          flex: 6,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppTokens.s48),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _languagePicker(currentLocale),
                    const SizedBox(height: AppTokens.s24),
                    _loginForm(theme, cs, isLoading),
                    const SizedBox(height: AppTokens.s16),
                    _onlineIndicator(isOnline),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Narrow (mobile) layout: single column
  Widget _narrowLayout(
    ThemeData theme,
    ColorScheme cs,
    AppLocale currentLocale,
    AsyncValue<bool> isOnline,
    bool isLoading,
  ) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontalPadding = screenWidth < 380 ? AppTokens.s16 : AppTokens.s24;

    return Stack(
      children: [
        Center(
          child: AnimatedPadding(
            duration: AppTokens.durFast,
            curve: AppTokens.curveStd,
            padding: EdgeInsets.only(bottom: viewInsets.bottom),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                AppTokens.s24,
                horizontalPadding,
                AppTokens.s32,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: screenWidth - (horizontalPadding * 2),
                  maxWidth: 420,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      AppBrand.logoAsset,
                      height: 90,
                      fit: BoxFit.contain,
                    ).animate().fadeIn(duration: AppTokens.durNormal),
                    const SizedBox(height: AppTokens.s12),
                    Text(
                      tr('app_name', ref),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppTokens.s4),
                    Text(
                      tr('sign_in_continue', ref),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppTokens.s20),
                    _languagePicker(currentLocale),
                    const SizedBox(height: AppTokens.s20),
                    SizedBox(
                      width: double.infinity,
                      child: _loginForm(theme, cs, isLoading),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Online indicator bottom-right
        Positioned(
          bottom: viewPadding.bottom + AppTokens.s12,
          right: AppTokens.s12,
          child: _onlineIndicator(isOnline),
        ),
      ],
    );
  }

  Widget _languagePicker(AppLocale currentLocale) {
    return SegmentedButton<AppLocale>(
      segments: AppLocale.values
          .map((l) => ButtonSegment<AppLocale>(value: l, label: Text(l.label)))
          .toList(),
      selected: {currentLocale},
      onSelectionChanged: (set) {
        ref.read(appLocaleProvider.notifier).set(set.first);
      },
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(
          Theme.of(context).textTheme.labelMedium,
        ),
      ),
    );
  }

  Widget _onlineIndicator(AsyncValue<bool> isOnline) {
    return isOnline.when(
      data: (online) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppOnlineIndicator(isOnline: online),
          const SizedBox(width: AppTokens.s4),
          Text(
            online ? tr('login_online', ref) : tr('login_offline', ref),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: online ? AppBrand.successColor : AppBrand.stockColor,
            ),
          ),
        ],
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppOnlineIndicator(isOnline: false),
          const SizedBox(width: AppTokens.s4),
          Text(
            tr('login_offline', ref),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _loginForm(ThemeData theme, ColorScheme cs, bool isLoading) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppTokens.brLG,
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s24),
        child: Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr('sign_in', ref),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppTokens.s24),
                TextFormField(
                  controller: _emailC,
                  focusNode: _emailFocus,
                  autofillHints: const [
                    AutofillHints.email,
                    AutofillHints.username,
                  ],
                  decoration: InputDecoration(
                    labelText: tr('email', ref),
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? tr('required', ref)
                      : null,
                ).animate().fadeIn(
                  delay: 100.ms,
                  duration: AppTokens.durNormal,
                ),
                const SizedBox(height: AppTokens.s16),
                TextFormField(
                  controller: _passC,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: tr('password', ref),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: AnimatedSwitcher(
                        duration: AppTokens.durFast,
                        child: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                          key: ValueKey(_obscure),
                        ),
                      ),
                      tooltip: _obscure
                          ? tr('tooltip_show_password', ref)
                          : tr('tooltip_hide_password', ref),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (v) =>
                      v == null || v.isEmpty ? tr('required', ref) : null,
                ).animate().fadeIn(
                  delay: 200.ms,
                  duration: AppTokens.durNormal,
                ),
                const SizedBox(height: AppTokens.s8),
                Row(
                  children: [
                    Checkbox(
                      value: _remember,
                      onChanged: (v) => setState(() => _remember = v!),
                    ),
                    Text(tr('remember_me', ref)),
                  ],
                ),
                const SizedBox(height: AppTokens.s24),
                SizedBox(
                  height: AppTokens.buttonMinHeight,
                  child: FilledButton(
                    onPressed: (isLoading || _isLockedOut) ? null : _submit,
                    child: isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppBrand.onPrimary,
                            ),
                          )
                        : _isLockedOut
                        ? Text('${tr('sign_in', ref)} ($_lockoutSeconds s)')
                        : Text(tr('sign_in', ref)),
                  ),
                ).animate().fadeIn(
                  delay: 300.ms,
                  duration: AppTokens.durNormal,
                ),
                const SizedBox(height: AppTokens.s8),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: _showForgotPassword,
                    child: Text(tr('forgot_password', ref)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Brand panel for wide layout — gradient + logo + tagline
class _BrandPanel extends ConsumerWidget {
  final ThemeData theme;
  final ColorScheme cs;

  const _BrandPanel({required this.theme, required this.cs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppBrand.primaryColor,
            AppBrand.primaryColor.withValues(alpha: 0.8),
            cs.primaryContainer,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(AppBrand.logoAsset, height: 120, fit: BoxFit.contain)
                .animate()
                .fadeIn(duration: AppTokens.durSlow)
                .scale(
                  begin: const Offset(0.85, 0.85),
                  end: const Offset(1, 1),
                  curve: AppTokens.curveSpring,
                ),
            const SizedBox(height: AppTokens.s16),
            Text(
              AppBrand.appName,
              style: theme.textTheme.headlineLarge?.copyWith(
                color: AppBrand.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ).animate().fadeIn(delay: 200.ms, duration: AppTokens.durNormal),
            const SizedBox(height: AppTokens.s8),
            Text(
              tr('login_tagline', ref),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: AppBrand.onPrimaryMuted,
              ),
            ).animate().fadeIn(delay: 400.ms, duration: AppTokens.durNormal),
          ],
        ),
      ),
    );
  }
}
