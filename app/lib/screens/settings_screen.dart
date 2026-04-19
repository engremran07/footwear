import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/snack_helper.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';

import '../widgets/confirm_dialog.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _companyC = TextEditingController();
  final _ppcC = TextEditingController();
  bool _requireAdminApprovalForSellerTransactionEdits = false;
  bool _showArabicColumnNamesInEnglishReports = false;
  bool _settingsLoaded = false;
  bool _isDirty = false;

  @override
  void dispose() {
    _companyC.dispose();
    _ppcC.dispose();
    super.dispose();
  }

  void _loadSettings() {
    if (_settingsLoaded) return;
    final s = ref.read(settingsProvider).value;
    if (s != null) {
      _companyC.value = TextEditingValue(
        text: s.companyName,
        selection: TextSelection.collapsed(offset: s.companyName.length),
      );
      final ppcStr = s.pairsPerCarton.toString();
      _ppcC.value = TextEditingValue(
        text: ppcStr,
        selection: TextSelection.collapsed(offset: ppcStr.length),
      );
      _requireAdminApprovalForSellerTransactionEdits =
          s.requireAdminApprovalForSellerTransactionEdits;
      _showArabicColumnNamesInEnglishReports =
          s.showArabicColumnNamesInEnglishReports;
      _settingsLoaded = true;
    }
  }

  Future<void> _saveSettings() async {
    try {
      await ref.read(settingsNotifierProvider.notifier).save({
        'company_name': _companyC.text.trim(),
        'pairs_per_carton': int.tryParse(_ppcC.text.trim()) ?? 12,
        'require_admin_approval_for_seller_transaction_edits':
            _requireAdminApprovalForSellerTransactionEdits,
        'show_arabic_column_names_in_english_reports':
            _showArabicColumnNamesInEnglishReports,
      });
      if (mounted) {
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

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final currentUser = ref.watch(authUserProvider).value;
    if (currentUser != null && !currentUser.isAdmin) {
      return Scaffold(body: Center(child: Text(tr('permission_denied', ref))));
    }
    settingsAsync.whenData((_) => _loadSettings());

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
        body: ListView(
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
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _companyC,
                      decoration: InputDecoration(
                        labelText: tr('company_name', ref),
                      ),
                      onChanged: (_) {
                        if (!_isDirty) setState(() => _isDirty = true);
                      },
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
                      value: _requireAdminApprovalForSellerTransactionEdits,
                      onChanged: (value) {
                        setState(() {
                          _requireAdminApprovalForSellerTransactionEdits =
                              value;
                          _isDirty = true;
                        });
                      },
                      title: Text(tr('require_approval_title', ref)),
                      subtitle: Text(tr('require_approval_subtitle', ref)),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _showArabicColumnNamesInEnglishReports,
                      onChanged: (value) {
                        setState(() {
                          _showArabicColumnNamesInEnglishReports = value;
                          _isDirty = true;
                        });
                      },
                      title: Text(tr('report_columns_arabic_title', ref)),
                      subtitle: Text(tr('report_columns_arabic_subtitle', ref)),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saveSettings,
                        child: Text(tr('save', ref)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Company Logo (admin only)
            if (currentUser?.isAdmin == true) ...[
              const _LogoCard(),
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
              // â”€â”€ Danger Zone â”€â”€
              Card(
                color: AppBrand.errorColor.withAlpha(12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: AppBrand.errorColor.withAlpha(80)),
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
  Uint8List? _pendingBytes;
  String? _pendingSizeLabel;
  double? _uploadProgress;

  String _fmtBytes(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      // Auto-optimise: image_picker resizes + JPEG-compresses before returning bytes.
      // 256Ã—256 for a logo icon is sufficient; keeps Firestore doc size small.
      maxWidth: 256,
      maxHeight: 256,
      imageQuality: 70,
    );
    if (picked == null) return;
    var bytes = await picked.readAsBytes();

    // Secondary compression via flutter_image_compress (S-07 hardening).
    try {
      final compressed = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 256,
        minHeight: 256,
        quality: 65,
        format: CompressFormat.jpeg,
      );
      bytes = compressed;
    } catch (_) {
      // Fall through with original bytes if compress fails.
    }

    // Hard guard: base64 encoding adds ~33%, so cap raw at 37 KB â†’ ~50 KB base64
    const maxRawBytes = 37 * 1024;
    if (bytes.lengthInBytes > maxRawBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          warningSnackBar(
            'Image is ${_fmtBytes(bytes.lengthInBytes)} â€” too large. '
            'Use a simpler image or reduce dimensions to 256Ã—256 px.',
          ),
        );
      }
      return;
    }

    setState(() {
      _pendingBytes = bytes;
      _pendingSizeLabel = _fmtBytes(bytes.lengthInBytes);
    });
  }

  Future<void> _confirmUpload() async {
    final bytes = _pendingBytes;
    if (bytes == null) return;
    setState(() {
      _uploading = true;
      _uploadProgress = null; // null = indeterminate LinearProgressIndicator
    });

    try {
      // Encode bytes as Base64 and store directly in Firestore.
      // The settingsProvider real-time stream propagates the new logo to every
      // connected device instantly â€” no Firebase Storage or CDN involved.
      final encoded = base64Encode(bytes);

      // S-07: Final base64 size cap â€” 50 KB max to keep Firestore reads cheap.
      if (encoded.length > 50 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            warningSnackBar(
              'Encoded logo is ${_fmtBytes(encoded.length)} â€” exceeds 50 KB limit.',
            ),
          );
        }
        setState(() => _uploading = false);
        return;
      }

      await ref.read(settingsNotifierProvider.notifier).save({
        'logo_base64': encoded,
        'logo_url': null,
      });

      if (mounted) {
        setState(() {
          _pendingBytes = null;
          _pendingSizeLabel = null;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(successSnackBar(tr('msg_logo_uploaded', ref)));
      }
    } catch (e) {
      if (mounted) {
        final detail = e is FirebaseException ? ' [${e.plugin}/${e.code}]' : '';
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(errorSnackBar('${tr(key, ref)}$detail'));
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
    if (confirmed != true) return;
    setState(() => _uploading = true);
    try {
      await ref.read(settingsNotifierProvider.notifier).deleteLogo();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(successSnackBar(tr('msg_logo_removed', ref)));
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
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              tr('settings_logo_specs', ref),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),

            // â”€â”€ Image area: local preview / uploaded logo / placeholder â”€â”€
            if (_pendingBytes != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  _pendingBytes!,
                  height: 80,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tr(
                  'lbl_preview',
                  ref,
                ).replaceAll('%s', _pendingSizeLabel ?? ''),
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
            if (_uploading) ...[
              LinearProgressIndicator(value: _uploadProgress),
              const SizedBox(height: 6),
              Text(
                _uploadProgress != null
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
            if (!_uploading)
              if (_pendingBytes != null)
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
                        _pendingBytes = null;
                        _pendingSizeLabel = null;
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
