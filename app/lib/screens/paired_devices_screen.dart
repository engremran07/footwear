import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/l10n/app_locale.dart';
import '../models/device_registration_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/tenant_provider.dart';
import '../widgets/error_state.dart';

class PairedDevicesScreen extends ConsumerStatefulWidget {
  final String tenantId;

  const PairedDevicesScreen({super.key, required this.tenantId});

  @override
  ConsumerState<PairedDevicesScreen> createState() =>
      _PairedDevicesScreenState();
}

class _PairedDevicesScreenState extends ConsumerState<PairedDevicesScreen> {
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(tenantDeviceRegistryProvider(widget.tenantId));
    ref.invalidate(tenantAccessRegistryUsersProvider(widget.tenantId));
    await Future.wait([
      ref.read(tenantDeviceRegistryProvider(widget.tenantId).future),
      ref.read(tenantAccessRegistryUsersProvider(widget.tenantId).future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authUserProvider).value;
    final devicesState = ref.watch(
      tenantDeviceRegistryProvider(widget.tenantId),
    );
    final usersState = ref.watch(
      tenantAccessRegistryUsersProvider(widget.tenantId),
    );

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('paired_devices_title', ref))),
        body: Center(child: Text(tr('access_workspace_unavailable', ref))),
      );
    }

    final error = devicesState.error ?? usersState.error;
    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('paired_devices_title', ref))),
        body: mappedErrorState(
          error: error,
          ref: ref,
          onRetry: () {
            ref.invalidate(tenantDeviceRegistryProvider(widget.tenantId));
            ref.invalidate(tenantAccessRegistryUsersProvider(widget.tenantId));
          },
        ),
      );
    }

    if (devicesState.isLoading || usersState.isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('paired_devices_title', ref))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final devices = devicesState.value ?? const <DeviceRegistrationModel>[];
    final users = usersState.value ?? const <UserModel>[];
    final usersById = {for (final user in users) user.id: user};
    final query = _search.trim().toLowerCase();
    final filteredDevices =
        devices.where((device) {
            final user = usersById[device.userId];
            final searchable = [
              user?.displayName ?? '',
              user?.email ?? '',
              device.brand,
              device.model,
              device.platform,
              device.osVersion,
              device.appVersion,
              device.status,
            ].join(' ').toLowerCase();
            return query.isEmpty || searchable.contains(query);
          }).toList()
          ..sort((left, right) => right.lastSeenAt.compareTo(left.lastSeenAt));

    return Scaffold(
      appBar: AppBar(title: Text(tr('paired_devices_title', ref))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _search = value),
              decoration: InputDecoration(
                labelText: tr('paired_devices_search', ref),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        tooltip: tr('clear', ref),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _search = '');
                        },
                        icon: const Icon(Icons.clear),
                      ),
              ),
            ),
          ),
          if (devices.length >= 200 || users.length >= 200)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
              child: Text(
                tr('access_registry_limit_notice', ref),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: filteredDevices.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Center(child: Text(tr('access_no_devices', ref))),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        12,
                        4,
                        12,
                        16,
                      ),
                      itemCount: filteredDevices.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final device = filteredDevices[index];
                        final account = usersById[device.userId];
                        final displayName = account?.displayName.trim() ?? '';
                        final name = displayName.isNotEmpty
                            ? displayName
                            : tr('access_unknown_user', ref);
                        final model = device.displayName.isNotEmpty
                            ? device.displayName
                            : tr('access_unknown_device', ref);
                        final osLabel = device.platform == 'android'
                            ? tr('access_android_version', ref)
                            : tr('access_os_version', ref);

                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.devices_outlined),
                            title: Text(
                              model,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$name · ${account?.email ?? tr('access_unknown_user', ref)}',
                                  ),
                                  Text(
                                    '${tr('access_app_version', ref)}: ${device.appVersion.isEmpty ? '—' : device.appVersion}',
                                  ),
                                  Text(
                                    '$osLabel: ${device.osVersion.isEmpty ? '—' : device.osVersion}',
                                  ),
                                  Text(
                                    '${tr('access_status', ref)}: ${_deviceStatus(device.status, ref)} · ${tr('access_registered_at', ref)} ${_formatDate(context, device.registeredAt)}',
                                  ),
                                  Text(
                                    '${tr('access_last_seen', ref)} ${_formatDate(context, device.lastSeenAt)}',
                                  ),
                                ],
                              ),
                            ),
                            isThreeLine: false,
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

String _deviceStatus(String status, WidgetRef ref) => switch (status) {
  'active' => tr('access_status_active', ref),
  'pending' => tr('access_status_pending', ref),
  'revoked' => tr('access_status_revoked', ref),
  'blocked' => tr('access_status_blocked', ref),
  _ => tr('status_unknown', ref),
};

String _formatDate(BuildContext context, Timestamp timestamp) =>
    DateFormat.yMMMd(
      Localizations.localeOf(context).toString(),
    ).add_jm().format(timestamp.toDate());
