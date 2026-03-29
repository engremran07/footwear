import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/error_mapper.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/route_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/theme_preference_provider.dart';
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
  final _myNameC = TextEditingController();
  bool _settingsLoaded = false;

  @override
  void dispose() {
    _companyC.dispose();
    _currencyC.dispose();
    _ppcC.dispose();
    _myNameC.dispose();
    super.dispose();
  }

  Future<void> _renameMyself() async {
    final me = ref.read(authUserProvider).valueOrNull;
    if (me == null) return;
    final name = _myNameC.text.trim();
    if (name.isEmpty || name == me.displayName) return;
    try {
      await ref
          .read(userManagementNotifierProvider.notifier)
          .updateUser(me.id, {'display_name': name});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr('saved_successfully', ref))));
      }
    } catch (e) {
      if (mounted) {
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr(key, ref))));
      }
    }
  }

  void _loadSettings() {
    if (_settingsLoaded) return;
    final s = ref.read(settingsProvider).valueOrNull;
    if (s != null) {
      _companyC.text = s.companyName;
      _currencyC.text = s.currency;
      _ppcC.text = s.pairsPerCarton.toString();
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
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr('saved_successfully', ref))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final currentUser = ref.watch(authUserProvider).valueOrNull;
    // Only watch allUsersProvider when the current user is confirmed admin.
    // This prevents permission-denied errors from firing for seller accounts.
    final usersAsync = currentUser?.isAdmin == true
        ? ref.watch(allUsersProvider)
        : const AsyncValue<List<UserModel>>.loading();
    final locale = ref.watch(appLocaleProvider);

    settingsAsync.whenData((_) => _loadSettings());

    // Pre-fill my name field once (non-reactive to avoid cursor jumps).
    if (currentUser != null && _myNameC.text.isEmpty) {
      _myNameC.text = currentUser.displayName;
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr('settings', ref))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── My Profile ─────────────────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'My Profile',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your name appears in the Entry By column of all PDF reports.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _myNameC,
                    decoration:
                        const InputDecoration(labelText: 'Display Name'),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _renameMyself,
                      child: Text(tr('save', ref)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Language selector
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('language', ref),
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SegmentedButton<AppLocale>(
                    segments: AppLocale.values
                        .map((l) =>
                            ButtonSegment(value: l, label: Text(l.label)))
                        .toList(),
                    selected: {locale},
                    onSelectionChanged: (s) =>
                        ref.read(appLocaleProvider.notifier).state = s.first,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Appearance (theme) selector — available to all users
          _AppearanceCard(),
          const SizedBox(height: 16),
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
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _currencyC,
                    decoration: InputDecoration(labelText: tr('currency', ref)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _ppcC,
                    decoration:
                        InputDecoration(labelText: tr('pairs_per_carton', ref)),
                    keyboardType: TextInputType.number,
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
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: u.isAdmin
                                    ? AppBrand.adminRoleColor.withAlpha(30)
                                    : AppBrand.sellerRoleColor.withAlpha(30),
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
                              title: Text(u.displayName),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    u.email,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
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
                                      if (!u.active) ...[
                                        const SizedBox(width: 4),
                                        const Text(
                                          '• inactive',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: AppBrand.errorColor),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!isSelf)
                                    IconButton(
                                      icon: const Icon(Icons.edit, size: 18),
                                      onPressed: () => _showEditUserDialog(u),
                                    ),
                                  Switch(
                                    value: u.active,
                                    onChanged: isSelf
                                        ? null
                                        : (v) => ref
                                            .read(userManagementNotifierProvider
                                                .notifier)
                                            .toggleActive(u.id, v),
                                  ),
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Security',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.password),
                    title: const Text('Change My Password'),
                    subtitle: Text(
                      currentUser?.isAdmin == true
                          ? 'Change your own admin password'
                          : 'Change your seller account password',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: currentUser == null
                        ? null
                        : () => _showChangeOwnPasswordDialog(),
                  ),
                ],
              ),
            ),
          ),
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
    );
  }

  void _showChangeOwnPasswordDialog() {
    final currentPassC = TextEditingController();
    final newPassC = TextEditingController();
    final confirmPassC = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Password'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentPassC,
                decoration:
                    const InputDecoration(labelText: 'Current Password'),
                obscureText: true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: newPassC,
                decoration: const InputDecoration(labelText: 'New Password'),
                obscureText: true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmPassC,
                decoration:
                    const InputDecoration(labelText: 'Confirm New Password'),
                obscureText: true,
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
              if (newPassC.text.trim() != confirmPassC.text.trim()) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('New passwords do not match')),
                );
                return;
              }
              try {
                await ref
                    .read(userManagementNotifierProvider.notifier)
                    .changeOwnPassword(
                      currentPassword: currentPassC.text,
                      newPassword: newPassC.text,
                    );
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(tr('saved_successfully', ref))),
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  final key = AppErrorMapper.key(e);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(tr(key, ref))),
                  );
                }
              }
            },
            child: Text(tr('save', ref)),
          ),
        ],
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
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    decoration: InputDecoration(labelText: tr('role', ref)),
                    items: const [
                      DropdownMenuItem(value: 'admin', child: Text('Admin')),
                      DropdownMenuItem(value: 'seller', child: Text('Seller')),
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
                        DropdownMenuItem<String>(
                          value: null,
                          child: Text(tr('none', ref)),
                        ),
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
                          .showSnackBar(SnackBar(content: Text('$e')));
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
    final emailC = TextEditingController(text: user.email);
    String role = user.isAdmin ? 'admin' : 'seller';
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
                    controller: emailC,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      helperText: user.isSeller
                          ? 'Admin can change seller email'
                          : 'Auth email editing is seller-only',
                    ),
                    keyboardType: TextInputType.emailAddress,
                    enabled: user.isSeller,
                  ),
                  if (user.isSeller) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.email, size: 16),
                        label: Text(tr('send_reset_email', ref)),
                        onPressed: () async {
                          try {
                            await ref
                                .read(userManagementNotifierProvider.notifier)
                                .sendPasswordResetEmail(user.email);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                    content: Text(tr('reset_email_sent', ref))),
                              );
                            }
                          } catch (e) {
                            if (ctx.mounted) {
                              final key = AppErrorMapper.key(e);
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text(tr(key, ref))),
                              );
                            }
                          }
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    decoration: InputDecoration(labelText: tr('role', ref)),
                    items: const [
                      DropdownMenuItem(value: 'admin', child: Text('Admin')),
                      DropdownMenuItem(value: 'seller', child: Text('Seller')),
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
                        DropdownMenuItem<String>(
                          value: null,
                          child: Text(tr('none', ref)),
                        ),
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
                        SnackBar(
                            content: Text(tr('err_permission_denied', ref))),
                      );
                    }
                    return;
                  }
                  if (nameC.text.trim().isEmpty || emailC.text.trim().isEmpty) {
                    return;
                  }
                  try {
                    final notifier =
                        ref.read(userManagementNotifierProvider.notifier);
                    // Clear old route assignment if route changed
                    if (oldRouteId != null && oldRouteId != selectedRouteId) {
                      await notifier.clearRouteAssignment(oldRouteId);
                    }
                    await notifier.updateUser(user.id, {
                      'display_name': nameC.text.trim(),
                      if (user.isSeller)
                        'email': emailC.text.trim().toLowerCase(),
                      'role': role,
                      'assigned_route_id': selectedRouteId,
                      'assigned_route_name': selectedRouteName,
                    });
                    if (user.isSeller &&
                        emailC.text.trim().toLowerCase() != user.email) {
                      await notifier.adminUpdateSellerAuth(
                        targetUid: user.id,
                        newEmail: emailC.text.trim().toLowerCase(),
                      );
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  } catch (e) {
                    if (ctx.mounted) {
                      final key = AppErrorMapper.key(e);
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text(tr(key, ref))),
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
}

// ─── Appearance Card ──────────────────────────────────────────────────────────

class _AppearanceCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themePreferenceProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Appearance',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Auto follows your device setting.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto, size: 18),
                  label: Text('Auto'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode, size: 18),
                  label: Text('Light'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode, size: 18),
                  label: Text('Dark'),
                ),
              ],
              selected: {current},
              onSelectionChanged: (s) => ref
                  .read(themePreferenceProvider.notifier)
                  .setThemeMode(s.first),
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
      // 800×400 @ quality 75 typically yields 40–120 KB for a logo.
      maxWidth: 800,
      maxHeight: 400,
      imageQuality: 75,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();

    // Hard guard: reject if still above 300 KB after resize+compress
    const maxBytes = 300 * 1024;
    if (bytes.lengthInBytes > maxBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Image is ${_fmtBytes(bytes.lengthInBytes)} — too large after optimisation. '
            'Use a simpler image or reduce dimensions below 800×400 px.',
          ),
          duration: const Duration(seconds: 5),
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
      await ref
          .read(settingsNotifierProvider.notifier)
          .save({'logo_base64': encoded, 'logo_url': null});

      if (mounted) {
        setState(() {
          _pendingBytes = null;
          _pendingSizeLabel = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logo uploaded successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        final detail = e is FirebaseException ? ' [${e.plugin}/${e.code}]' : '';
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${tr(key, ref)}$detail'),
          duration: const Duration(seconds: 8),
        ));
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
      title: 'Remove Logo',
      message: 'Remove the company logo from all reports?',
    );
    if (confirmed != true) return;
    setState(() => _uploading = true);
    try {
      await ref.read(settingsNotifierProvider.notifier).deleteLogo();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logo removed')),
        );
      }
    } catch (e) {
      if (mounted) {
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr(key, ref))));
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
              'Company Logo',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'PDF reports · PNG/JPG · max 800×400 px · max 300 KB',
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
                'Preview · $_pendingSizeLabel',
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
                    ? 'Uploading… ${(_uploadProgress! * 100).round()}%'
                    : 'Uploading…',
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
                      label: const Text('Upload'),
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
                          ? 'Replace Logo'
                          : 'Upload Logo'),
                    ),
                    if (savedLogoBytes != null)
                      OutlinedButton.icon(
                        onPressed: _deleteLogo,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppBrand.errorColor,
                          side: const BorderSide(color: AppBrand.errorColor),
                        ),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Remove'),
                      ),
                  ],
                ),
          ],
        ),
      ),
    );
  }
}
