import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/l10n/app_locale.dart';
import '../core/models/access_usage_summary.dart';
import '../core/models/tenant_model.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/snack_helper.dart';
import '../models/device_registration_model.dart';
import '../models/session_model.dart';
import '../providers/auth_provider.dart';
import '../providers/tenant_provider.dart';
import '../models/user_model.dart';
import '../widgets/error_state.dart';

class DeviceSessionSecurityScreen extends ConsumerWidget {
  final String? tenantId;

  const DeviceSessionSecurityScreen({super.key, this.tenantId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('access_security_title', ref))),
      body: tenantId == null
          ? _buildUserView(context, ref)
          : _buildAdminView(context, ref, tenantId!),
    );
  }

  Widget _buildUserView(BuildContext context, WidgetRef ref) {
    final userState = ref.watch(authUserProvider);
    return userState.when(
      data: (user) {
        if (user == null || user.tenantId == null) {
          return Center(child: Text(tr('access_workspace_unavailable', ref)));
        }
        final tenantState = ref.watch(tenantProvider(user.tenantId!));
        final devicesState = ref.watch(deviceRegistrationsProvider(user.id));
        final sessionsState = ref.watch(userSessionsProvider(user.id));
        final installationState = ref.watch(currentDeviceInstallationProvider);

        return tenantState.when(
          data: (tenant) {
            if (tenant == null) {
              return Center(
                child: Text(tr('access_workspace_unavailable', ref)),
              );
            }
            return devicesState.when(
              data: (devices) => sessionsState.when(
                data: (sessions) => _buildOwnUsage(
                  context,
                  ref,
                  user,
                  tenant,
                  devices,
                  sessions,
                  installationState.value?.installationId,
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => mappedErrorState(
                  error: error,
                  ref: ref,
                  onRetry: () => ref.invalidate(userSessionsProvider(user.id)),
                ),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => mappedErrorState(
                error: error,
                ref: ref,
                onRetry: () =>
                    ref.invalidate(deviceRegistrationsProvider(user.id)),
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => mappedErrorState(
            error: error,
            ref: ref,
            onRetry: () => ref.invalidate(tenantProvider(user.tenantId!)),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => mappedErrorState(error: error, ref: ref),
    );
  }

  Widget _buildOwnUsage(
    BuildContext context,
    WidgetRef ref,
    UserModel user,
    TenantModel tenant,
    List<DeviceRegistrationModel> devices,
    List<SessionModel> sessions,
    String? installationId,
  ) {
    final now = DateTime.now();
    final registeredDevices = devices
        .where((device) => device.status == 'active')
        .length;
    final activeSessions = sessions
        .where((session) => session.status == 'active')
        .where((session) => session.expiresAt?.toDate().isAfter(now) ?? false)
        .length;
    final summary = AccessUsageSummary(
      maxDevicesAllowed: tenant.maxDevicesAllowed,
      registeredDevices: registeredDevices,
      maxActiveSessionsAllowed: tenant.maxActiveSessionsAllowed,
      activeSessions: activeSessions,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _CapacitySection(
          title: tr('access_devices', ref),
          icon: Icons.devices_outlined,
          allowedLabel: tr('access_allowed', ref),
          usedLabel: tr('access_registered', ref),
          availableLabel: tr('access_available', ref),
          allowed: summary.maxDevicesAllowed,
          used: summary.registeredDevices,
          available: summary.availableDeviceSlots,
          overLimit: summary.overLimitDeviceCount,
          ref: ref,
        ),
        const SizedBox(height: 12),
        _CapacitySection(
          title: tr('access_active_sessions', ref),
          icon: Icons.phonelink_lock_outlined,
          allowedLabel: tr('access_allowed', ref),
          usedLabel: tr('access_active', ref),
          availableLabel: tr('access_available', ref),
          allowed: summary.maxActiveSessionsAllowed,
          used: summary.activeSessions,
          available: summary.availableSessionSlots,
          overLimit: summary.overLimitSessionCount,
          ref: ref,
        ),
        if (summary.overLimitDeviceCount > 0 ||
            summary.overLimitSessionCount > 0) ...[
          const SizedBox(height: 8),
          Text(
            tr('access_policy_reduced_notice', ref),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        Text(
          tr('access_devices', ref),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (devices.isEmpty)
          Text(tr('access_no_devices', ref))
        else
          for (final device in devices)
            _DeviceCard(
              device: device,
              isCurrent: device.deviceId == installationId,
              activeSessionCount: sessions
                  .where(
                    (session) =>
                        session.deviceId == device.deviceId &&
                        session.status == 'active' &&
                        (session.expiresAt?.toDate().isAfter(now) ?? false),
                  )
                  .length,
              onRevoke: () => _revokeDevice(
                context,
                ref,
                device,
                userName: user.displayName,
                relatedSessionCount: sessions
                    .where((session) => session.deviceId == device.deviceId)
                    .length,
              ),
              ref: ref,
            ),
        const SizedBox(height: 20),
        Text(
          tr('access_active_sessions', ref),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (sessions.isEmpty)
          Text(tr('access_no_sessions', ref))
        else
          for (final session in sessions)
            _SessionCard(
              session: session,
              isCurrent: session.deviceId == installationId,
              userName: user.displayName,
              onTerminate: session.status == 'active'
                  ? () => _terminateSession(
                      context,
                      ref,
                      session,
                      userName: user.displayName,
                    )
                  : null,
              ref: ref,
            ),
      ],
    );
  }

  Widget _buildAdminView(BuildContext context, WidgetRef ref, String tenantId) {
    final tenantState = ref.watch(tenantProvider(tenantId));
    final devicesState = ref.watch(tenantDeviceRegistryProvider(tenantId));
    final sessionsState = ref.watch(tenantSessionRegistryProvider(tenantId));
    final usersState = ref.watch(tenantUsersProvider(tenantId));
    final currentUser = ref.watch(authUserProvider).value;
    final installationId = ref
        .watch(currentDeviceInstallationProvider)
        .value
        ?.installationId;

    return tenantState.when(
      data: (tenant) {
        if (tenant == null) {
          return Center(child: Text(tr('access_workspace_unavailable', ref)));
        }
        final canEditPolicy = currentUser?.isSuperAdmin == true
            ? currentUser?.activeWorkspaceId == tenant.id
            : currentUser?.isTenantAdmin == true &&
                  currentUser?.id == tenant.ownerUserId;
        if (devicesState.isLoading ||
            sessionsState.isLoading ||
            usersState.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        final error =
            devicesState.error ?? sessionsState.error ?? usersState.error;
        if (error != null) return mappedErrorState(error: error, ref: ref);
        final devices = devicesState.value ?? const <DeviceRegistrationModel>[];
        final sessions = sessionsState.value ?? const <SessionModel>[];
        final users = usersState.value ?? const <UserModel>[];
        final userNames = {
          for (final user in users)
            user.id: user.displayName.trim().isEmpty
                ? user.email
                : user.displayName,
        };

        return Column(
          children: [
            _WorkspacePolicyEditor(tenant: tenant, canEdit: canEditPolicy),
            if (devices.length >= 200 || sessions.length >= 200)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 8),
                child: Text(
                  tr('access_registry_limit_notice', ref),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Expanded(
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    TabBar(
                      tabs: [
                        Tab(text: tr('access_devices', ref)),
                        Tab(text: tr('access_active_sessions', ref)),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _adminDeviceList(
                            context,
                            ref,
                            devices,
                            sessions,
                            userNames,
                            currentUser?.id,
                            installationId,
                          ),
                          _adminSessionList(
                            context,
                            ref,
                            sessions,
                            userNames,
                            currentUser?.id,
                            installationId,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => mappedErrorState(
        error: error,
        ref: ref,
        onRetry: () => ref.invalidate(tenantProvider(tenantId)),
      ),
    );
  }

  Widget _adminDeviceList(
    BuildContext context,
    WidgetRef ref,
    List<DeviceRegistrationModel> devices,
    List<SessionModel> sessions,
    Map<String, String> userNames,
    String? currentUserId,
    String? installationId,
  ) {
    if (devices.isEmpty) {
      return Center(child: Text(tr('access_no_devices', ref)));
    }
    final now = DateTime.now();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: devices.length,
      itemBuilder: (context, index) {
        final device = devices[index];
        final relatedSessions = sessions
            .where(
              (session) =>
                  session.userId == device.userId &&
                  session.deviceId == device.deviceId,
            )
            .toList();
        return _DeviceCard(
          device: device,
          userName: userNames[device.userId] ?? tr('access_unknown_user', ref),
          isCurrent:
              device.userId == currentUserId &&
              device.deviceId == installationId,
          activeSessionCount: relatedSessions
              .where((session) => session.status == 'active')
              .where(
                (session) => session.expiresAt?.toDate().isAfter(now) ?? false,
              )
              .length,
          onRevoke: device.status == 'active'
              ? () => _revokeDevice(
                  context,
                  ref,
                  device,
                  userName:
                      userNames[device.userId] ??
                      tr('access_unknown_user', ref),
                  relatedSessionCount: relatedSessions.length,
                )
              : null,
          ref: ref,
        );
      },
    );
  }

  Widget _adminSessionList(
    BuildContext context,
    WidgetRef ref,
    List<SessionModel> sessions,
    Map<String, String> userNames,
    String? currentUserId,
    String? installationId,
  ) {
    if (sessions.isEmpty) {
      return Center(child: Text(tr('access_no_sessions', ref)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final session = sessions[index];
        final userName =
            userNames[session.userId] ?? tr('access_unknown_user', ref);
        return _SessionCard(
          session: session,
          userName: userName,
          isCurrent:
              session.userId == currentUserId &&
              session.deviceId == installationId,
          onTerminate: session.status == 'active'
              ? () =>
                    _terminateSession(context, ref, session, userName: userName)
              : null,
          ref: ref,
        );
      },
    );
  }

  Future<void> _revokeDevice(
    BuildContext context,
    WidgetRef ref,
    DeviceRegistrationModel device, {
    required String userName,
    required int relatedSessionCount,
  }) async {
    final confirmed = await _confirmAction(
      context,
      title: tr('access_remove_device', ref),
      details: [
        '${tr('access_user', ref)}: $userName',
        '${tr('access_device', ref)}: ${device.displayName}',
        '${tr('access_status', ref)}: ${_statusLabel(device.status, ref)}',
        '${tr('access_related_sessions', ref)}: $relatedSessionCount',
        tr('access_device_revoke_effect', ref),
      ].join('\n'),
      ref: ref,
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(sessionManagementNotifierProvider.notifier)
          .revokeDevice(device.userId, device.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(successSnackBar(tr('access_device_removed', ref)));
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(errorSnackBar(tr(AppErrorMapper.key(error), ref)));
      }
    }
  }

  Future<void> _terminateSession(
    BuildContext context,
    WidgetRef ref,
    SessionModel session, {
    required String userName,
  }) async {
    final confirmed = await _confirmAction(
      context,
      title: tr('access_terminate_session', ref),
      details: [
        '${tr('access_user', ref)}: $userName',
        '${tr('access_device', ref)}: ${[session.deviceBrand, session.deviceModel].whereType<String>().where((value) => value.isNotEmpty).join(' ')}',
        '${tr('access_status', ref)}: ${_statusLabel(session.status, ref)}',
        '${tr('access_started', ref)}: ${_formatDate(context, session.createdAt.toDate())}',
        tr('access_session_terminate_effect', ref),
      ].join('\n'),
      ref: ref,
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(sessionManagementNotifierProvider.notifier)
          .terminateSession(
            session.userId,
            session.id,
            reason: 'admin_terminated',
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(successSnackBar(tr('access_session_terminated', ref)));
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(errorSnackBar(tr(AppErrorMapper.key(error), ref)));
      }
    }
  }

  Future<bool?> _confirmAction(
    BuildContext context, {
    required String title,
    required String details,
    required WidgetRef ref,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(details),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('cancel', ref)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr('confirm', ref)),
          ),
        ],
      ),
    );
  }
}

class _WorkspacePolicyEditor extends ConsumerStatefulWidget {
  final TenantModel tenant;
  final bool canEdit;

  const _WorkspacePolicyEditor({required this.tenant, required this.canEdit});

  @override
  ConsumerState<_WorkspacePolicyEditor> createState() =>
      _WorkspacePolicyEditorState();
}

class _WorkspacePolicyEditorState
    extends ConsumerState<_WorkspacePolicyEditor> {
  late final TextEditingController _devicesController;
  late final TextEditingController _sessionsController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _devicesController = TextEditingController(
      text: widget.tenant.maxDevicesAllowed.toString(),
    );
    _sessionsController = TextEditingController(
      text: widget.tenant.maxActiveSessionsAllowed.toString(),
    );
  }

  @override
  void didUpdateWidget(covariant _WorkspacePolicyEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenant.id != widget.tenant.id ||
        oldWidget.tenant.updatedAt != widget.tenant.updatedAt) {
      _devicesController.text = widget.tenant.maxDevicesAllowed.toString();
      _sessionsController.text = widget.tenant.maxActiveSessionsAllowed
          .toString();
    }
  }

  @override
  void dispose() {
    _devicesController.dispose();
    _sessionsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final devices = int.tryParse(_devicesController.text.trim());
    final sessions = int.tryParse(_sessionsController.text.trim());
    if (devices == null ||
        sessions == null ||
        devices < 1 ||
        sessions < 1 ||
        devices > AccessUsageSummary.maximumSlotsPerUser ||
        sessions > AccessUsageSummary.maximumSlotsPerUser) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(errorSnackBar(tr('access_policy_range', ref)));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(tenantManagementNotifierProvider.notifier)
          .updateTenant(
            widget.tenant.id,
            name: widget.tenant.name,
            slug: widget.tenant.slug,
            requireDevicePairing: widget.tenant.requireDevicePairing,
            allowAdminResetOnly: widget.tenant.allowAdminResetOnly,
            maxDevicesAllowed: devices,
            maxActiveSessionsAllowed: sessions,
            ownerUserId: widget.tenant.ownerUserId,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(successSnackBar(tr('access_policy_saved', ref)));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(errorSnackBar(tr(AppErrorMapper.key(error), ref)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('access_policy_title', ref),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _devicesController,
                  enabled: widget.canEdit && !_saving,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: tr('access_policy_devices', ref),
                    helperText: tr('access_policy_devices_help', ref),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _sessionsController,
                  enabled: widget.canEdit && !_saving,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: tr('access_policy_sessions', ref),
                    helperText: tr('access_policy_sessions_help', ref),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              tr('access_policy_reduced_notice', ref),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (widget.canEdit)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(tr('save_changes', ref)),
              ),
            ),
          const Divider(height: 16),
        ],
      ),
    );
  }
}

class _CapacitySection extends StatelessWidget {
  final String title;
  final IconData icon;
  final String allowedLabel;
  final String usedLabel;
  final String availableLabel;
  final int allowed;
  final int used;
  final int available;
  final int overLimit;
  final WidgetRef ref;

  const _CapacitySection({
    required this.title,
    required this.icon,
    required this.allowedLabel,
    required this.usedLabel,
    required this.availableLabel,
    required this.allowed,
    required this.used,
    required this.available,
    required this.overLimit,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _CapacityValue(label: allowedLabel, value: allowed),
                _CapacityValue(label: usedLabel, value: used),
                _CapacityValue(label: availableLabel, value: available),
              ],
            ),
            if (overLimit > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${tr('access_over_limit', ref)}: $overLimit',
                  style: TextStyle(color: colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CapacityValue extends StatelessWidget {
  final String label;
  final int value;

  const _CapacityValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value.toString(), style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final DeviceRegistrationModel device;
  final String? userName;
  final bool isCurrent;
  final int activeSessionCount;
  final VoidCallback? onRevoke;
  final WidgetRef ref;

  const _DeviceCard({
    required this.device,
    required this.isCurrent,
    required this.activeSessionCount,
    required this.onRevoke,
    required this.ref,
    this.userName,
  });

  @override
  Widget build(BuildContext context) {
    final title = device.displayName.isEmpty
        ? tr('access_unknown_device', ref)
        : device.displayName;
    final details = [
      ?userName,
      device.platform,
      if (device.appVersion.isNotEmpty)
        '${tr('access_app_version', ref)} ${device.appVersion}',
      '${tr('access_registered_at', ref)} ${_formatDate(context, device.registeredAt.toDate())}',
      '${tr('access_last_seen', ref)} ${_formatDate(context, device.lastSeenAt.toDate())}',
    ];
    return Card(
      child: ListTile(
        leading: const Icon(Icons.devices_outlined),
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isCurrent) Text(tr('access_current_device', ref)),
            Text(
              details.join(' · '),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            Text('${tr('access_related_sessions', ref)}: $activeSessionCount'),
          ],
        ),
        trailing: onRevoke == null
            ? _StatusChip(status: device.status, ref: ref)
            : Tooltip(
                message: tr('access_remove_device', ref),
                child: IconButton(
                  onPressed: onRevoke,
                  icon: const Icon(Icons.phonelink_erase_outlined),
                ),
              ),
        isThreeLine: true,
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final SessionModel session;
  final String userName;
  final bool isCurrent;
  final VoidCallback? onTerminate;
  final WidgetRef ref;

  const _SessionCard({
    required this.session,
    required this.userName,
    required this.isCurrent,
    required this.onTerminate,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final deviceName = [
      session.deviceBrand,
      session.deviceModel,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' ');
    final title = deviceName.isEmpty
        ? tr('access_unknown_device', ref)
        : deviceName;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.phonelink_lock_outlined),
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(userName, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (isCurrent) Text(tr('access_current_device', ref)),
            Text(
              '${tr('access_started', ref)} ${_formatDate(context, session.createdAt.toDate())} · ${tr('access_last_seen', ref)} ${_formatDate(context, session.lastSeenAt.toDate())}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        trailing: onTerminate == null
            ? _StatusChip(status: session.status, ref: ref)
            : Tooltip(
                message: tr('access_terminate_session', ref),
                child: IconButton(
                  onPressed: onTerminate,
                  icon: const Icon(Icons.logout_outlined),
                ),
              ),
        isThreeLine: true,
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  final WidgetRef ref;

  const _StatusChip({required this.status, required this.ref});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Chip(
      label: Text(_statusLabel(status, ref)),
      visualDensity: VisualDensity.compact,
      backgroundColor: status == 'active'
          ? colorScheme.tertiaryContainer
          : colorScheme.surfaceContainerHighest,
    );
  }
}

String _statusLabel(String status, WidgetRef ref) => switch (status) {
  'active' => tr('access_status_active', ref),
  'revoked' => tr('access_status_revoked', ref),
  'expired' => tr('access_status_expired', ref),
  _ => tr('status_unknown', ref),
};

String _formatDate(BuildContext context, DateTime date) => DateFormat.yMMMd(
  Localizations.localeOf(context).toString(),
).add_jm().format(date);
