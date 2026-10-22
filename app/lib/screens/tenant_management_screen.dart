import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/l10n/app_locale.dart';
import '../core/models/tenant_model.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/snack_helper.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/tenant_provider.dart';
import '../providers/user_provider.dart';
import '../widgets/error_state.dart';

class TenantManagementScreen extends ConsumerStatefulWidget {
  const TenantManagementScreen({super.key});

  @override
  ConsumerState<TenantManagementScreen> createState() =>
      _TenantManagementScreenState();
}

class _TenantManagementScreenState
    extends ConsumerState<TenantManagementScreen> {
  final _nameController = TextEditingController();
  final _slugController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _ownerEmailController = TextEditingController();
  final _ownerPasswordController = TextEditingController();
  final _maxDevicesController = TextEditingController(text: '3');
  final _maxSessionsController = TextEditingController(text: '2');
  bool _requireDevicePairing = false;
  bool _allowAdminResetOnly = true;
  String? _selectedOwnerId;
  String? _pendingTenantId;
  String? _pendingOwnerId;
  bool _selectedWorkspaceForProvisioning = false;
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    _ownerNameController.dispose();
    _ownerEmailController.dispose();
    _ownerPasswordController.dispose();
    _maxDevicesController.dispose();
    _maxSessionsController.dispose();
    super.dispose();
  }

  void _showMappedError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(errorSnackBar(tr(AppErrorMapper.key(error), ref)));
  }

  Future<void> _createOrUpdateTenant({TenantModel? existing}) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(errorSnackBar(tr('workspace_name_required', ref)));
      return;
    }

    final ownerRequired = existing == null || existing.ownerUserId == null;
    final createOwnerAccount = ownerRequired && _selectedOwnerId == null;
    if (createOwnerAccount) {
      final ownerName = _ownerNameController.text.trim();
      final ownerEmail = _ownerEmailController.text.trim();
      if (ownerName.isEmpty || !ownerEmail.contains('@')) {
        ScaffoldMessenger.of(context).showSnackBar(
          errorSnackBar(tr('workspace_owner_details_required', ref)),
        );
        return;
      }
      if (_ownerPasswordController.text.trim().length < 8 &&
          _pendingOwnerId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          errorSnackBar(tr('workspace_owner_password_required', ref)),
        );
        return;
      }
    }

    setState(() => _isCreating = true);
    var saved = false;
    try {
      final maxDevicesAllowed =
          int.tryParse(_maxDevicesController.text.trim()) ?? 1;
      final maxActiveSessionsAllowed =
          int.tryParse(_maxSessionsController.text.trim()) ?? 1;
      final notifier = ref.read(tenantManagementNotifierProvider.notifier);
      final String tenantId;
      if (existing == null) {
        _pendingTenantId ??= await notifier.createTenant(
          name: name,
          slug: _slugController.text.trim(),
          requireDevicePairing: _requireDevicePairing,
          allowAdminResetOnly: _allowAdminResetOnly,
          maxDevicesAllowed: maxDevicesAllowed,
          maxActiveSessionsAllowed: maxActiveSessionsAllowed,
        );
        tenantId = _pendingTenantId!;
      } else {
        tenantId = existing.id;
        await notifier.updateTenant(
          tenantId,
          name: name,
          slug: _slugController.text.trim(),
          requireDevicePairing: _requireDevicePairing,
          allowAdminResetOnly: _allowAdminResetOnly,
          maxDevicesAllowed: maxDevicesAllowed,
          maxActiveSessionsAllowed: maxActiveSessionsAllowed,
          ownerUserId: _selectedOwnerId,
        );
      }

      if (createOwnerAccount) {
        if (!_selectedWorkspaceForProvisioning) {
          await ref
              .read(authNotifierProvider.notifier)
              .selectWorkspace(
                workspaceId: tenantId,
                reason: 'Initial workspace owner account setup',
              );
          _selectedWorkspaceForProvisioning = true;
        }
        _pendingOwnerId ??= await ref
            .read(userManagementNotifierProvider.notifier)
            .createUser(
              email: _ownerEmailController.text.trim(),
              password: _ownerPasswordController.text,
              displayName: _ownerNameController.text.trim(),
              role: 'tenant_admin',
              tenantId: tenantId,
            );
        await notifier.assignTenantOwner(tenantId, _pendingOwnerId!);
      }
      saved = true;
    } catch (error) {
      _showMappedError(error);
    } finally {
      if (_selectedWorkspaceForProvisioning) {
        _selectedWorkspaceForProvisioning = false;
        try {
          await ref.read(authNotifierProvider.notifier).endWorkspaceAccess();
        } catch (error) {
          saved = false;
          _showMappedError(error);
        }
      }
      if (mounted) setState(() => _isCreating = false);
    }
    if (saved && mounted) {
      _pendingTenantId = null;
      _pendingOwnerId = null;
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _changeWorkspaceAccess(TenantModel tenant) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('access_workspace', ref)),
        content: TextField(
          controller: reasonController,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          maxLength: 240,
          decoration: InputDecoration(
            labelText: tr('workspace_access_reason', ref),
            hintText: tr('workspace_access_reason_hint', ref),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr('cancel', ref)),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, reasonController.text.trim()),
            child: Text(tr('confirm', ref)),
          ),
        ],
      ),
    );
    reasonController.dispose();
    if (reason == null || !mounted) return;
    try {
      await ref
          .read(authNotifierProvider.notifier)
          .selectWorkspace(workspaceId: tenant.id, reason: reason);
    } catch (error) {
      _showMappedError(error);
    }
  }

  void _openCreateSheet({TenantModel? existing}) {
    if (existing != null) {
      _nameController.text = existing.name;
      _slugController.text = existing.slug;
      _maxDevicesController.text = existing.maxDevicesAllowed.toString();
      _maxSessionsController.text = existing.maxActiveSessionsAllowed
          .toString();
      _requireDevicePairing = existing.requireDevicePairing;
      _allowAdminResetOnly = existing.allowAdminResetOnly;
      _selectedOwnerId = existing.ownerUserId;
      _ownerNameController.clear();
      _ownerEmailController.clear();
      _ownerPasswordController.clear();
    } else {
      if (_pendingTenantId == null) {
        _nameController.clear();
        _slugController.clear();
        _ownerNameController.clear();
        _ownerEmailController.clear();
        _ownerPasswordController.clear();
        _maxDevicesController.text = '3';
        _maxSessionsController.text = '2';
        _requireDevicePairing = false;
        _allowAdminResetOnly = true;
        _selectedOwnerId = null;
        _pendingOwnerId = null;
      }
    }

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            existing == null
                ? tr('create_workspace', ref)
                : tr('edit_workspace', ref),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    key: const Key('workspace_name'),
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: tr('workspace_name', ref),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('workspace_slug'),
                    controller: _slugController,
                    decoration: InputDecoration(labelText: tr('slug', ref)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _maxDevicesController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: tr('max_devices_allowed', ref),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _maxSessionsController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: tr('max_active_sessions_allowed', ref),
                    ),
                  ),
                  const SizedBox(height: 12),
                  StatefulBuilder(
                    builder: (context, setPairingState) =>
                        SwitchListTile.adaptive(
                          value: _requireDevicePairing,
                          onChanged: (value) => setPairingState(
                            () => _requireDevicePairing = value,
                          ),
                          title: Text(tr('require_device_pairing', ref)),
                        ),
                  ),
                  StatefulBuilder(
                    builder: (context, setResetState) =>
                        SwitchListTile.adaptive(
                          value: _allowAdminResetOnly,
                          onChanged: (value) =>
                              setResetState(() => _allowAdminResetOnly = value),
                          title: Text(tr('admin_reset_only', ref)),
                        ),
                  ),
                  if (existing != null) ...[
                    const SizedBox(height: 12),
                    Consumer(
                      builder: (context, ownerRef, _) => ownerRef
                          .watch(tenantUsersProvider(existing.id))
                          .when(
                            data: (users) => DropdownButtonFormField<String>(
                              key: const Key('workspace_owner_selector'),
                              initialValue:
                                  users.any(
                                    (user) =>
                                        user.role == UserRole.tenantAdmin &&
                                        user.id == _selectedOwnerId,
                                  )
                                  ? _selectedOwnerId
                                  : null,
                              items: [
                                DropdownMenuItem<String>(
                                  value: null,
                                  child: Text(tr('no_owner', ownerRef)),
                                ),
                                ...users
                                    .where(
                                      (user) =>
                                          user.role == UserRole.tenantAdmin,
                                    )
                                    .map(
                                      (user) => DropdownMenuItem<String>(
                                        value: user.id,
                                        child: Text(
                                          user.displayName.trim().isEmpty
                                              ? user.email
                                              : user.displayName,
                                        ),
                                      ),
                                    ),
                              ],
                              onChanged: (value) =>
                                  setState(() => _selectedOwnerId = value),
                              decoration: InputDecoration(
                                labelText: tr('owner', ownerRef),
                              ),
                            ),
                            loading: () => const LinearProgressIndicator(),
                            error: (error, _) => mappedErrorState(
                              error: error,
                              ref: ownerRef,
                              onRetry: () => ownerRef.invalidate(
                                tenantUsersProvider(existing.id),
                              ),
                            ),
                          ),
                    ),
                  ],
                  if (existing == null ||
                      (existing.ownerUserId == null &&
                          _selectedOwnerId == null)) ...[
                    const SizedBox(height: 16),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        tr('workspace_owner_account', ref),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('workspace_owner_name'),
                      controller: _ownerNameController,
                      decoration: InputDecoration(
                        labelText: tr('display_name', ref),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('workspace_owner_email'),
                      controller: _ownerEmailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(labelText: tr('email', ref)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('workspace_owner_password'),
                      controller: _ownerPasswordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: tr('temp_password', ref),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(tr('cancel', ref)),
            ),
            FilledButton.icon(
              onPressed: _isCreating
                  ? null
                  : () => _createOrUpdateTenant(existing: existing),
              icon: const Icon(Icons.save_alt),
              label: Text(
                existing == null
                    ? (_pendingTenantId == null
                          ? tr('create_workspace', ref)
                          : tr('complete_workspace_setup', ref))
                    : tr('save_changes', ref),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tenantsAsync = ref.watch(tenantsProvider);
    final currentUser = ref.watch(authUserProvider).value;
    final canManageTenants =
        currentUser != null &&
        (currentUser.isSuperAdmin || currentUser.isTenantAdmin);
    final canCreateTenants = currentUser?.isSuperAdmin == true;

    bool canEditTenant(TenantModel tenant) {
      return currentUser?.isSuperAdmin == true &&
          currentUser?.activeWorkspaceId == tenant.id;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('workspaces', ref)),
        actions: [
          if (canCreateTenants)
            IconButton(
              onPressed: () => _openCreateSheet(),
              icon: const Icon(Icons.add_business),
            ),
        ],
      ),
      body: tenantsAsync.when(
        data: (tenants) {
          if (tenants.isEmpty) {
            if (!canManageTenants) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 56),
                    const SizedBox(height: 12),
                    Text(
                      tr('no_access_to_workspaces', ref),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              );
            }
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.apartment, size: 56),
                  const SizedBox(height: 12),
                  Text(
                    tr('no_workspaces_yet', ref),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: tenants.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final tenant = tenants[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              tenant.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (currentUser?.isTenantAdmin == true ||
                              (currentUser?.isSuperAdmin == true &&
                                  currentUser?.activeWorkspaceId == tenant.id))
                            IconButton(
                              tooltip: tr('security_devices_sessions', ref),
                              onPressed: () => context.push(
                                '/tenants/${tenant.id}/security',
                              ),
                              icon: const Icon(Icons.phonelink_lock_outlined),
                            ),
                          if (currentUser?.isTenantAdmin == true ||
                              (currentUser?.isSuperAdmin == true &&
                                  currentUser?.activeWorkspaceId == tenant.id))
                            IconButton(
                              tooltip: tr('paired_devices_title', ref),
                              onPressed: () =>
                                  context.push('/tenants/${tenant.id}/devices'),
                              icon: const Icon(Icons.devices_outlined),
                            ),
                          if (canEditTenant(tenant))
                            IconButton(
                              onPressed: () =>
                                  _openCreateSheet(existing: tenant),
                              icon: const Icon(Icons.edit),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('${tr('slug', ref)}: ${tenant.slug}'),
                      Text(
                        '${tr('require_device_pairing', ref)}: ${tenant.requireDevicePairing ? tr('yes', ref) : tr('no', ref)}',
                      ),
                      Text(
                        '${tr('admin_reset_only', ref)}: ${tenant.allowAdminResetOnly ? tr('yes', ref) : tr('no', ref)}',
                      ),
                      if (tenant.ownerUserId == null)
                        Text(
                          tr('workspace_owner_missing', ref),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      if (currentUser?.isSuperAdmin == true) ...[
                        const SizedBox(height: 12),
                        if (currentUser?.activeWorkspaceId == tenant.id &&
                            currentUser?.activeWorkspaceReason != null)
                          Text(
                            '${tr('workspace_access_active', ref)}: ${currentUser!.activeWorkspaceReason}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: TextButton.icon(
                            onPressed: () => _changeWorkspaceAccess(tenant),
                            icon: Icon(
                              currentUser?.activeWorkspaceId == tenant.id
                                  ? Icons.lock_open
                                  : Icons.admin_panel_settings_outlined,
                            ),
                            label: Text(
                              tr(
                                currentUser?.activeWorkspaceId == tenant.id
                                    ? 'end_workspace_access'
                                    : 'access_workspace',
                                ref,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => mappedErrorState(
          error: error,
          ref: ref,
          onRetry: () => ref.invalidate(tenantsProvider),
        ),
      ),
    );
  }
}
