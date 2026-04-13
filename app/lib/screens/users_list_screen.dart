import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_brand.dart';
import '../core/design/app_animations.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/snack_helper.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/route_provider.dart';
import '../providers/user_provider.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/app_search_bar.dart';
import '../widgets/app_pull_refresh.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/shimmer_loading.dart';

/// Dedicated admin-only user management screen (/users).
///
/// Shows all users with search, role filter, and full CRUD actions.
class UsersListScreen extends ConsumerStatefulWidget {
  const UsersListScreen({super.key});

  @override
  ConsumerState<UsersListScreen> createState() => _UsersListScreenState();
}

class _UsersListScreenState extends ConsumerState<UsersListScreen> {
  String _search = '';
  // null means 'all'
  String? _roleFilter;
  // Active/Inactive tab toggle
  bool _showInactive = false;

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authUserProvider).value;

    // Admin guard: render access-denied if not admin
    if (currentUser != null && !currentUser.isAdmin) {
      return Scaffold(body: Center(child: Text(tr('permission_denied', ref))));
    }

    final usersAsync = _showInactive
        ? ref.watch(inactiveUsersProvider)
        : ref.watch(allUsersProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateUserDialog(),
        icon: const Icon(Icons.person_add),
        label: Text(tr('new_user', ref)),
        tooltip: tr('new_user', ref),
      ),
      body: Column(
        children: [
          AppSearchBar(
            hintText: tr('search', ref),
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
          ),
          // Active / Inactive segmented tab
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 12,
              vertical: 4,
            ),
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(tr('tab_active_users', ref)),
                ),
                ButtonSegment(
                  value: true,
                  label: Text(tr('tab_inactive_users', ref)),
                ),
              ],
              selected: {_showInactive},
              onSelectionChanged: (s) =>
                  setState(() => _showInactive = s.first),
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
          ),
          // Role filter chips (active tab only)
          if (!_showInactive)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  _RoleChip(
                    label: tr('all', ref),
                    selected: _roleFilter == null,
                    onTap: () => setState(() => _roleFilter = null),
                  ),
                  const SizedBox(width: 8),
                  _RoleChip(
                    label: tr('lbl_admin', ref),
                    selected: _roleFilter == 'admin',
                    color: AppBrand.adminRoleColor,
                    onTap: () => setState(
                      () =>
                          _roleFilter = _roleFilter == 'admin' ? null : 'admin',
                    ),
                  ),
                  const SizedBox(width: 8),
                  _RoleChip(
                    label: tr('lbl_seller', ref),
                    selected: _roleFilter == 'seller',
                    color: AppBrand.sellerRoleColor,
                    onTap: () => setState(
                      () => _roleFilter = _roleFilter == 'seller'
                          ? null
                          : 'seller',
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: usersAsync.when(
              loading: () => const ShimmerLoading(),
              error: (e, _) => mappedErrorState(
                error: e,
                ref: ref,
                onRetry: () {
                  if (_showInactive) {
                    ref.invalidate(inactiveUsersProvider);
                  } else {
                    ref.invalidate(allUsersProvider);
                  }
                },
              ),
              data: (users) {
                final filtered = users.where((u) {
                  final matchesSearch =
                      _search.isEmpty ||
                      u.displayName.toLowerCase().contains(_search) ||
                      u.email.toLowerCase().contains(_search) ||
                      (u.assignedRouteName?.toLowerCase().contains(_search) ??
                          false);
                  final matchesRole =
                      _roleFilter == null ||
                      (_roleFilter == 'admin' ? u.isAdmin : u.isSeller);
                  return matchesSearch && matchesRole;
                }).toList();

                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.group_off,
                    message: tr('no_users', ref),
                  );
                }

                return AppPullRefresh(
                  onRefresh: () async {
                    if (_showInactive) {
                      ref.invalidate(inactiveUsersProvider);
                    } else {
                      ref.invalidate(allUsersProvider);
                    }
                    await Future.delayed(const Duration(milliseconds: 300));
                  },
                  child: ListView.builder(
                    itemCount: filtered.length,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 88),
                    itemBuilder: (_, i) => _showInactive
                        ? _InactiveUserTile(
                            user: filtered[i],
                            onReactivate: () =>
                                _confirmReactivateUser(filtered[i]),
                            onSendReset: () =>
                                _sendResetEmailForUser(filtered[i]),
                            onHardDelete: () =>
                                _confirmHardDeleteUser(filtered[i]),
                          ).listEntry(i)
                        : _UserTile(
                            user: filtered[i],
                            currentUser: currentUser,
                            onEdit: () => _showEditUserDialog(filtered[i]),
                            onDelete: () => _confirmDeleteUser(filtered[i]),
                            onToggle: (v) => ref
                                .read(userManagementNotifierProvider.notifier)
                                .toggleActive(filtered[i].id, v),
                          ).listEntry(i),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Create user dialog ───────────────────────────────────────────────────

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
          final routes = ref.watch(routesProvider).value ?? [];
          final availableRoutes = routes
              .where(
                (r) =>
                    r.assignedSellerId == null || r.assignedSellerId!.isEmpty,
              )
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
                    textCapitalization: TextCapitalization.words,
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
                        value: 'admin',
                        child: Text(tr('lbl_admin', ref)),
                      ),
                      DropdownMenuItem(
                        value: 'seller',
                        child: Text(tr('lbl_seller', ref)),
                      ),
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
                      items: availableRoutes
                          .map(
                            (r) => DropdownMenuItem(
                              value: r.id,
                              child: Text(r.name),
                            ),
                          )
                          .toList(),
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
                  if (passC.text.trim().length < 8) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        warningSnackBar(tr('err_weak_password', ref)),
                      );
                    }
                    return;
                  }
                  if (role == 'seller' &&
                      (selectedRouteId == null ||
                          selectedRouteId!.trim().isEmpty)) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: Text(tr('msg_seller_needs_route', ref)),
                        ),
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
                child: Text(tr('create', ref)),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Edit user dialog ─────────────────────────────────────────────────────

  void _showEditUserDialog(UserModel user) {
    final nameC = TextEditingController(text: user.displayName);
    final emailC = TextEditingController(text: user.email);
    final passwordC = TextEditingController();
    String role = user.isAdmin ? 'admin' : 'seller';
    final currentUser = ref.read(authUserProvider).value;
    final isSelf = currentUser?.id == user.id;
    String? selectedRouteId = user.assignedRouteId;
    String? selectedRouteName = user.assignedRouteName;
    final oldRouteId = user.assignedRouteId;
    bool obscurePassword = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final routes = ref.watch(routesProvider).value ?? [];
          final availableRoutes = routes
              .where(
                (r) =>
                    r.id == selectedRouteId ||
                    r.assignedSellerId == null ||
                    r.assignedSellerId!.isEmpty ||
                    r.assignedSellerId == user.id,
              )
              .toList();
          return AlertDialog(
            title: Text(tr('edit_user', ref)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Name ──
                  TextField(
                    controller: nameC,
                    decoration: InputDecoration(labelText: tr('name', ref)),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 8),
                  // ── Email (admin-editable, syncs Auth + Firestore) ──
                  TextField(
                    controller: emailC,
                    enabled: !isSelf,
                    decoration: InputDecoration(
                      labelText: tr('email', ref),
                      helperText: isSelf
                          ? tr('lbl_email_no_change', ref)
                          : tr('lbl_email_change_note', ref),
                      helperMaxLines: 2,
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 8),
                  // ── Set Password (optional — blank = no change) ──
                  TextField(
                    controller: passwordC,
                    obscureText: obscurePassword,
                    decoration: InputDecoration(
                      labelText: tr('lbl_set_password', ref),
                      hintText: tr('hint_set_password', ref),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          size: 20,
                        ),
                        onPressed: () =>
                            setS(() => obscurePassword = !obscurePassword),
                        tooltip: obscurePassword ? 'Show' : 'Hide',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // ── Email Verified badge + Send Verification button ──
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(
                        avatar: Icon(
                          user.emailVerified
                              ? Icons.verified
                              : Icons.warning_amber_rounded,
                          size: 16,
                          color: user.emailVerified
                              ? AppBrand.successColor
                              : AppBrand.warningColor,
                        ),
                        label: Text(
                          tr(
                            user.emailVerified
                                ? 'lbl_email_verified'
                                : 'lbl_email_not_verified',
                            ref,
                          ),
                          style: const TextStyle(fontSize: 11),
                        ),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        side: BorderSide.none,
                      ),
                      if (!user.emailVerified)
                        TextButton.icon(
                          icon: const Icon(Icons.forward_to_inbox, size: 14),
                          label: Text(
                            tr('btn_send_verification', ref),
                            style: const TextStyle(fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () async {
                            try {
                              final targetEmail = emailC.text.trim().isNotEmpty
                                  ? emailC.text.trim()
                                  : user.email;
                              await ref
                                  .read(userManagementNotifierProvider.notifier)
                                  .adminSendVerificationEmail(
                                    user.id,
                                    targetEmail,
                                  );
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  successSnackBar(
                                    tr(
                                      'msg_verification_sent',
                                      ref,
                                    ).replaceAll('%s', targetEmail),
                                  ),
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
                        ),
                    ],
                  ),
                  const Divider(height: 16),
                  // ── Role ──
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
                          value: 'admin',
                          child: Text(tr('lbl_admin', ref)),
                        ),
                        DropdownMenuItem(
                          value: 'seller',
                          child: Text(tr('lbl_seller', ref)),
                        ),
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
                      items: availableRoutes
                          .map(
                            (r) => DropdownMenuItem(
                              value: r.id,
                              child: Text(r.name),
                            ),
                          )
                          .toList(),
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
                  final me = ref.read(authUserProvider).value;
                  if (me?.isAdmin != true) {
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
                    final notifier = ref.read(
                      userManagementNotifierProvider.notifier,
                    );
                    // ── Step 1: Auth sync via 4-way pipeline ──────────────
                    final emailChanged =
                        !isSelf &&
                        emailC.text.trim().toLowerCase() !=
                            user.email.trim().toLowerCase() &&
                        emailC.text.trim().isNotEmpty;
                    final passwordSet = passwordC.text.trim().isNotEmpty;
                    if (passwordSet && passwordC.text.trim().length < 8) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          warningSnackBar(tr('err_weak_password', ref)),
                        );
                      }
                      return;
                    }
                    if (emailChanged || passwordSet) {
                      await notifier.adminUpdateUserAuth(
                        uid: user.id,
                        newEmail: emailChanged ? emailC.text.trim() : null,
                        newPassword: passwordSet ? passwordC.text.trim() : null,
                      );
                    }
                    // ── Step 2: Firestore profile (name / role / route) ───
                    await notifier.updateUser(user.id, {
                      'display_name': nameC.text.trim(),
                      'role': isSelf ? 'admin' : role,
                      'assigned_route_id': selectedRouteId,
                      'assigned_route_name': selectedRouteName,
                    }, previousRouteId: oldRouteId);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        successSnackBar(tr('msg_auth_updated', ref)),
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
          );
        },
      ),
    );
  }

  // ── Reactivate user dialog ────────────────────────────────────────────────

  Future<void> _confirmReactivateUser(UserModel user) async {
    final routes = ref.read(routesProvider).value ?? [];
    String? selectedRouteId;
    String? selectedRouteName;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final freeRoutes = routes
              .where(
                (r) =>
                    r.assignedSellerId == null || r.assignedSellerId!.isEmpty,
              )
              .toList();
          return AlertDialog(
            title: Text(tr('reactivate', ref)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr(
                    'confirm_reactivate_user',
                    ref,
                  ).replaceAll('%s', user.displayName),
                ),
                const SizedBox(height: 12),
                if (user.isSeller)
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: tr('assigned_route', ref),
                    ),
                    items: freeRoutes
                        .map(
                          (r) => DropdownMenuItem(
                            value: r.id,
                            child: Text(r.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setS(() {
                      selectedRouteId = v;
                      selectedRouteName = routes
                          .where((r) => r.id == v)
                          .map((r) => r.name)
                          .firstOrNull;
                    }),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('cancel', ref)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('reactivate', ref)),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(userManagementNotifierProvider.notifier)
          .reactivateUser(
            uid: user.id,
            routeId: selectedRouteId ?? '',
            routeName: selectedRouteName ?? '',
            displayName: user.displayName,
          );
      if (mounted) {
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

  // ── Hard-delete user confirmation ─────────────────────────────────────────

  Future<void> _confirmHardDeleteUser(UserModel user) async {
    final me = ref.read(authUserProvider).value;
    if (me?.isAdmin != true) return;

    final confirmed = await ConfirmDialog.show(
      context,
      title: tr('hard_delete_user', ref),
      message: tr(
        'confirm_hard_delete_user',
        ref,
      ).replaceAll('%s', user.displayName),
      isDestructive: true,
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(userManagementNotifierProvider.notifier)
          .hardDeleteUser(user.id, me!.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          successSnackBar(
            tr('msg_user_hard_deleted', ref).replaceAll('%s', user.displayName),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(tr(key, ref)));
      }
    }
  }

  // ── Delete user confirmation ──────────────────────────────────────────────

  Future<void> _confirmDeleteUser(UserModel user) async {
    final me = ref.read(authUserProvider).value;
    if (me?.isAdmin != true) return;
    // Cannot delete self or other admins
    if (user.id == me?.id || user.isAdmin) return;

    final confirmed = await ConfirmDialog.show(
      context,
      title: tr('delete', ref),
      message: tr(
        'confirm_delete_user',
        ref,
      ).replaceAll('%s', user.displayName),
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(userManagementNotifierProvider.notifier)
          .deleteUser(user.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          successSnackBar(
            tr('msg_user_deleted', ref).replaceAll('%s', user.displayName),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(tr(key, ref)));
      }
    }
  }

  Future<void> _sendResetEmailForUser(UserModel user) async {
    try {
      await ref
          .read(userManagementNotifierProvider.notifier)
          .sendPasswordResetForSeller(email: user.email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          successSnackBar(
            tr('msg_reset_email_sent', ref).replaceAll('%s', user.email),
          ),
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

// ─── Role filter chip ─────────────────────────────────────────────────────────

class _RoleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;

  const _RoleChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? Theme.of(context).colorScheme.primary;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: chipColor.withAlpha(40),
      checkmarkColor: chipColor,
      labelStyle: TextStyle(
        color: selected ? chipColor : null,
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }
}

// ─── User tile ────────────────────────────────────────────────────────────────

class _UserTile extends ConsumerWidget {
  final UserModel user;
  final UserModel? currentUser;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;

  const _UserTile({
    required this.user,
    required this.currentUser,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSelf = user.id == currentUser?.id;
    final roleColor = user.isAdmin
        ? AppBrand.adminRoleColor
        : AppBrand.sellerRoleColor;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: roleColor.withAlpha(30),
                  child: Icon(
                    user.isAdmin ? Icons.admin_panel_settings : Icons.person,
                    size: 18,
                    color: roleColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              user.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (!user.active)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppBrand.errorBg,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                tr('inactive', ref),
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: AppBrand.errorFg,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      Text(
                        user.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                // Role chip
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: roleColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    user.role.name,
                    style: TextStyle(
                      fontSize: 10,
                      color: roleColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (user.isSeller && user.assignedRouteName != null) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '• ${user.assignedRouteName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
                const Spacer(),
                // Edit
                Tooltip(
                  message: 'Edit',
                  child: IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    onPressed: onEdit,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                ),
                // Delete (only sellers, not self)
                if (!isSelf && !user.isAdmin)
                  Tooltip(
                    message: 'Delete',
                    child: IconButton(
                      icon: const Icon(
                        Icons.delete,
                        size: 18,
                        color: AppBrand.errorColor,
                      ),
                      onPressed: onDelete,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                // Active toggle (not self)
                SizedBox(
                  width: 44,
                  height: 28,
                  child: FittedBox(
                    child: Switch(
                      value: user.active,
                      onChanged: isSelf ? null : onToggle,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Inactive user tile ────────────────────────────────────────────────────────────────────

class _InactiveUserTile extends StatelessWidget {
  final UserModel user;
  final VoidCallback onReactivate;
  final VoidCallback onSendReset;
  final VoidCallback onHardDelete;

  const _InactiveUserTile({
    required this.user,
    required this.onReactivate,
    required this.onSendReset,
    required this.onHardDelete,
  });

  @override
  Widget build(BuildContext context) {
    final roleColor = user.isAdmin
        ? AppBrand.adminRoleColor
        : AppBrand.sellerRoleColor;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.16),
              child: Icon(
                user.isAdmin ? Icons.admin_panel_settings : Icons.person_off,
                size: 18,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withAlpha(140),
                    ),
                  ),
                  Text(
                    user.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withAlpha(100),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsetsDirectional.only(top: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: roleColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      user.role.name,
                      style: TextStyle(
                        fontSize: 10,
                        color: roleColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Reactivate
            Tooltip(
              message: 'Reactivate',
              child: IconButton(
                icon: const Icon(
                  Icons.person_add_alt_1,
                  size: 20,
                  color: AppBrand.successColor,
                ),
                onPressed: onReactivate,
                visualDensity: VisualDensity.compact,
              ),
            ),
            // Hard delete
            Tooltip(
              message: 'Send Reset Email',
              child: IconButton(
                icon: const Icon(
                  Icons.lock_reset,
                  size: 20,
                  color: AppBrand.primaryColor,
                ),
                onPressed: onSendReset,
                visualDensity: VisualDensity.compact,
              ),
            ),
            Tooltip(
              message: 'Permanently Delete',
              child: IconButton(
                icon: const Icon(
                  Icons.delete_forever,
                  size: 20,
                  color: AppBrand.errorColor,
                ),
                onPressed: onHardDelete,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
