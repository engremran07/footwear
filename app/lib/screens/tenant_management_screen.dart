import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/l10n/app_locale.dart';
import '../core/models/tenant_model.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/share_helper.dart';
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
  String? _selectedOwnerId;
  String? _pendingTenantId;
  String? _pendingOwnerId;
  bool _selectedWorkspaceForProvisioning = false;
  bool _isCreating = false;
  String? _lifecycleTenantId;
  String? _seatInitializationTenantId;

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    _ownerNameController.dispose();
    _ownerEmailController.dispose();
    _ownerPasswordController.dispose();
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
      final notifier = ref.read(tenantManagementNotifierProvider.notifier);
      final String tenantId;
      if (existing == null) {
        _pendingTenantId ??= await notifier.createTenant(
          name: name,
          slug: _slugController.text.trim(),
        );
        tenantId = _pendingTenantId!;
      } else {
        tenantId = existing.id;
        await notifier.updateTenant(
          tenantId,
          name: name,
          slug: _slugController.text.trim(),
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
      if (tenant.active && tenant.activeUserCount == null) {
        await _initializeWorkspaceSeats(tenant);
      }
    } catch (error) {
      _showMappedError(error);
    }
  }

  Future<void> _initializeWorkspaceSeats(TenantModel tenant) async {
    if (_seatInitializationTenantId != null || !tenant.active) return;
    setState(() => _seatInitializationTenantId = tenant.id);
    try {
      await ref
          .read(tenantManagementNotifierProvider.notifier)
          .initializeWorkspaceSeatCount(tenant.id);
      if (!mounted) return;
      ref.invalidate(tenantsProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(successSnackBar(tr('workspace_seats_initialized', ref)));
    } catch (error) {
      _showMappedError(error);
    } finally {
      if (mounted) setState(() => _seatInitializationTenantId = null);
    }
  }

  Future<void> _contactOwnerByEmail(String email) async {
    try {
      final opened = await launchUrl(
        Uri(scheme: 'mailto', path: email),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(errorSnackBar(tr('err_url_open', ref)));
      }
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(errorSnackBar(tr('err_url_open', ref)));
      }
    }
  }

  Future<void> _contactOwnerByWhatsApp(String phone) async {
    try {
      final opened = await openWhatsApp(
        phone: phone,
        message: tr('whatsapp_greeting', ref),
      );
      if (!opened && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(errorSnackBar(tr('err_whatsapp_unavailable', ref)));
      }
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(errorSnackBar(tr('err_whatsapp_unavailable', ref)));
      }
    }
  }

  Future<void> _changeTenantLifecycle(TenantModel tenant) async {
    final restoring = !tenant.active;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          tr(
            restoring
                ? 'restore_workspace_confirmation_title'
                : 'archive_workspace_confirmation_title',
            ref,
          ),
        ),
        content: Text(
          tr(
            restoring
                ? 'restore_workspace_confirmation_message'
                : 'archive_workspace_confirmation_message',
            ref,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('cancel', ref)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              tr(restoring ? 'restore_workspace' : 'archive_workspace', ref),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _lifecycleTenantId = tenant.id);
    try {
      final notifier = ref.read(tenantManagementNotifierProvider.notifier);
      if (restoring) {
        await notifier.restoreTenant(tenant.id);
      } else {
        await notifier.archiveTenant(tenant.id);
      }
      if (!mounted) return;
      ref.invalidate(tenantsProvider);
      ref.invalidate(tenantProvider(tenant.id));
      ScaffoldMessenger.of(context).showSnackBar(
        successSnackBar(
          tr(restoring ? 'workspace_restored' : 'workspace_archived', ref),
        ),
      );
    } catch (error) {
      _showMappedError(error);
    } finally {
      if (mounted) setState(() => _lifecycleTenantId = null);
    }
  }

  void _openCreateSheet({TenantModel? existing}) {
    if (existing != null) {
      _nameController.text = existing.name;
      _slugController.text = existing.slug;
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

  Widget _buildWorkspaceMemberSummary(TenantModel tenant) {
    return Consumer(
      builder: (context, memberRef, _) {
        final viewer = memberRef.watch(authUserProvider).value;
        final supportContextActive =
            viewer?.hasActiveWorkspaceSupportContextFor(tenant.id) ?? false;
        final assignedWorkspaceAdmin =
            viewer?.isTenantAdmin == true &&
            viewer!.active &&
            viewer.tenantId == tenant.id;
        if (!supportContextActive && !assignedWorkspaceAdmin) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(tr('workspace_support_context_expired', memberRef)),
          );
        }

        return memberRef
            .watch(tenantWorkspaceUsersProvider(tenant.id))
            .when(
              data: (users) {
                final activeMembers = users
                    .where((user) => user.active && !user.isSuperAdmin)
                    .toList();
                final inactiveCount = users
                    .where((user) => !user.active && !user.isSuperAdmin)
                    .length;
                final adminCount = activeMembers
                    .where(
                      (user) =>
                          user.role == UserRole.admin ||
                          user.role == UserRole.tenantAdmin,
                    )
                    .length;
                final sellerCount = activeMembers
                    .where((user) => user.role == UserRole.seller)
                    .length;
                final otherCount =
                    activeMembers.length - adminCount - sellerCount;
                UserModel? owner;
                for (final user in users) {
                  if (user.id == tenant.ownerUserId) {
                    owner = user;
                    break;
                  }
                }

                Widget metric(String label, int value) =>
                    Chip(label: Text('$label: $value'));

                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Card(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('workspace_member_summary', memberRef),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              metric(
                                tr('workspace_active_users', memberRef),
                                activeMembers.length,
                              ),
                              metric(
                                tr('workspace_inactive_users', memberRef),
                                inactiveCount,
                              ),
                              metric(
                                tr('workspace_admin_count', memberRef),
                                adminCount,
                              ),
                              metric(
                                tr('workspace_seller_count', memberRef),
                                sellerCount,
                              ),
                              if (otherCount > 0)
                                metric(
                                  tr('workspace_other_roles', memberRef),
                                  otherCount,
                                ),
                            ],
                          ),
                          if (tenant.activeUserCount != null &&
                              tenant.activeUserCount != activeMembers.length)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                tr('workspace_seat_count_mismatch', memberRef),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          const Divider(height: 24),
                          Text(
                            tr('workspace_owner_details', memberRef),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          if (owner == null)
                            Text(tr('workspace_owner_missing', memberRef))
                          else ...[
                            Text(
                              owner.displayName.trim().isNotEmpty
                                  ? owner.displayName
                                  : owner.email,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (owner.email.isNotEmpty)
                              Row(
                                children: [
                                  const Icon(Icons.email_outlined, size: 18),
                                  const SizedBox(width: 6),
                                  Expanded(child: Text(owner.email)),
                                  IconButton(
                                    tooltip: tr(
                                      'contact_owner_email',
                                      memberRef,
                                    ),
                                    onPressed: () =>
                                        _contactOwnerByEmail(owner!.email),
                                    icon: const Icon(Icons.mail_outline),
                                  ),
                                ],
                              ),
                            if (owner.phone?.trim().isNotEmpty == true)
                              Row(
                                children: [
                                  const Icon(Icons.phone_outlined, size: 18),
                                  const SizedBox(width: 6),
                                  Expanded(child: Text(owner.phone!)),
                                  if (isValidWhatsAppPhone(owner.phone!))
                                    IconButton(
                                      tooltip: tr(
                                        'contact_owner_whatsapp',
                                        memberRef,
                                      ),
                                      onPressed: () => _contactOwnerByWhatsApp(
                                        owner!.phone!,
                                      ),
                                      icon: const Icon(Icons.chat_outlined),
                                    ),
                                ],
                              )
                            else
                              Text(
                                tr('workspace_owner_phone_missing', memberRef),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            Wrap(
                              spacing: 8,
                              children: [
                                Chip(
                                  avatar: Icon(
                                    owner.emailVerified
                                        ? Icons.verified_outlined
                                        : Icons.info_outline,
                                    size: 16,
                                  ),
                                  label: Text(
                                    tr(
                                      owner.emailVerified
                                          ? 'workspace_owner_email_verified'
                                          : 'workspace_owner_email_unverified',
                                      memberRef,
                                    ),
                                  ),
                                ),
                                Chip(
                                  label: Text(
                                    tr(
                                      owner.active
                                          ? 'account_active'
                                          : 'workspace_owner_inactive',
                                      memberRef,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
              error: (error, _) => mappedErrorState(
                error: error,
                ref: memberRef,
                onRetry: () => memberRef.invalidate(
                  tenantWorkspaceUsersProvider(tenant.id),
                ),
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
      return currentUser?.hasActiveWorkspaceSupportContextFor(tenant.id) ==
          true;
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
              final hasWorkspaceSupportContext =
                  currentUser?.hasActiveWorkspaceSupportContextFor(tenant.id) ==
                  true;
              final isAssignedWorkspaceAdmin =
                  currentUser?.isTenantAdmin == true &&
                  currentUser!.active &&
                  currentUser.tenantId == tenant.id;
              final seatCount = tenant.activeUserCount;
              final seatLimit = tenant.maxActiveUsers;
              final remainingSeats = seatCount == null
                  ? null
                  : (seatLimit - seatCount).clamp(0, seatLimit);
              final planLabel =
                  tenant.plan == null || tenant.plan!.trim().isEmpty
                  ? tr('free_tier', ref)
                  : tenant.plan!.toLowerCase() == 'free'
                  ? tr('free_tier', ref)
                  : tenant.plan!;
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
                      const SizedBox(height: 8),
                      Chip(
                        label: Text(
                          tr(
                            tenant.active
                                ? 'workspace_status_active'
                                : 'workspace_status_archived',
                            ref,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Card(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLow,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.people_alt_outlined,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      tr('workspace_seats', ref),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleSmall,
                                    ),
                                  ),
                                  Chip(label: Text(planLabel)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    seatCount == null
                                        ? '— / $seatLimit'
                                        : '$seatCount / $seatLimit',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  if (remainingSeats != null)
                                    Text(
                                      '${tr('workspace_seats_remaining', ref)}: $remainingSeats',
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              LinearProgressIndicator(
                                value: seatCount == null
                                    ? null
                                    : seatLimit == 0
                                    ? 1
                                    : (seatCount / seatLimit).clamp(0, 1),
                                semanticsLabel: tr('workspace_seats', ref),
                              ),
                              if (seatCount == null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  tr('workspace_seat_count_pending', ref),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (hasWorkspaceSupportContext && tenant.active)
                                  Align(
                                    alignment: AlignmentDirectional.centerEnd,
                                    child: TextButton.icon(
                                      onPressed:
                                          _seatInitializationTenantId == null
                                          ? () => _initializeWorkspaceSeats(
                                              tenant,
                                            )
                                          : null,
                                      icon:
                                          _seatInitializationTenantId ==
                                              tenant.id
                                          ? const SizedBox.square(
                                              dimension: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.sync, size: 18),
                                      label: Text(
                                        tr('initialize_workspace_seats', ref),
                                      ),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
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
                        if (hasWorkspaceSupportContext &&
                            currentUser?.activeWorkspaceReason != null)
                          Text(
                            '${tr('workspace_access_active', ref)}: ${currentUser!.activeWorkspaceReason}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: () => _changeWorkspaceAccess(tenant),
                              icon: Icon(
                                hasWorkspaceSupportContext
                                    ? Icons.lock_open
                                    : Icons.admin_panel_settings_outlined,
                              ),
                              label: Text(
                                tr(
                                  hasWorkspaceSupportContext
                                      ? 'end_workspace_access'
                                      : 'access_workspace',
                                  ref,
                                ),
                              ),
                            ),
                            if (hasWorkspaceSupportContext)
                              OutlinedButton.icon(
                                onPressed: _lifecycleTenantId == null
                                    ? () => _changeTenantLifecycle(tenant)
                                    : null,
                                icon: _lifecycleTenantId == tenant.id
                                    ? const SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(
                                        tenant.active
                                            ? Icons.archive_outlined
                                            : Icons.unarchive_outlined,
                                      ),
                                label: Text(
                                  tr(
                                    tenant.active
                                        ? 'archive_workspace'
                                        : 'restore_workspace',
                                    ref,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                      if ((hasWorkspaceSupportContext ||
                              isAssignedWorkspaceAdmin) &&
                          tenant.active)
                        _buildWorkspaceMemberSummary(tenant),
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
