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
import '../providers/database_flush_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/user_provider.dart';
import '../widgets/confirm_dialog.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _companyC = TextEditingController();
  final _currencyC = TextEditingController();
  final _ppcC = TextEditingController();
  bool _requireAdminApprovalForSellerTransactionEdits = false;
  bool _settingsLoaded = false;
  bool _isDirty = false;

  @override
  void dispose() {
    _companyC.dispose();
    _currencyC.dispose();
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
      _currencyC.value = TextEditingValue(
        text: s.currency,
        selection: TextSelection.collapsed(offset: s.currency.length),
      );
      final ppcStr = s.pairsPerCarton.toString();
      _ppcC.value = TextEditingValue(
        text: ppcStr,
        selection: TextSelection.collapsed(offset: ppcStr.length),
      );
      _requireAdminApprovalForSellerTransactionEdits =
          s.requireAdminApprovalForSellerTransactionEdits;
      _settingsLoaded = true;
    }
  }

  Future<void> _saveSettings() async {
    try {
      await ref.read(settingsNotifierProvider.notifier).save({
        'company_name': _companyC.text.trim(),
        'currency': _currencyC.text.trim(),
        'pairs_per_carton': int.tryParse(_ppcC.text.trim()) ?? 12,
        'require_admin_approval_for_seller_transaction_edits':
            _requireAdminApprovalForSellerTransactionEdits,
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
                      controller: _currencyC,
                      decoration: InputDecoration(
                        labelText: tr('currency', ref),
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
            // ── Danger Zone ──
            _DatabaseFlushSection(),
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

// ─── Company Logo Card ────────────────────────────────────────────────────────

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
      // 256×256 for a logo icon is sufficient; keeps Firestore doc size small.
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

    // Hard guard: base64 encoding adds ~33%, so cap raw at 37 KB → ~50 KB base64
    const maxRawBytes = 37 * 1024;
    if (bytes.lengthInBytes > maxRawBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          warningSnackBar(
            'Image is ${_fmtBytes(bytes.lengthInBytes)} — too large. '
            'Use a simpler image or reduce dimensions to 256×256 px.',
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
      // connected device instantly — no Firebase Storage or CDN involved.
      final encoded = base64Encode(bytes);

      // S-07: Final base64 size cap — 50 KB max to keep Firestore reads cheap.
      if (encoded.length > 50 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            warningSnackBar(
              'Encoded logo is ${_fmtBytes(encoded.length)} — exceeds 50 KB limit.',
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

            // ── Image area: local preview / uploaded logo / placeholder ──
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

            // ── Upload progress bar ──
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

            // ── Action buttons ──
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

// ═══════════════════════════════════════════════════════════════════════════════
// Danger Zone — Database Flush Section
// ═══════════════════════════════════════════════════════════════════════════════

class _DatabaseFlushSection extends ConsumerStatefulWidget {
  @override
  ConsumerState<_DatabaseFlushSection> createState() =>
      _DatabaseFlushSectionState();
}

class _DatabaseFlushSectionState extends ConsumerState<_DatabaseFlushSection> {
  bool _includeUsers = false;
  String? _selectedUserId;
  bool _flushing = false;

  Future<void> _executeFlush(
    String operationKey,
    String descKey,
    Future<FlushResult> Function() action,
  ) async {
    // Step 1: "Are you sure?" confirmation
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: AppBrand.errorColor,
              size: 28,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(tr('flush_confirm_title', ref))),
          ],
        ),
        content: Text(
          tr(
            'flush_confirm_message',
            ref,
          ).replaceAll('%s', tr(descKey, ref).toLowerCase()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel', ref)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppBrand.errorColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('flush_confirm_button', ref)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Step 2: Password + countdown confirmation
    final passwordOk = await _showPasswordCountdownDialog();
    if (passwordOk != true || !mounted) return;

    // Step 3: Execute flush
    setState(() => _flushing = true);
    try {
      final result = await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          successSnackBar(
            tr(
              'flush_success',
              ref,
            ).replaceAll('%s', '${result.totalAffected}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(errorSnackBar(tr(AppErrorMapper.key(e), ref)));
      }
    } finally {
      if (mounted) setState(() => _flushing = false);
    }
  }

  Future<bool?> _showPasswordCountdownDialog() {
    final passwordC = TextEditingController();
    int countdown = 10;
    String? errorText;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          // Start countdown timer
          if (countdown > 0) {
            Future.delayed(const Duration(seconds: 1), () {
              if (ctx.mounted && countdown > 0) {
                setS(() => countdown--);
              }
            });
          }
          return AlertDialog(
            title: Text(tr('flush_password_title', ref)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: passwordC,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: tr('flush_password_hint', ref),
                    errorText: errorText,
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                  onChanged: (_) {
                    if (errorText != null) setS(() => errorText = null);
                  },
                ),
                const SizedBox(height: 16),
                if (countdown > 0)
                  Text(
                    tr('flush_countdown', ref).replaceAll('%s', '$countdown'),
                    style: const TextStyle(
                      color: AppBrand.warningColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('cancel', ref)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppBrand.errorColor,
                ),
                onPressed: countdown > 0 || passwordC.text.isEmpty
                    ? null
                    : () async {
                        final ok = await ref
                            .read(databaseFlushProvider.notifier)
                            .reauthenticate(passwordC.text);
                        if (ok) {
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } else {
                          setS(
                            () => errorText = tr('flush_password_wrong', ref),
                          );
                        }
                      },
                child: Text(tr('flush_confirm_button', ref)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authUserProvider).value;
    if (currentUser == null || !currentUser.isAdmin) {
      return const SizedBox.shrink();
    }
    final users = ref.watch(allUsersProvider).value ?? [];
    final nonAdminUsers = users.where((u) => !u.isAdmin).toList();

    return Stack(
      children: [
        Card(
          color: AppBrand.errorColor.withAlpha(15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppBrand.errorColor.withAlpha(80)),
          ),
          child: ExpansionTile(
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
            subtitle: Text(
              tr('danger_zone_subtitle', ref),
              style: TextStyle(
                color: AppBrand.errorColor.withAlpha(180),
                fontSize: 12,
              ),
            ),
            children: [
              const Divider(height: 1),
              // Individual flush options
              _flushTile(
                icon: Icons.receipt_long_outlined,
                titleKey: 'flush_financial',
                descKey: 'flush_financial_desc',
                onTap: () => _executeFlush(
                  'flush_financial',
                  'flush_financial_desc',
                  () => ref
                      .read(databaseFlushProvider.notifier)
                      .flushFinancialData(),
                ),
              ),
              _flushTile(
                icon: Icons.inventory_2_outlined,
                titleKey: 'flush_inventory',
                descKey: 'flush_inventory_desc',
                onTap: () => _executeFlush(
                  'flush_inventory',
                  'flush_inventory_desc',
                  () =>
                      ref.read(databaseFlushProvider.notifier).flushInventory(),
                ),
              ),
              _flushTile(
                icon: Icons.store_outlined,
                titleKey: 'flush_shops',
                descKey: 'flush_shops_desc',
                onTap: () => _executeFlush(
                  'flush_shops',
                  'flush_shops_desc',
                  () => ref.read(databaseFlushProvider.notifier).flushShops(),
                ),
              ),
              _flushTile(
                icon: Icons.route_outlined,
                titleKey: 'flush_routes',
                descKey: 'flush_routes_desc',
                onTap: () => _executeFlush(
                  'flush_routes',
                  'flush_routes_desc',
                  () => ref.read(databaseFlushProvider.notifier).flushRoutes(),
                ),
              ),
              _flushTile(
                icon: Icons.shopping_bag_outlined,
                titleKey: 'flush_products',
                descKey: 'flush_products_desc',
                onTap: () => _executeFlush(
                  'flush_products',
                  'flush_products_desc',
                  () =>
                      ref.read(databaseFlushProvider.notifier).flushProducts(),
                ),
              ),
              _flushTile(
                icon: Icons.settings_backup_restore,
                titleKey: 'flush_settings',
                descKey: 'flush_settings_desc',
                onTap: () => _executeFlush(
                  'flush_settings',
                  'flush_settings_desc',
                  () =>
                      ref.read(databaseFlushProvider.notifier).resetSettings(),
                ),
              ),

              const Divider(height: 1),

              // Per-user flush
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('flush_per_user', ref),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppBrand.errorColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr('flush_per_user_desc', ref),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedUserId,
                      decoration: InputDecoration(
                        labelText: tr('flush_select_user', ref),
                        isDense: true,
                      ),
                      items: nonAdminUsers
                          .map(
                            (u) => DropdownMenuItem(
                              value: u.id,
                              child: Text(u.displayName),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _selectedUserId = v),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppBrand.errorColor,
                          side: const BorderSide(color: AppBrand.errorColor),
                        ),
                        onPressed: _selectedUserId == null
                            ? null
                            : () => _executeFlush(
                                'flush_per_user',
                                'flush_per_user_desc',
                                () => ref
                                    .read(databaseFlushProvider.notifier)
                                    .flushPerUser(_selectedUserId!),
                              ),
                        icon: const Icon(
                          Icons.person_remove_outlined,
                          size: 18,
                        ),
                        label: Text(tr('flush_per_user', ref)),
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Full database reset (nuclear option)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _includeUsers,
                      onChanged: (v) =>
                          setState(() => _includeUsers = v ?? false),
                      title: Text(
                        tr('flush_include_users', ref),
                        style: const TextStyle(fontSize: 14),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppBrand.errorColor,
                        ),
                        onPressed: () => _executeFlush(
                          'flush_all',
                          'flush_all_desc',
                          () => ref
                              .read(databaseFlushProvider.notifier)
                              .flushAll(
                                keepAdminId: currentUser.id,
                                includeUsers: _includeUsers,
                              ),
                        ),
                        icon: const Icon(Icons.delete_forever, size: 20),
                        label: Text(
                          tr('flush_all', ref).toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Full-screen loading overlay
        if (_flushing)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.scrim.withValues(alpha: 0.54),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: AppBrand.onPrimary),
                    const SizedBox(height: 16),
                    Text(
                      tr('flush_in_progress', ref),
                      style: const TextStyle(
                        color: AppBrand.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _flushTile({
    required IconData icon,
    required String titleKey,
    required String descKey,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppBrand.errorColor),
      title: Text(
        tr(titleKey, ref),
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        tr(descKey, ref),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
