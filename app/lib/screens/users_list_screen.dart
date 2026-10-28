import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/constants/app_brand.dart';
import '../core/design/app_animations.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/permission_policy.dart';
import '../core/utils/role_names.dart';
import '../core/utils/role_utils.dart';
import '../core/utils/snack_helper.dart';
import '../core/utils/tenant_scope.dart';
import '../models/route_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/route_provider.dart';
import '../providers/tenant_provider.dart';
import '../providers/user_provider.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/app_search_bar.dart';
import '../widgets/app_pull_refresh.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/shimmer_loading.dart';

/// User management for authorized admin-equivalent and workspace-admin roles.
///
/// User queries and writes remain constrained by the active workspace and
/// role policy.
class UsersListScreen extends ConsumerStatefulWidget {
  const UsersListScreen({super.key});

  @override
  ConsumerState<UsersListScreen> createState() => _UsersListScreenState();
}

class _UsersListScreenState extends ConsumerState<UsersListScreen> {
  String _search = '';
  // Active/Inactive tab toggle
  bool _showInactive = false;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    if (authState.hasError) {
      return Scaffold(
        body: mappedErrorState(
          error: authState.error!,
          ref: ref,
          onRetry: () => ref.invalidate(authStateProvider),
        ),
      );
    }
    if (authState.isLoading) {
      return const Scaffold(body: ShimmerLoading());
    }

    final currentUserState = ref.watch(authUserProvider);
    if (currentUserState.hasError) {
      return Scaffold(
        body: mappedErrorState(
          error: currentUserState.error!,
          ref: ref,
          onRetry: () => ref.invalidate(authUserProvider),
        ),
      );
    }
    if (currentUserState.isLoading) {
      return const Scaffold(body: ShimmerLoading());
    }

    final currentUser = currentUserState.value;
    if (currentUser == null) {
      return Scaffold(body: Center(child: Text(tr('permission_denied', ref))));
    }

    final canViewUserAccounts = PermissionPolicy.hasRoleCapability(
      currentUser,
      AppCapability.manageUsers,
    );

    // Account management must be isolated from workspace management.
    if (!canViewUserAccounts) {
      return Scaffold(body: Center(child: Text(tr('permission_denied', ref))));
    }
    if (currentUser.isSuperAdmin && currentUser.activeWorkspaceId == null) {
      return Scaffold(
        body: EmptyState(
          icon: Icons.apartment_outlined,
          message: tr('select_workspace', ref),
          actionLabel: tr('workspaces', ref),
          onAction: () => context.go('/tenants'),
        ),
      );
    }

    final tenantId =
        TenantScope.normalize(currentUser.tenantId) ??
        TenantScope.noActiveWorkspaceId;

    // ── Users for selected workspace ────────────────────────────────────
    final usersAsync = _showInactive
        ? ref.watch(allInactiveUsersForTenantProvider(tenantId))
        : ref.watch(tenantUsersProvider(tenantId));

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateUserDialog(
          currentUser,
          tenantId,
          canCreateAdmin: PermissionPolicy.can(
            currentUser,
            AppCapability.manageUsers,
            targetRole: 'admin',
          ),
          canCreateSupervisor: PermissionPolicy.can(
            currentUser,
            AppCapability.createSupervisor,
          ),
        ),
        icon: const Icon(Icons.person_add),
        label: Text(tr('new_user', ref)),
        tooltip: tr('new_user', ref),
      ),
      body: Column(
        children: [
          const Divider(height: 1),
          // ── Search bar ──────────────────────────────────────────────────
          AppSearchBar(
            hintText: tr('search', ref),
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
          ),
          // ── Active / Inactive segmented tab ─────────────────────────────
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
          const Divider(height: 1),
          // ── Users list (workspace-scoped, no role tags) ──────────────────
          Expanded(
            child: usersAsync.when(
              loading: () => const ShimmerLoading(),
              error: (e, _) => mappedErrorState(
                error: e,
                ref: ref,
                onRetry: () {
                  if (_showInactive) {
                    ref.invalidate(allInactiveUsersForTenantProvider(tenantId));
                  } else {
                    ref.invalidate(tenantUsersProvider(tenantId));
                  }
                },
              ),
              data: (users) {
                final filtered = users.where((u) {
                  final matchesSearch =
                      _search.isEmpty ||
                      u.displayName.toLowerCase().contains(_search) ||
                      u.email.toLowerCase().contains(_search) ||
                      u.assignedRouteNames.any(
                        (n) => n.toLowerCase().contains(_search),
                      );
                  return matchesSearch;
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
                      final provider = allInactiveUsersForTenantProvider(
                        tenantId,
                      );
                      ref.invalidate(provider);
                      await ref.read(provider.future);
                    } else {
                      final provider = tenantUsersProvider(tenantId);
                      ref.invalidate(provider);
                      await ref.read(provider.future);
                    }
                  },
                  child: ListView.builder(
                    itemCount: filtered.length,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 88),
                    itemBuilder: (_, i) => _showInactive
                        ? _InactiveUserTile(
                            user: filtered[i],
                            onReactivate:
                                PermissionPolicy.can(
                                  currentUser,
                                  AppCapability.manageUsers,
                                  targetRole: roleValueFromUserRole(
                                    filtered[i].role,
                                  ),
                                )
                                ? () => _confirmReactivateUser(filtered[i])
                                : null,
                            onSendReset: () =>
                                _sendResetEmailForUser(filtered[i]),
                            onHardDelete:
                                PermissionPolicy.can(
                                  currentUser,
                                  AppCapability.manageDataMaintenance,
                                )
                                ? () => _confirmHardDeleteUser(filtered[i])
                                : null,
                          ).listEntry(i)
                        : _UserTile(
                            user: filtered[i],
                            currentUser: currentUser,
                            onEdit:
                                filtered[i].id != currentUser.id &&
                                    PermissionPolicy.can(
                                      currentUser,
                                      AppCapability.manageUsers,
                                      targetRole: roleValueFromUserRole(
                                        filtered[i].role,
                                      ),
                                    )
                                ? () =>
                                      _showEditUserDialog(filtered[i], tenantId)
                                : null,
                            onDelete:
                                filtered[i].id != currentUser.id &&
                                    PermissionPolicy.can(
                                      currentUser,
                                      AppCapability.manageUsers,
                                      targetRole: roleValueFromUserRole(
                                        filtered[i].role,
                                      ),
                                    )
                                ? () => _confirmDeleteUser(filtered[i])
                                : null,
                            onToggle: (v) => _toggleUserActive(filtered[i], v),
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

  Future<void> _toggleUserActive(UserModel user, bool active) async {
    try {
      final me = await ref.read(authUserProvider.future);
      if (!mounted) return;
      if (me == null ||
          !PermissionPolicy.can(
            me,
            AppCapability.manageUsers,
            targetRole: roleValueFromUserRole(user.role),
          )) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(errorSnackBar(tr('permission_denied', ref)));
        return;
      }
      if (!active) {
        final confirmed = await ConfirmDialog.show(
          context,
          title: tr('disable_user', ref),
          message: tr(
            'confirm_deactivate_user',
            ref,
          ).replaceAll('%s', user.displayName),
          isDestructive: true,
        );
        if (confirmed != true || !mounted) return;
      }
      await ref
          .read(userManagementNotifierProvider.notifier)
          .toggleActive(user.id, active);
    } catch (e) {
      if (!mounted) return;
      final key = AppErrorMapper.key(e);
      ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(tr(key, ref)));
    }
  }

  // ── Create user dialog ───────────────────────────────────────────────────

  void _showCreateUserDialog(
    UserModel currentUser,
    String tenantId, {
    required bool canCreateAdmin,
    required bool canCreateSupervisor,
  }) {
    final emailC = TextEditingController();
    final passC = TextEditingController();
    final nameC = TextEditingController();
    final phoneC = TextEditingController();
    String role = 'seller';
    String? createError;
    var isCreating = false;
    final selectedRouteIds = <String>[];
    final selectedRouteNames = <String>[];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          return AlertDialog(
            title: Text(tr('new_user', ref)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (createError != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          tr(createError!, ref),
                          key: const Key('user_create_error'),
                          style: TextStyle(
                            color: Theme.of(ctx).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    key: const Key('user_create_name'),
                    controller: nameC,
                    decoration: InputDecoration(labelText: tr('name', ref)),
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) {
                      if (createError != null) {
                        setS(() => createError = null);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('user_create_email'),
                    controller: emailC,
                    decoration: InputDecoration(labelText: tr('email', ref)),
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) {
                      if (createError != null) {
                        setS(() => createError = null);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: phoneC,
                    decoration: InputDecoration(
                      labelText: tr('phone_optional', ref),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('user_create_password'),
                    controller: passC,
                    decoration: InputDecoration(labelText: tr('password', ref)),
                    obscureText: true,
                    keyboardType: TextInputType.visiblePassword,
                    onChanged: (_) {
                      if (createError != null) {
                        setS(() => createError = null);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    decoration: InputDecoration(labelText: tr('role', ref)),
                    items: [
                      if (canCreateAdmin)
                        DropdownMenuItem(
                          value: 'admin',
                          child: Text(tr('lbl_admin', ref)),
                        ),
                      if (canCreateSupervisor)
                        DropdownMenuItem(
                          value: 'supervisor',
                          child: Text(tr('role_supervisor', ref)),
                        ),
                      DropdownMenuItem(
                        value: 'seller',
                        child: Text(tr('lbl_seller', ref)),
                      ),
                      if (PermissionPolicy.can(
                        currentUser,
                        AppCapability.manageUsers,
                        targetRole: 'tenant_admin',
                        tenantId: tenantId,
                      ))
                        DropdownMenuItem(
                          value: 'tenant_admin',
                          child: Text(tr('role_tenant_admin', ref)),
                        ),
                    ],
                    onChanged: (v) => setS(() {
                      role = v ?? 'seller';
                      if (role != 'seller') {
                        selectedRouteIds.clear();
                        selectedRouteNames.clear();
                      }
                    }),
                  ),
                  if (role == 'seller') ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        tr('assigned_routes', ref),
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _RouteAssignmentOptions(
                      selectedRouteIds: selectedRouteIds,
                      onSelectionChanged: (route, selected) => setS(
                        () => _updateRouteSelection(
                          selectedRouteIds,
                          selectedRouteNames,
                          route,
                          selected,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isCreating ? null : () => Navigator.pop(ctx),
                child: Text(tr('cancel', ref)),
              ),
              ElevatedButton(
                onPressed: isCreating
                    ? null
                    : () async {
                        if (nameC.text.trim().isEmpty ||
                            emailC.text.trim().isEmpty ||
                            passC.text.isEmpty) {
                          return;
                        }
                        if (passC.text.length < 8) {
                          setS(() => createError = 'err_weak_password');
                          return;
                        }
                        if (role == 'seller' &&
                            !_validateSellerRoutes(
                              ctx,
                              selectedRouteIds,
                              selectedRouteNames,
                              onError: (key) => setS(() => createError = key),
                            )) {
                          return;
                        }
                        setS(() {
                          isCreating = true;
                          createError = null;
                        });
                        try {
                          await ref
                              .read(userManagementNotifierProvider.notifier)
                              .createUser(
                                email: emailC.text.trim(),
                                password: passC.text,
                                displayName: nameC.text.trim(),
                                role: role,
                                phone: phoneC.text.trim(),
                                assignedRouteIds: selectedRouteIds,
                                assignedRouteNames: selectedRouteNames,
                                tenantId: tenantId,
                              );
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              successSnackBar(tr('saved_successfully', ref)),
                            );
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            setS(() => createError = AppErrorMapper.key(e));
                          }
                        } finally {
                          if (ctx.mounted) setS(() => isCreating = false);
                        }
                      },
                child: isCreating
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(tr('loading', ref)),
                        ],
                      )
                    : Text(tr('create', ref)),
              ),
            ],
          );
        },
      ),
    ).whenComplete(() {
      emailC.dispose();
      passC.dispose();
      nameC.dispose();
      phoneC.dispose();
    });
  }

  // ── Edit user dialog ─────────────────────────────────────────────────────

  Future<void> _showEditUserDialog(UserModel user, String tenantId) async {
    final currentUser = await ref.read(authUserProvider.future);
    if (!mounted || currentUser == null) return;
    final nameC = TextEditingController(text: user.displayName);
    final emailC = TextEditingController(text: user.email);
    final phoneC = TextEditingController(text: user.phone ?? '');
    String role = roleValueFromUserRole(user.role);
    final isSelf = currentUser.id == user.id;
    final canChangeRole =
        !isSelf &&
        PermissionPolicy.can(
          currentUser,
          AppCapability.manageUsers,
          targetRole: roleValueFromUserRole(user.role),
          tenantId: tenantId,
        );
    final selectedRouteIds = List<String>.from(user.assignedRouteIds);
    final selectedRouteNames = List<String>.from(user.assignedRouteNames);
    final oldRouteIds = List<String>.from(user.assignedRouteIds);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
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
                  TextField(
                    key: const Key('user_phone_field'),
                    controller: phoneC,
                    decoration: InputDecoration(
                      labelText: tr('phone', ref),
                      helperText: tr('contact_owner_whatsapp', ref),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 8),
                  // Account credentials are controlled by the account owner.
                  TextField(
                    controller: emailC,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: tr('email', ref),
                      helperText: tr('credentials_owner_managed', ref),
                      helperMaxLines: 2,
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _sendResetEmailForUser(user),
                    icon: const Icon(Icons.lock_reset),
                    label: Text(tr('send_password_reset', ref)),
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
                    ],
                  ),
                  const Divider(height: 16),
                  // ── Role ──
                  if (!canChangeRole)
                    TextField(
                      enabled: false,
                      decoration: InputDecoration(
                        labelText: tr('role', ref),
                        hintText: tr(roleLabelKeyFromRoleValue(role), ref),
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: InputDecoration(labelText: tr('role', ref)),
                      items: [
                        if (currentUser.isSuperAdmin)
                          DropdownMenuItem(
                            value: 'admin',
                            child: Text(tr('lbl_admin', ref)),
                          ),
                        DropdownMenuItem(
                          value: 'supervisor',
                          child: Text(tr('role_supervisor', ref)),
                        ),
                        DropdownMenuItem(
                          value: 'seller',
                          child: Text(tr('lbl_seller', ref)),
                        ),
                        if (currentUser.isSuperAdmin)
                          DropdownMenuItem(
                            value: 'tenant_admin',
                            child: Text(tr('role_tenant_admin', ref)),
                          ),
                      ],
                      onChanged: (v) => setS(() {
                        role = v ?? 'seller';
                        if (role != 'seller') {
                          selectedRouteIds.clear();
                          selectedRouteNames.clear();
                        }
                      }),
                    ),
                  if (role == 'seller' && (canChangeRole || user.isSeller)) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        tr('assigned_routes', ref),
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _RouteAssignmentOptions(
                      selectedRouteIds: selectedRouteIds,
                      onSelectionChanged: (route, selected) => setS(
                        () => _updateRouteSelection(
                          selectedRouteIds,
                          selectedRouteNames,
                          route,
                          selected,
                        ),
                      ),
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
                  final me = await ref.read(authUserProvider.future);
                  if (!mounted || !ctx.mounted) return;
                  if (!PermissionPolicy.can(
                    me,
                    AppCapability.manageUsers,
                    targetRole: role,
                    tenantId: tenantId,
                  )) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        errorSnackBar(tr('err_permission_denied', ref)),
                      );
                    }
                    return;
                  }
                  if (nameC.text.trim().isEmpty) return;
                  if (role == 'seller' &&
                      !_validateSellerRoutes(
                        ctx,
                        selectedRouteIds,
                        selectedRouteNames,
                      )) {
                    return;
                  }
                  try {
                    final notifier = ref.read(
                      userManagementNotifierProvider.notifier,
                    );
                    // Profile and authorization changes remain provider/rules guarded.
                    final profileUpdate = <String, dynamic>{
                      'display_name': nameC.text.trim(),
                      'phone': phoneC.text.trim(),
                    };
                    if (canChangeRole) {
                      profileUpdate['role'] = role;
                      profileUpdate['assigned_route_ids'] = role == 'seller'
                          ? selectedRouteIds
                          : <String>[];
                      profileUpdate['assigned_route_names'] = role == 'seller'
                          ? selectedRouteNames
                          : <String>[];
                    } else if (role == 'seller' && user.isSeller) {
                      profileUpdate['assigned_route_ids'] = selectedRouteIds;
                      profileUpdate['assigned_route_names'] =
                          selectedRouteNames;
                    }
                    await notifier.updateUser(
                      user.id,
                      profileUpdate,
                      previousRouteIds: oldRouteIds,
                    );
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
    ).whenComplete(() {
      nameC.dispose();
      emailC.dispose();
      phoneC.dispose();
    });
  }

  void _updateRouteSelection(
    List<String> routeIds,
    List<String> routeNames,
    RouteModel route,
    bool selected,
  ) {
    if (selected) {
      if (routeIds.contains(route.id)) return;
      routeIds.add(route.id);
      routeNames.add(route.name);
      return;
    }
    final index = routeIds.indexOf(route.id);
    if (index < 0) return;
    routeIds.removeAt(index);
    if (index < routeNames.length) routeNames.removeAt(index);
  }

  bool _validateSellerRoutes(
    BuildContext dialogContext,
    List<String> selectedRouteIds,
    List<String> selectedRouteNames, {
    void Function(String key)? onError,
  }) {
    final routeState = ref.read(routesProvider);
    if (routeState.hasError) {
      final key = AppErrorMapper.key(routeState.error!);
      if (onError != null) {
        onError(key);
      } else {
        ScaffoldMessenger.of(
          dialogContext,
        ).showSnackBar(errorSnackBar(tr(key, ref)));
      }
      return false;
    }
    if (routeState.isLoading || !routeState.hasValue) {
      if (onError != null) {
        onError('loading');
      } else {
        ScaffoldMessenger.of(
          dialogContext,
        ).showSnackBar(infoSnackBar(tr('loading', ref)));
      }
      return false;
    }
    if (selectedRouteIds.isEmpty) {
      if (onError != null) {
        onError('msg_seller_needs_route');
      } else {
        ScaffoldMessenger.of(
          dialogContext,
        ).showSnackBar(warningSnackBar(tr('msg_seller_needs_route', ref)));
      }
      return false;
    }

    final routeNamesById = {
      for (final route in routeState.value!) route.id: route.name,
    };
    if (selectedRouteIds.any(
      (routeId) => !routeNamesById.containsKey(routeId),
    )) {
      if (onError != null) {
        onError('route_unavailable');
      } else {
        ScaffoldMessenger.of(
          dialogContext,
        ).showSnackBar(warningSnackBar(tr('route_unavailable', ref)));
      }
      return false;
    }
    selectedRouteNames
      ..clear()
      ..addAll(selectedRouteIds.map((routeId) => routeNamesById[routeId]!));
    return true;
  }

  // ── Reactivate user dialog ────────────────────────────────────────────────

  Future<void> _confirmReactivateUser(UserModel user) async {
    if (user.assignedRouteIds.isNotEmpty) {
      final confirmed = await ConfirmDialog.show(
        context,
        title: tr('reactivate', ref),
        message: tr(
          'confirm_reactivate_user',
          ref,
        ).replaceAll('%s', user.displayName),
      );
      if (confirmed != true) return;
      try {
        await ref
            .read(userManagementNotifierProvider.notifier)
            .toggleActive(user.id, true);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(successSnackBar(tr('saved_successfully', ref)));
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(errorSnackBar(tr(AppErrorMapper.key(error), ref)));
        }
      }
      return;
    }

    final selectedRouteIds = <String>[];
    final selectedRouteNames = <String>[];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
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
                if (user.isSeller) ...[
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      tr('assigned_routes', ref),
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _RouteAssignmentOptions(
                    selectedRouteIds: selectedRouteIds,
                    onSelectionChanged: (route, selected) => setS(
                      () => _updateRouteSelection(
                        selectedRouteIds,
                        selectedRouteNames,
                        route,
                        selected,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('cancel', ref)),
              ),
              ElevatedButton(
                onPressed: () {
                  if (user.isSeller &&
                      !_validateSellerRoutes(
                        ctx,
                        selectedRouteIds,
                        selectedRouteNames,
                      )) {
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
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
            routeIds: selectedRouteIds,
            routeNames: selectedRouteNames,
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
    final me = await ref.read(authUserProvider.future);
    if (!mounted) return;
    if (!PermissionPolicy.can(
          me,
          AppCapability.manageDataMaintenance,
          tenantId: me?.tenantId,
        ) ||
        TenantScope.normalize(user.tenantId) !=
            TenantScope.normalize(me?.tenantId)) {
      return;
    }

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
    final me = await ref.read(authUserProvider.future);
    if (!mounted) return;
    if (!PermissionPolicy.can(
      me,
      AppCapability.manageUsers,
      targetRole: roleValueFromUserRole(user.role),
    )) {
      return;
    }
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
          .sendPasswordResetForSeller(userId: user.id);
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

class _RouteAssignmentOptions extends ConsumerWidget {
  final List<String> selectedRouteIds;
  final void Function(RouteModel route, bool selected) onSelectionChanged;

  const _RouteAssignmentOptions({
    required this.selectedRouteIds,
    required this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routesAsync = ref.watch(routesProvider);
    return routesAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => Row(
        children: [
          Expanded(
            child: Text(
              tr(AppErrorMapper.key(error), ref),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          TextButton.icon(
            onPressed: () => ref.invalidate(routesProvider),
            icon: const Icon(Icons.refresh),
            label: Text(tr('retry', ref)),
          ),
        ],
      ),
      data: (routes) => routes.isEmpty
          ? Text(tr('no_routes', ref))
          : Wrap(
              spacing: 8,
              runSpacing: 4,
              children: routes
                  .map(
                    (route) => FilterChip(
                      label: Text(route.name),
                      selected: selectedRouteIds.contains(route.id),
                      onSelected: (selected) =>
                          onSelectionChanged(route, selected),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

// ─── (Unused role chip removed in v3.10 workspace-first UX) ────────────────────

// ─── User tile ────────────────────────────────────────────────────────────────

class _UserTile extends ConsumerWidget {
  final UserModel user;
  final UserModel? currentUser;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
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
    final canManageTarget = PermissionPolicy.can(
      currentUser,
      AppCapability.manageUsers,
      targetRole: roleValueFromUserRole(user.role),
    );
    final roleColor = user.isAdmin || user.isSupervisor
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
                    user.isAdmin || user.isSupervisor
                        ? Icons.admin_panel_settings
                        : Icons.person,
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
                    tr(
                      roleLabelKeyFromRoleValue(
                        roleValueFromUserRole(user.role),
                      ),
                      ref,
                    ),
                    style: TextStyle(
                      fontSize: 10,
                      color: roleColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (user.isSeller && user.assignedRouteNames.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '• ${user.assignedRouteNames.join(', ')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
                const Spacer(),
                // Edit
                if (canManageTarget && onEdit != null)
                  Tooltip(
                    message: tr('edit', ref),
                    child: IconButton(
                      icon: const Icon(Icons.edit, size: 18),
                      onPressed: onEdit,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                // Delete (only sellers, not self)
                if (!isSelf && canManageTarget && onDelete != null)
                  Tooltip(
                    message: tr('delete', ref),
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
                if (!isSelf && canManageTarget && !user.isSupervisor)
                  SizedBox(
                    width: 44,
                    height: 28,
                    child: FittedBox(
                      child: Switch(value: user.active, onChanged: onToggle),
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

class _InactiveUserTile extends ConsumerWidget {
  final UserModel user;
  final VoidCallback? onReactivate;
  final VoidCallback? onSendReset;
  final VoidCallback? onHardDelete;

  const _InactiveUserTile({
    required this.user,
    required this.onReactivate,
    required this.onSendReset,
    required this.onHardDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roleColor = user.isAdmin || user.isSupervisor
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
                user.isAdmin || user.isSupervisor
                    ? Icons.admin_panel_settings
                    : Icons.person_off,
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
                      tr(
                        roleLabelKeyFromRoleValue(
                          roleValueFromUserRole(user.role),
                        ),
                        ref,
                      ),
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
            if (onReactivate != null)
              Tooltip(
                message: tr('reactivate', ref),
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
            if (user.isSeller && onSendReset != null)
              Tooltip(
                message: tr('send_password_reset', ref),
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
            if (onHardDelete != null)
              Tooltip(
                message: tr('hard_delete_user', ref),
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
