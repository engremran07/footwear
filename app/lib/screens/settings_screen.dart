import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/permission_policy.dart';
import '../core/utils/snack_helper.dart';
import '../core/utils/workspace_logo_processor.dart';
import '../models/settings_model.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';

import '../widgets/confirm_dialog.dart';
import '../widgets/error_state.dart';
import '../widgets/app_pull_refresh.dart';
import '../widgets/whats_new_sheet.dart';

Future<bool> _requireAdminSettingsAccess(
  BuildContext context,
  WidgetRef ref,
) async {
  final user = await ref.read(authUserProvider.future);
  if (user?.isAdmin == true) return true;
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(errorSnackBar(tr('permission_denied', ref)));
  }
  return false;
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _ppcC = TextEditingController();
  bool _allowSellerEditRequests = false;
  bool _settingsLoaded = false;
  bool _isDirty = false;
  bool _savingSettings = false;

  @override
  void dispose() {
    _ppcC.dispose();
    super.dispose();
  }

  void _loadSettings(SettingsModel settings) {
    if (_isDirty) return;
    final ppcStr = settings.pairsPerCarton.toString();
    _ppcC.value = TextEditingValue(
      text: ppcStr,
      selection: TextSelection.collapsed(offset: ppcStr.length),
    );
    _allowSellerEditRequests = settings.allowSellerEditRequests;
    _settingsLoaded = true;
  }

  Widget _buildPlatformSettingsHub() {
    final theme = Theme.of(context);
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            tr('platform_settings', ref),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            tr('platform_settings_scope', ref),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.apartment_outlined),
            title: Text(tr('workspaces', ref)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/tenants'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline),
            title: Text(tr('profile', ref)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/profile'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline),
            title: Text(tr('about_us', ref)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/about'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.new_releases_outlined),
            title: Text(tr('whats_new', ref)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => WhatsNewSheet.show(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _saveSettings() async {
    if (_savingSettings) return;
    setState(() => _savingSettings = true);
    try {
      if (!await _requireAdminSettingsAccess(context, ref)) return;
      final pairsPerCarton = int.tryParse(_ppcC.text.trim());
      if (pairsPerCarton == null || pairsPerCarton <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            warningSnackBar(tr('settings_invalid_pairs_per_carton', ref)),
          );
        }
        return;
      }
      await ref.read(settingsNotifierProvider.notifier).save({
        'pairs_per_carton': pairsPerCarton,
        'allow_seller_edit_requests': _allowSellerEditRequests,
      });
      if (mounted) {
        setState(() => _isDirty = false);
        ref.invalidate(settingsProvider);
        ScaffoldMessenger.of(context)
            .showSnackBar(successSnackBar(tr('saved_successfully', ref)));
      }
    } catch (e) {
      if (mounted) {
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(tr(key, ref)));
      }
    } finally {
      if (mounted) setState(() => _savingSettings = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authUserProvider);
    if (authAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (authAsync.hasError) {
      return Scaffold(
        body: mappedErrorState(
          error: authAsync.error!,
          ref: ref,
          onRetry: () => ref.invalidate(authUserProvider),
        ),
      );
    }
    final currentUser = authAsync.value;
    if (currentUser == null) {
      return Scaffold(body: Center(child: Text(tr('permission_denied', ref))));
    }
    if (currentUser.isSuperAdmin && currentUser.activeWorkspaceId == null) {
      return _buildPlatformSettingsHub();
    }

    final settingsAsync = ref.watch(settingsProvider);
    final canViewDataMaintenance = PermissionPolicy.canAccessRoute(
      currentUser,
      '/settings/flush',
    );
    if (!currentUser.isAdmin) {
      return Scaffold(body: Center(child: Text(tr('permission_denied', ref))));
    }
    settingsAsync.whenData(_loadSettings);
    if (!_settingsLoaded) {
      return Scaffold(
        body: settingsAsync.when(
          data: (_) => const Center(child: CircularProgressIndicator()),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => mappedErrorState(
            error: error,
            ref: ref,
            onRetry: () => ref.invalidate(settingsProvider),
          ),
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
      child: Scaffold(
        body: AppPullRefresh(
          onRefresh: () async {
            ref.invalidate(settingsProvider);
            await ref.read(settingsProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              // Business settings
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('business_settings', ref),
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _ppcC,
                        decoration: InputDecoration(
                          labelText: tr('pairs_per_carton', ref),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) {
                          if (!_isDirty) setState(() => _isDirty = true);
                        },
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: _allowSellerEditRequests,
                        onChanged: (value) {
                          setState(() {
                            _allowSellerEditRequests = value;
                            _isDirty = true;
                          });
                        },
                        title: Text(tr('seller_edit_requests_title', ref)),
                        subtitle: Text(
                          tr('seller_edit_requests_subtitle', ref),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _savingSettings ? null : _saveSettings,
                          child: _savingSettings
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(tr('save', ref)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Company Logo (admin only)
              if (currentUser.isAdmin) ...[
                const _LogoCard(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(tr('invoice_header_settings', ref)),
                  subtitle: Text(tr('invoice_header_settings_hint', ref)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings/invoice-header'),
                ),
                const SizedBox(height: 16),
              ],
              // About
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.info_outlined),
                title: Text(tr('about_us', ref)),
                subtitle: const Text(
                  AppBrand.versionDisplay,
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/about'),
              ),
              const SizedBox(height: 16),
              // â”€â”€ Backup & Restore â”€â”€
              if (ref.watch(authUserProvider).value?.isAdmin == true) ...[
                Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.backup_outlined,
                      color: AppBrand.primaryColor,
                    ),
                    title: Text(tr('backup_title', ref)),
                    subtitle: Text(tr('backup_nav_subtitle', ref)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/settings/backup'),
                  ),
                ),
                const SizedBox(height: 8),
                if (canViewDataMaintenance)
                  Card(
                    color: AppBrand.errorColor.withAlpha(12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: AppBrand.errorColor.withAlpha(80),
                      ),
                    ),
                    child: ListTile(
                      leading: const Icon(
                        Icons.warning_amber_rounded,
                        color: AppBrand.errorColor,
                      ),
                      title: Text(
                        tr('danger_zone', ref),
                        style: const TextStyle(
                          color: AppBrand.errorColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(tr('danger_zone_subtitle', ref)),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: AppBrand.errorColor,
                      ),
                      onTap: () => context.push('/settings/flush'),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              // Sign out
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

// â”€â”€â”€ Company Logo Card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _LogoCard extends ConsumerStatefulWidget {
  const _LogoCard();

  @override
  ConsumerState<_LogoCard> createState() => _LogoCardState();
}

class _LogoCardState extends ConsumerState<_LogoCard> {
  bool _uploading = false;
  bool _processing = false;
  ProcessedWorkspaceLogo? _pendingLogo;
  double? _uploadProgress;

  String _fmtBytes(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> _pickImage() async {
    setState(() => _processing = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null || !mounted) return;
      final processed = await WorkspaceLogoProcessor.process(
        await picked.readAsBytes(),
      );
      if (mounted) setState(() => _pendingLogo = processed);
    } on WorkspaceLogoProcessingException catch (error) {
      if (mounted) {
        final message = tr(error.code, ref)
            .replaceAll(
              '%s',
              _fmtBytes(error.encodedLength ?? error.sourceBytes ?? 0),
            )
            .replaceAll('%1', error.width?.toString() ?? '')
            .replaceAll('%2', error.height?.toString() ?? '');
        ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(message));
      }
    } catch (error, stackTrace) {
      debugPrint('Workspace logo processing failed: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(errorSnackBar(tr(AppErrorMapper.key(error), ref)));
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _confirmUpload() async {
    final logo = _pendingLogo;
    if (logo == null) return;
    setState(() {
      _uploading = true;
      _uploadProgress = null; // null = indeterminate LinearProgressIndicator
    });

    try {
      if (!await _requireAdminSettingsAccess(context, ref)) return;
      await ref.read(settingsNotifierProvider.notifier).saveProcessedLogo(logo);

      if (mounted) {
        setState(() => _pendingLogo = null);
        ScaffoldMessenger.of(context)
            .showSnackBar(successSnackBar(tr('msg_logo_uploaded', ref)));
      }
    } catch (e) {
      if (mounted) {
        final detail = e is FirebaseException ? ' [${e.plugin}/${e.code}]' : '';
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context)
            .showSnackBar(errorSnackBar('${tr(key, ref)}$detail'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _uploadProgress = null;
        });
      }
    }
  }

  Future<void> _deleteLogo() async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: tr('confirm_remove_logo', ref),
      message: tr('confirm_remove_logo_msg', ref),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _uploading = true);
    try {
      if (!await _requireAdminSettingsAccess(context, ref)) return;
      await ref.read(settingsNotifierProvider.notifier).deleteLogo();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(successSnackBar(tr('msg_logo_removed', ref)));
      }
    } catch (e) {
      if (mounted) {
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(tr(key, ref)));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value;
    // Logo bytes come straight from Firestore via the real-time stream.
    // No URL, no CDN, no Firebase Storage needed.
    final savedLogoBytes = settings?.logoBytes;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('settings_company_logo', ref),
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              tr('settings_logo_specs', ref),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),

            // â”€â”€ Image area: local preview / uploaded logo / placeholder â”€â”€
            if (_pendingLogo != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  _pendingLogo!.pngBytes,
                  height: 80,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tr('settings_logo_preview_details', ref)
                    .replaceAll('%1', '${_pendingLogo!.width}')
                    .replaceAll('%2', '${_pendingLogo!.height}')
                    .replaceAll('%3', _fmtBytes(_pendingLogo!.base64.length))
                    .replaceAll('%4', '${_pendingLogo!.sourceWidth}')
                    .replaceAll('%5', '${_pendingLogo!.sourceHeight}'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ] else if (savedLogoBytes != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  savedLogoBytes,
                  height: 80,
                  fit: BoxFit.contain,
                ),
              ),
            ] else ...[
              Container(
                height: 80,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.image_outlined,
                    size: 40,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),

            // â”€â”€ Upload progress bar â”€â”€
            if (_processing || _uploading) ...[
              LinearProgressIndicator(value: _uploadProgress),
              const SizedBox(height: 6),
              Text(
                _processing
                    ? tr('settings_logo_processing', ref)
                    : _uploadProgress != null
                    ? tr(
                        'settings_uploading_pct',
                        ref,
                      ).replaceAll('%s', '${(_uploadProgress! * 100).round()}')
                    : tr('settings_uploading', ref),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: 4),
            ],

            // â”€â”€ Action buttons â”€â”€
            if (!_uploading && !_processing)
              if (_pendingLogo != null)
                // Confirm / discard flow
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _confirmUpload,
                      icon: const Icon(Icons.cloud_upload, size: 18),
                      label: Text(tr('lbl_upload', ref)),
                    ),
                    OutlinedButton(
                      onPressed: () => setState(() {
                        _pendingLogo = null;
                      }),
                      child: Text(tr('cancel', ref)),
                    ),
                  ],
                )
              else
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.upload, size: 18),
                      label: Text(
                        savedLogoBytes != null
                            ? tr('settings_replace_logo', ref)
                            : tr('settings_upload_logo', ref),
                      ),
                    ),
                    if (savedLogoBytes != null)
                      OutlinedButton.icon(
                        onPressed: _deleteLogo,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppBrand.errorColor,
                          side: const BorderSide(color: AppBrand.errorColor),
                        ),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: Text(tr('lbl_remove', ref)),
                      ),
                  ],
                ),
          ],
        ),
      ),
    );
  }
}
