import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/app_sanitizer.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/input_formatters.dart';
import '../core/utils/snack_helper.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_preference_provider.dart';
import '../providers/user_provider.dart';
import '../widgets/confirm_dialog.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameC = TextEditingController();
  bool _isDirty = false;

  @override
  void dispose() {
    _nameC.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final me = ref.read(authUserProvider).value;
    if (me == null) return;
    final name = AppSanitizer.name(_nameC.text);
    if (name.isEmpty || name == me.displayName) return;

    try {
      await ref.read(userManagementNotifierProvider.notifier).updateUser(
        me.id,
        {'display_name': name},
      );
      if (mounted) {
        HapticFeedback.mediumImpact();
        setState(() => _isDirty = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(successSnackBar(tr('saved_successfully', ref)));
      }
    } catch (e) {
      if (mounted) {
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(tr(key, ref)));
      }
    }
  }

  void _showChangePasswordDialog() {
    final currentPassC = TextEditingController();
    final newPassC = TextEditingController();
    final confirmPassC = TextEditingController();
    final newPassFn = FocusNode();
    final confirmPassFn = FocusNode();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('change_password', ref)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentPassC,
                decoration: InputDecoration(
                  labelText: tr('current_password', ref),
                ),
                obscureText: true,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => newPassFn.requestFocus(),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: newPassC,
                focusNode: newPassFn,
                decoration: InputDecoration(labelText: tr('new_password', ref)),
                obscureText: true,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => confirmPassFn.requestFocus(),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmPassC,
                focusNode: confirmPassFn,
                decoration: InputDecoration(
                  labelText: tr('confirm_password', ref),
                ),
                obscureText: true,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.done,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('cancel', ref)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newPass = newPassC.text.trim();
              if (newPass.length < 8) {
                ScaffoldMessenger.of(
                  ctx,
                ).showSnackBar(warningSnackBar(tr('err_weak_password', ref)));
                return;
              }
              if (newPass != confirmPassC.text.trim()) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  warningSnackBar(tr('passwords_dont_match', ref)),
                );
                return;
              }

              try {
                await ref
                    .read(userManagementNotifierProvider.notifier)
                    .changeOwnPassword(
                      currentPassword: currentPassC.text,
                      newPassword: newPass,
                    );
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    successSnackBar(tr('saved_successfully', ref)),
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  final key = AppErrorMapper.key(e);
                  ScaffoldMessenger.of(
                    ctx,
                  ).showSnackBar(errorSnackBar(tr(key, ref)));
                }
              }
            },
            child: Text(tr('save', ref)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authUserProvider).value;
    final locale = ref.watch(appLocaleProvider);
    final currentTheme = ref.watch(themePreferenceProvider);

    if (currentUser != null && _nameC.text.isEmpty) {
      _nameC.value = TextEditingValue(
        text: currentUser.displayName,
        selection: TextSelection.collapsed(
          offset: currentUser.displayName.length,
        ),
      );
    }

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await ConfirmDialog.show(
          context,
          title: tr('unsaved_changes', ref),
          message: tr('discard_changes_message', ref),
        );
        if (leave == true && context.mounted) Navigator.pop(context);
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('profile_my_profile', ref),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _nameC,
                        decoration: InputDecoration(
                          labelText: tr('lbl_display_name', ref),
                        ),
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _saveName(),
                        onChanged: (_) {
                          if (!_isDirty) setState(() => _isDirty = true);
                        },
                        inputFormatters: [AppInputFormatters.maxLength(100)],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _saveName,
                          child: Text(tr('save', ref)),
                        ),
                      ),
                      if (currentUser != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          currentUser.email,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('language', ref),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<AppLocale>(
                        segments: AppLocale.values
                            .map(
                              (l) =>
                                  ButtonSegment(value: l, label: Text(l.label)),
                            )
                            .toList(),
                        selected: {locale},
                        onSelectionChanged: (s) =>
                            ref.read(appLocaleProvider.notifier).set(s.first),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('profile_appearance', ref),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<AppThemeMode>(
                        segments: [
                          ButtonSegment(
                            value: AppThemeMode.auto,
                            icon: const Icon(Icons.brightness_auto, size: 18),
                            label: Text(tr('profile_theme_auto', ref)),
                          ),
                          ButtonSegment(
                            value: AppThemeMode.light,
                            icon: const Icon(Icons.light_mode, size: 18),
                            label: Text(tr('profile_theme_light', ref)),
                          ),
                          ButtonSegment(
                            value: AppThemeMode.dark,
                            icon: const Icon(Icons.dark_mode, size: 18),
                            label: Text(tr('profile_theme_dark', ref)),
                          ),
                          ButtonSegment(
                            value: AppThemeMode.highContrast,
                            icon: const Icon(Icons.contrast, size: 18),
                            label: Text(tr('profile_theme_high_contrast', ref)),
                          ),
                        ],
                        selected: {currentTheme},
                        onSelectionChanged: (s) => ref
                            .read(themePreferenceProvider.notifier)
                            .setThemeMode(s.first),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('profile_security', ref),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _showChangePasswordDialog,
                          icon: const Icon(Icons.lock_reset),
                          label: Text(tr('change_password', ref)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppBrand.errorColor,
                    side: const BorderSide(color: AppBrand.errorColor),
                  ),
                  onPressed: () async {
                    final confirmed = await ConfirmDialog.show(
                      context,
                      title: tr('sign_out', ref),
                      message: tr('confirm_sign_out', ref),
                    );
                    if (confirmed == true) {
                      ref.read(authNotifierProvider.notifier).signOut();
                    }
                  },
                  icon: const Icon(Icons.logout),
                  label: Text(tr('sign_out', ref)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
