import '../../models/user_model.dart';
import 'tenant_scope.dart';
import 'role_names.dart';

enum BackupScope { disabled, platformMetadata, workspaceBusiness }

class BackupScopePolicy {
  BackupScopePolicy._();

  static const platformMetadataCollections = <String>{'workspaces', 'users'};
  static const workspaceBusinessCollections = <String>{
    'routes',
    'shops',
    'products',
    'inventory',
    'transactions',
    'invoices',
    'settings',
  };

  static BackupScope scopeFor(UserRole role) => switch (role) {
    UserRole.superAdmin => BackupScope.platformMetadata,
    UserRole.tenantAdmin => BackupScope.workspaceBusiness,
    _ => BackupScope.disabled,
  };

  static Set<String> collectionsFor(UserRole role) => switch (scopeFor(role)) {
    BackupScope.platformMetadata => platformMetadataCollections,
    BackupScope.workspaceBusiness => workspaceBusinessCollections,
    BackupScope.disabled => const <String>{},
  };

  static String archiveScopeFor(UserRole role) => switch (scopeFor(role)) {
    BackupScope.platformMetadata => 'platform_metadata',
    BackupScope.workspaceBusiness => 'workspace',
    BackupScope.disabled => 'disabled',
  };

  static String requireSelectedWorkspace({
    required String? activeWorkspaceId,
    String? requestedWorkspaceId,
  }) {
    final activeWorkspace = TenantScope.normalize(activeWorkspaceId);
    if (activeWorkspace == null) {
      throw StateError('Select an active workspace before accessing backups');
    }
    final requestedWorkspace = TenantScope.normalize(requestedWorkspaceId);
    if (requestedWorkspace != null && requestedWorkspace != activeWorkspace) {
      throw StateError('Backup workspace must match the active workspace');
    }
    return activeWorkspace;
  }

  static bool isPlatformRole(String role) =>
      canonicalRoleName(role) == 'super_admin';
}
