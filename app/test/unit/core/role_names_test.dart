import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/utils/role_names.dart';
import 'package:footwear_erp/core/utils/role_utils.dart';
import 'package:footwear_erp/models/user_model.dart';

void main() {
  test('canonicalizes accepted legacy and tenant-aware roles', () {
    expect(canonicalRoleName(' Manager '), 'admin');
    expect(canonicalRoleName('tenant-admin'), 'tenant_admin');
    expect(canonicalRoleName('SuperAdmin'), 'super_admin');
    expect(canonicalRoleName('seller'), 'seller');
  });

  test('keeps unknown and empty role values explicit', () {
    expect(canonicalRoleName('workspace_owner'), 'unknown');
    expect(canonicalRoleName('  '), 'unknown');
  });

  test('workspace security management is limited to super admins', () {
    expect(canManageWorkspaceRole('tenant_admin'), isFalse);
    expect(canManageWorkspaceRole('super_admin'), isTrue);
    expect(canManageWorkspaceRole('admin'), isFalse);
    expect(canManageWorkspaceRole('seller'), isFalse);
  });

  test(
    'tenant security route is scoped to tenant admin or active workspace',
    () {
      UserModel user({
        required UserRole role,
        String? tenantId,
        String? activeWorkspaceId,
      }) => UserModel(
        id: 'user-1',
        email: 'user@example.com',
        displayName: 'User',
        role: role,
        tenantId: tenantId,
        activeWorkspaceId: activeWorkspaceId,
        activeWorkspaceReason: activeWorkspaceId == null
            ? null
            : 'Investigating a report',
        activeWorkspaceSelectedAt: activeWorkspaceId == null
            ? null
            : Timestamp.fromDate(DateTime.now()),
        active: true,
        createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
        updatedAt: Timestamp.fromMillisecondsSinceEpoch(0),
      );

      expect(
        canManageTenantSecurity(
          user(role: UserRole.tenantAdmin, tenantId: 'tenant-1'),
          'tenant-1',
        ),
        isTrue,
      );
      expect(
        canManageTenantSecurity(
          user(role: UserRole.tenantAdmin, tenantId: 'tenant-1'),
          'tenant-2',
        ),
        isFalse,
      );
      expect(
        canManageTenantSecurity(
          user(role: UserRole.superAdmin, activeWorkspaceId: 'tenant-1'),
          'tenant-1',
        ),
        isTrue,
      );
      expect(
        canManageTenantSecurity(
          user(role: UserRole.superAdmin, activeWorkspaceId: 'tenant-1'),
          'tenant-2',
        ),
        isFalse,
      );
      expect(
        canManageTenantSecurity(
          user(role: UserRole.admin, tenantId: 'tenant-1'),
          'tenant-1',
        ),
        isFalse,
      );
    },
  );
}
