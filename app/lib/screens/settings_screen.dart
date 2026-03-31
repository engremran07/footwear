import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/snack_helper.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/route_provider.dart';
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
    final s = ref.read(settingsProvider).valueOrNull;
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
      _settingsLoaded = true;
    }
  }

  Future<void> _saveSettings() async {
    try {
      await ref.read(settingsNotifierProvider.notifier).save({
        'company_name': _companyC.text.trim(),
        'currency': _currencyC.text.trim(),
        'pairs_per_carton': int.tryParse(_ppcC.text.trim()) ?? 12,
      });
      if (mounted) {
        setState(() => _isDirty = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(successSnackBar(tr('saved_successfully', ref)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(errorSnackBar('$e'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final currentUser = ref.watch(authUserProvider).valueOrNull;
    if (currentUser != null && !currentUser.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('settings', ref))),
        body: Center(child: Text(tr('permission_denied', ref))),
      );
    }
    // Only watch allUsersProvider when the current user is confirmed admin.
    // This prevents permission-denied errors from firing for seller accounts.
    final usersAsync = currentUser?.isAdmin == true
        ? ref.watch(allUsersProvider)
        : const AsyncValue<List<UserModel>>.loading();
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
        appBar: AppBar(title: Text(tr('settings', ref))),
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
                    Text(tr('business_settings', ref),
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _companyC,
                      decoration:
                          InputDecoration(labelText: tr('company_name', ref)),
                      onChanged: (_) {
                        if (!_isDirty) setState(() => _isDirty = true);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _currencyC,
                      decoration:
                          InputDecoration(labelText: tr('currency', ref)),
                      onChanged: (_) {
                        if (!_isDirty) setState(() => _isDirty = true);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _ppcC,
                      decoration: InputDecoration(
                          labelText: tr('pairs_per_carton', ref)),
                      keyboardType: TextInputType.number,
                      onChanged: (_) {
                        if (!_isDirty) setState(() => _isDirty = true);
                      },
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
            // User Management (admin only)
            if (currentUser?.isAdmin == true) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(tr('users', ref),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => _showCreateUserDialog(),
                            icon: const Icon(Icons.person_add, size: 18),
                            label: Text(tr('new_user', ref)),
                          ),
                        ],
                      ),
                      const Divider(),
                      usersAsync.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (e, _) => Text('$e'),
                        data: (users) {
                          if (users.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(tr('no_data', ref)),
                            );
                          }
                          return Column(
                            children: users.map((u) {
                              final isSelf = u.id == currentUser?.id;
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // ── Top row: avatar + name + email + role ──
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 16,
                                          backgroundColor: u.isAdmin
                                              ? AppBrand.adminRoleColor
                                                  .withAlpha(30)
                                              : AppBrand.sellerRoleColor
                                                  .withAlpha(30),
                                          child: Icon(
                                            u.isAdmin
                                                ? Icons.admin_panel_settings
                                                : Icons.person,
                                            size: 16,
                                            color: u.isAdmin
                                                ? AppBrand.adminRoleColor
                                                : AppBrand.sellerRoleColor,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                u.displayName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w500),
                                              ),
                                              Text(
                                                u.email,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    // ── Bottom row: role chip + route + actions ──
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: (u.isAdmin
                                                    ? AppBrand.adminRoleColor
                                                    : AppBrand.sellerRoleColor)
                                                .withAlpha(25),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            u.role.name,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: u.isAdmin
                                                  ? AppBrand.adminRoleColor
                                                  : AppBrand.sellerRoleColor,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        if (u.isSeller &&
                                            u.assignedRouteName != null) ...[
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              '• ${u.assignedRouteName}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style:
                                                  const TextStyle(fontSize: 11),
                                            ),
                                          ),
                                        ],
                                        const Spacer(),
                                        // ── Action buttons ──
                                        GestureDetector(
                                          onTap: () => _showEditUserDialog(u),
                                          child: const Padding(
                                            padding: EdgeInsets.all(4),
                                            child: Icon(Icons.edit, size: 16),
                                          ),
                                        ),
                                        if (!isSelf && !u.isAdmin)
                                          GestureDetector(
                                            onTap: () => _confirmDeleteUser(u),
                                            child: const Padding(
                                              padding: EdgeInsets.all(4),
                                              child: Icon(Icons.delete,
                                                  size: 16,
                                                  color: AppBrand.errorColor),
                                            ),
                                          ),
                                        SizedBox(
                                          width: 36,
                                          height: 24,
                                          child: FittedBox(
                                            child: Switch(
                                              value: u.active,
                                              onChanged: isSelf
                                                  ? null
                                                  : (v) => ref
                                                      .read(
                                                          userManagementNotifierProvider
                                                              .notifier)
                                                      .toggleActive(u.id, v),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Divider(height: 8),
                                  ],
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  ),
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

  void _showCreateUserDialog() {
    final emailC = TextEditingController();
    final passC = TextEditingController();
    final nameC = TextEditingController();
    String role = 'seller';
    String? selectedRouteId;
    String? selectedRouteName;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final routes = ref.watch(routesProvider).valueOrNull ?? [];
          final availableRoutes = routes
              .where((r) =>
                  r.assignedSellerId == null || r.assignedSellerId!.isEmpty)
              .toList();
          return AlertDialog(
            title: Text(tr('new_user', ref)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameC,
                    decoration: InputDecoration(labelText: tr('name', ref)),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: emailC,
                    decoration: InputDecoration(labelText: tr('email', ref)),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: passC,
                    decoration: InputDecoration(labelText: tr('password', ref)),
                    obscureText: true,
                    keyboardType: TextInputType.visiblePassword,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    decoration: InputDecoration(labelText: tr('role', ref)),
                    items: [
                      DropdownMenuItem(
                          value: 'admin', child: Text(tr('lbl_admin', ref))),
                      DropdownMenuItem(
                          value: 'seller', child: Text(tr('lbl_seller', ref))),
                    ],
                    onChanged: (v) => setS(() {
                      role = v ?? 'seller';
                      if (role != 'seller') {
                        selectedRouteId = null;
                        selectedRouteName = null;
                      }
                    }),
                  ),
                  if (role == 'seller') ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: selectedRouteId,
                      decoration: InputDecoration(
                        labelText: tr('assigned_route', ref),
                      ),
                      items: [
                        ...availableRoutes.map((r) => DropdownMenuItem(
                              value: r.id,
                              child: Text(r.name),
                            )),
                      ],
                      onChanged: (v) => setS(() {
                        selectedRouteId = v;
                        selectedRouteName = routes
                            .where((r) => r.id == v)
                            .map((r) => r.name)
                            .firstOrNull;
                      }),
                    ),
                  ],
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
                  if (nameC.text.trim().isEmpty ||
                      emailC.text.trim().isEmpty ||
                      passC.text.trim().isEmpty) {
                    return;
                  }
                  if (role == 'seller' &&
                      (selectedRouteId == null ||
                          selectedRouteId!.trim().isEmpty)) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                            content: Text(tr('msg_seller_needs_route', ref))),
                      );
                    }
                    return;
                  }
                  try {
                    await ref
                        .read(userManagementNotifierProvider.notifier)
                        .createUser(
                          email: emailC.text.trim(),
                          password: passC.text.trim(),
                          displayName: nameC.text.trim(),
                          role: role,
                          assignedRouteId: selectedRouteId,
                          assignedRouteName: selectedRouteName,
                        );
                    if (mounted) {
                      Navigator.of(context, rootNavigator: true).pop();
                    }
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx)
                          .showSnackBar(errorSnackBar('$e'));
                    }
                  }
                },
                child: Text(tr('create', ref)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditUserDialog(UserModel user) {
    final nameC = TextEditingController(text: user.displayName);
    String role = user.isAdmin ? 'admin' : 'seller';
    final currentUser = ref.read(authUserProvider).valueOrNull;
    final isSelf = currentUser?.id == user.id;
    String? selectedRouteId = user.assignedRouteId;
    String? selectedRouteName = user.assignedRouteName;
    final oldRouteId = user.assignedRouteId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final routes = ref.watch(routesProvider).valueOrNull ?? [];
          final availableRoutes = routes
              .where((r) =>
                  r.id == selectedRouteId ||
                  r.assignedSellerId == null ||
                  r.assignedSellerId!.isEmpty ||
                  r.assignedSellerId == user.id)
              .toList();
          return AlertDialog(
            title: Text(tr('edit_user', ref)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameC,
                    decoration: InputDecoration(labelText: tr('name', ref)),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: TextEditingController(text: user.email),
                    decoration: InputDecoration(
                      labelText: tr('lbl_email', ref),
                      helperText: tr('lbl_email_no_change', ref),
                    ),
                    enabled: false,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.lock_reset),
                      label: Text(tr('settings_send_reset_email', ref)),
                      onPressed: () async {
                        try {
                          await ref
                              .read(userManagementNotifierProvider.notifier)
                              .sendPasswordResetForSeller(email: user.email);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              successSnackBar(tr('msg_reset_email_sent', ref)
                                  .replaceAll('%s', user.email)),
                            );
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            final key = AppErrorMapper.key(e);
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              errorSnackBar(tr(key, ref)),
                            );
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (isSelf)
                    TextField(
                      enabled: false,
                      decoration: InputDecoration(
                        labelText: tr('role', ref),
                        hintText: role,
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: InputDecoration(labelText: tr('role', ref)),
                      items: [
                        DropdownMenuItem(
                            value: 'admin', child: Text(tr('lbl_admin', ref))),
                        DropdownMenuItem(
                            value: 'seller',
                            child: Text(tr('lbl_seller', ref))),
                      ],
                      onChanged: (v) => setS(() {
                        role = v ?? 'seller';
                        if (role != 'seller') {
                          selectedRouteId = null;
                          selectedRouteName = null;
                        }
                      }),
                    ),
                  if (role == 'seller') ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: selectedRouteId,
                      decoration: InputDecoration(
                        labelText: tr('assigned_route', ref),
                      ),
                      items: [
                        ...availableRoutes.map((r) => DropdownMenuItem(
                              value: r.id,
                              child: Text(r.name),
                            )),
                      ],
                      onChanged: (v) => setS(() {
                        selectedRouteId = v;
                        selectedRouteName = routes
                            .where((r) => r.id == v)
                            .map((r) => r.name)
                            .firstOrNull;
                      }),
                    ),
                  ],
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
                  final currentUser = ref.read(authUserProvider).valueOrNull;
                  if (currentUser?.isAdmin != true) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        errorSnackBar(tr('err_permission_denied', ref)),
                      );
                    }
                    return;
                  }
                  if (nameC.text.trim().isEmpty) return;
                  if (role == 'seller' &&
                      (selectedRouteId == null ||
                          selectedRouteId!.trim().isEmpty)) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        warningSnackBar(tr('msg_seller_needs_route', ref)),
                      );
                    }
                    return;
                  }
                  try {
                    final notifier =
                        ref.read(userManagementNotifierProvider.notifier);
                    if (oldRouteId != null && oldRouteId != selectedRouteId) {
                      await notifier.clearRouteAssignment(oldRouteId);
                    }
                    await notifier.updateUser(user.id, {
                      'display_name': nameC.text.trim(),
                      'role': isSelf ? 'admin' : role,
                      'assigned_route_id': selectedRouteId,
                      'assigned_route_name': selectedRouteName,
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                  } catch (e) {
                    if (ctx.mounted) {
                      final key = AppErrorMapper.key(e);
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        errorSnackBar(tr(key, ref)),
                      );
                    }
                  }
                },
                child: Text(tr('save', ref)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDeleteUser(UserModel user) async {
    final me = ref.read(authUserProvider).valueOrNull;
    if (me?.isAdmin != true) return;
    if (user.id == me?.id || user.isAdmin) return;

    final confirmed = await ConfirmDialog.show(
      context,
      title: tr('delete', ref),
      message:
          tr('confirm_delete_user', ref).replaceAll('%s', user.displayName),
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(userManagementNotifierProvider.notifier)
          .deleteUser(user.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          successSnackBar(
              tr('msg_user_deleted', ref).replaceAll('%s', user.displayName)),
        );
      }
    } catch (e) {
      if (mounted) {
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(tr(key, ref)));
      }
    }
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
        ScaffoldMessenger.of(context).showSnackBar(warningSnackBar(
          'Image is ${_fmtBytes(bytes.lengthInBytes)} — too large. '
          'Use a simpler image or reduce dimensions to 256×256 px.',
        ));
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
          ScaffoldMessenger.of(context).showSnackBar(warningSnackBar(
            'Encoded logo is ${_fmtBytes(encoded.length)} — exceeds 50 KB limit.',
          ));
        }
        setState(() => _uploading = false);
        return;
      }

      await ref
          .read(settingsNotifierProvider.notifier)
          .save({'logo_base64': encoded, 'logo_url': null});

      if (mounted) {
        setState(() {
          _pendingBytes = null;
          _pendingSizeLabel = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          successSnackBar(tr('msg_logo_uploaded', ref)),
        );
      }
    } catch (e) {
      if (mounted) {
        final detail = e is FirebaseException ? ' [${e.plugin}/${e.code}]' : '';
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context).showSnackBar(
          errorSnackBar('${tr(key, ref)}$detail'),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          successSnackBar(tr('msg_logo_removed', ref)),
        );
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
    final settings = ref.watch(settingsProvider).valueOrNull;
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
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
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
                tr('lbl_preview', ref)
                    .replaceAll('%s', _pendingSizeLabel ?? ''),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                      color: Theme.of(context).colorScheme.outlineVariant),
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
                    ? tr('settings_uploading_pct', ref)
                        .replaceAll('%s', '${(_uploadProgress! * 100).round()}')
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
                      child: const Text('Cancel'),
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
                      label: Text(savedLogoBytes != null
                          ? tr('settings_replace_logo', ref)
                          : tr('settings_upload_logo', ref)),
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
