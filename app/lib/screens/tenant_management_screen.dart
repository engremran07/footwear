import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/l10n/app_locale.dart';
import '../core/models/tenant_model.dart';
import '../core/utils/device_pairing.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/tenant_provider.dart';
import '../providers/user_provider.dart';

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
  bool _requireDevicePairing = false;
  bool _allowAdminResetOnly = true;
  String? _selectedOwnerId;
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    super.dispose();
  }

  Future<void> _createOrUpdateTenant({TenantModel? existing}) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('workspace_name_required', ref))),
      );
      return;
    }

    final notifier = ref.read(tenantManagementNotifierProvider.notifier);
    if (existing == null) {
      await notifier.createTenant(
        name: name,
        slug: _slugController.text.trim(),
        requireDevicePairing: _requireDevicePairing,
        allowAdminResetOnly: _allowAdminResetOnly,
        ownerUserId: _selectedOwnerId,
      );
    } else {
      await notifier.updateTenant(
        existing.id,
        name: name,
        slug: _slugController.text.trim(),
        requireDevicePairing: _requireDevicePairing,
        allowAdminResetOnly: _allowAdminResetOnly,
        ownerUserId: _selectedOwnerId,
      );
    }

    if (!mounted) return;
    setState(() => _isCreating = false);
    Navigator.of(context).pop();
  }

  Future<void> _resetDevicePairing(UserModel user) async {
    final authNotifier = ref.read(authNotifierProvider.notifier);
    try {
      await authNotifier.resetDevicePairing(user.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${tr('device_pairing_reset', ref)} ${user.displayName}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _toggleDevicePairing(UserModel user, bool enabled) async {
    final authNotifier = ref.read(authNotifierProvider.notifier);
    try {
      final devicePairingId = enabled
          ? DevicePairing.generate(user.devicePairingId, user.id)
          : null;
      await authNotifier.setDevicePairingState(
        user.id,
        enabled: enabled,
        pairingId: devicePairingId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? tr('device_pairing_enabled', ref)
                : tr('device_pairing_disabled', ref),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _openCreateSheet({TenantModel? existing}) {
    if (existing != null) {
      _nameController.text = existing.name;
      _slugController.text = existing.slug;
      _requireDevicePairing = existing.requireDevicePairing;
      _allowAdminResetOnly = existing.allowAdminResetOnly;
      _selectedOwnerId = existing.ownerUserId;
    } else {
      _nameController.clear();
      _slugController.clear();
      _requireDevicePairing = false;
      _allowAdminResetOnly = true;
      _selectedOwnerId = null;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final ownerUsersAsync = ref.watch(allUsersProvider);
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                existing == null
                    ? tr('create_workspace', ref)
                    : tr('edit_workspace', ref),
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: tr('workspace_name', ref),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _slugController,
                decoration: InputDecoration(labelText: tr('slug', ref)),
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                value: _requireDevicePairing,
                onChanged: (value) =>
                    setState(() => _requireDevicePairing = value),
                title: Text(tr('require_device_pairing', ref)),
              ),
              SwitchListTile.adaptive(
                value: _allowAdminResetOnly,
                onChanged: (value) =>
                    setState(() => _allowAdminResetOnly = value),
                title: Text(tr('admin_reset_only', ref)),
              ),
              const SizedBox(height: 12),
              ownerUsersAsync.when(
                data: (users) {
                  return DropdownButtonFormField<String>(
                    initialValue: _selectedOwnerId,
                    items: [
                      DropdownMenuItem<String>(
                        value: null,
                        child: Text(tr('no_owner', ref)),
                      ),
                      ...users.map(
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
                    decoration: InputDecoration(labelText: tr('owner', ref)),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _isCreating
                    ? null
                    : () async {
                        setState(() => _isCreating = true);
                        await _createOrUpdateTenant(existing: existing);
                      },
                icon: const Icon(Icons.save_alt),
                label: Text(
                  existing == null
                      ? tr('create_workspace', ref)
                      : tr('save_changes', ref),
                ),
              ),
            ],
          ),
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
      return currentUser?.isSuperAdmin == true ||
          (currentUser?.isTenantAdmin == true &&
              currentUser?.id == tenant.ownerUserId);
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
                      const SizedBox(height: 12),
                      Consumer(
                        builder: (context, ref, child) {
                          final usersAsync = ref.watch(
                            tenantUsersProvider(tenant.id),
                          );
                          return usersAsync.when(
                            data: (users) {
                              if (users.isEmpty) {
                                return Text(tr('no_members_yet', ref));
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tr('authorized_devices', ref),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 8),
                                  for (final user in users)
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        user.displayName.isEmpty
                                            ? user.email
                                            : user.displayName,
                                      ),
                                      subtitle: Text(
                                        user.devicePairingEnabled
                                            ? '${tr('paired', ref)}: ${user.devicePairingId ?? 'active'}'
                                            : tr('not_paired', ref),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Switch.adaptive(
                                            value: user.devicePairingEnabled,
                                            onChanged: (enabled) =>
                                                _toggleDevicePairing(
                                                  user,
                                                  enabled,
                                                ),
                                          ),
                                          IconButton(
                                            onPressed: () =>
                                                _resetDevicePairing(user),
                                            icon: const Icon(Icons.lock_reset),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              );
                            },
                            loading: () => const LinearProgressIndicator(),
                            error: (error, _) => Text(error.toString()),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text(error.toString())),
      ),
    );
  }
}
