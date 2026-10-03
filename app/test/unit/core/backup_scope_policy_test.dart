import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/utils/backup_scope_policy.dart';
import 'package:footwear_erp/models/user_model.dart';

void main() {
  test(
    'platform backups contain only workspace metadata and user profiles',
    () {
      expect(
        BackupScopePolicy.scopeFor(UserRole.superAdmin),
        BackupScope.platformMetadata,
      );
      expect(BackupScopePolicy.collectionsFor(UserRole.superAdmin), {
        'workspaces',
        'users',
      });
    },
  );

  test('tenant-admin backups cover workspace data but not user accounts', () {
    expect(
      BackupScopePolicy.scopeFor(UserRole.tenantAdmin),
      BackupScope.workspaceBusiness,
    );
    expect(BackupScopePolicy.collectionsFor(UserRole.tenantAdmin), {
      'routes',
      'shops',
      'products',
      'inventory',
      'transactions',
      'invoices',
      'settings',
    });
  });

  test('seller and legacy admin accounts cannot initiate backups', () {
    expect(BackupScopePolicy.scopeFor(UserRole.seller), BackupScope.disabled);
    expect(BackupScopePolicy.scopeFor(UserRole.admin), BackupScope.disabled);
    expect(BackupScopePolicy.collectionsFor(UserRole.seller), isEmpty);
    expect(BackupScopePolicy.collectionsFor(UserRole.admin), isEmpty);
  });

  test(
    'recognizes all canonical super-admin aliases for profile filtering',
    () {
      expect(BackupScopePolicy.isPlatformRole('super_admin'), isTrue);
      expect(BackupScopePolicy.isPlatformRole(' SuperAdmin '), isTrue);
      expect(BackupScopePolicy.isPlatformRole('tenant_admin'), isFalse);
    },
  );

  test('backup access is limited to the currently selected workspace', () {
    expect(
      BackupScopePolicy.requireSelectedWorkspace(
        activeWorkspaceId: 'tenant-1',
        requestedWorkspaceId: 'tenant-1',
      ),
      'tenant-1',
    );
    expect(
      () => BackupScopePolicy.requireSelectedWorkspace(
        activeWorkspaceId: 'tenant-1',
        requestedWorkspaceId: 'tenant-2',
      ),
      throwsStateError,
    );
    expect(
      () => BackupScopePolicy.requireSelectedWorkspace(activeWorkspaceId: null),
      throwsStateError,
    );
  });
}
