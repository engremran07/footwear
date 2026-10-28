import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/permission_policy.dart';
import '../core/utils/role_names.dart';
import '../core/utils/tenant_scope.dart';
import '../providers/auth_provider.dart';
import '../providers/tenant_provider.dart';
import '../widgets/error_state.dart';

class DatabaseFlushScreen extends ConsumerWidget {
  const DatabaseFlushScreen({super.key});

  Widget _disabledOperation(
    BuildContext context,
    WidgetRef ref,
    String titleKey,
  ) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      enabled: false,
      leading: Icon(Icons.block, color: colors.onSurfaceVariant),
      title: Text(tr(titleKey, ref)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authUserProvider);
    if (authState.isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('danger_zone', ref))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (authState.hasError) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('danger_zone', ref))),
        body: mappedErrorState(
          error: authState.error!,
          ref: ref,
          onRetry: () => ref.invalidate(authUserProvider),
        ),
      );
    }

    final currentUser = authState.value;
    if (currentUser == null ||
        (!PermissionPolicy.can(
              currentUser,
              AppCapability.viewDataMaintenance,
            ) &&
            !PermissionPolicy.can(
              currentUser,
              AppCapability.manageDataMaintenance,
            ))) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('danger_zone', ref))),
        body: Center(child: Text(tr('permission_denied', ref))),
      );
    }

    final tenantId = TenantScope.normalize(currentUser.tenantId);
    if (tenantId == null ||
        tenantId == TenantScope.globalTenantId ||
        (!PermissionPolicy.can(
              currentUser,
              AppCapability.viewDataMaintenance,
              tenantId: tenantId,
            ) &&
            !PermissionPolicy.can(
              currentUser,
              AppCapability.manageDataMaintenance,
              tenantId: tenantId,
            ))) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('danger_zone', ref))),
        body: Center(child: Text(tr('permission_denied', ref))),
      );
    }

    final tenantAsync = ref.watch(tenantProvider(tenantId));
    return Scaffold(
      appBar: AppBar(title: Text(tr('danger_zone', ref))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                tr('flush_data_reset_unavailable', ref),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.domain_outlined),
              title: Text(tr('flush_select_workspace', ref)),
              subtitle: tenantAsync.when(
                loading: () => Text(tr('loading', ref)),
                error: (error, _) => Text(tr(AppErrorMapper.key(error), ref)),
                data: (tenant) =>
                    Text(tenant?.name ?? tr('workspace_name_unavailable', ref)),
              ),
              trailing: tenantAsync.hasError
                  ? IconButton(
                      tooltip: tr('retry', ref),
                      onPressed: () => ref.invalidate(tenantProvider(tenantId)),
                      icon: const Icon(Icons.refresh),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                _disabledOperation(context, ref, 'flush_financial'),
                const Divider(height: 1),
                _disabledOperation(context, ref, 'flush_inventory'),
                const Divider(height: 1),
                _disabledOperation(context, ref, 'flush_shops'),
                const Divider(height: 1),
                _disabledOperation(context, ref, 'flush_routes'),
                const Divider(height: 1),
                _disabledOperation(context, ref, 'flush_products'),
                const Divider(height: 1),
                _disabledOperation(context, ref, 'flush_variants'),
                const Divider(height: 1),
                _disabledOperation(context, ref, 'flush_invoices'),
                const Divider(height: 1),
                _disabledOperation(context, ref, 'flush_notifications'),
                const Divider(height: 1),
                _disabledOperation(context, ref, 'flush_users'),
                const Divider(height: 1),
                _disabledOperation(context, ref, 'flush_per_user'),
                const Divider(height: 1),
                _disabledOperation(context, ref, 'flush_all'),
                const Divider(height: 1),
                _disabledOperation(context, ref, 'flush_settings'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
