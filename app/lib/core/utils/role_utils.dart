import 'package:flutter/foundation.dart' show debugPrint;

import '../../models/user_model.dart';
import 'role_names.dart';
import 'permission_policy.dart';

String normalizeRoleName(String role) {
  final canonical = canonicalRoleName(role);
  if (canonical == 'unknown') {
    debugPrint('[SEC] Unsupported account role; access remains blocked');
  }
  return canonical;
}

bool canManageUserAccountsRole(String role) {
  return RoleCapabilities.allows(role, AppCapability.manageUsers);
}

bool canManageWorkspaceRole(String role) {
  return RoleCapabilities.allows(role, AppCapability.manageWorkspaces);
}

bool canManageTenantSecurity(UserModel user, String tenantId) {
  if ((!user.isTenantAdmin && !user.isSuperAdmin) ||
      !user.active ||
      tenantId.trim().isEmpty) {
    return false;
  }
  return PermissionPolicy.can(
    user,
    AppCapability.manageUsers,
    tenantId: tenantId,
  );
}

bool isPrivilegedRoleName(String role) {
  return RoleCapabilities.allows(role, AppCapability.manageUsers);
}

String roleValueFromUserRole(UserRole role) {
  switch (role) {
    case UserRole.admin:
      return 'admin';
    case UserRole.seller:
      return 'seller';
    case UserRole.tenantAdmin:
      return 'tenant_admin';
    case UserRole.superAdmin:
      return 'super_admin';
    case UserRole.supervisor:
      return 'supervisor';
    case UserRole.unknown:
      return 'unknown';
  }
}

String roleLabelKeyFromRoleValue(String roleValue) {
  switch (roleValue) {
    case 'admin':
      return 'lbl_admin';
    case 'seller':
      return 'lbl_seller';
    case 'tenant_admin':
      return 'role_tenant_admin';
    case 'supervisor':
      return 'role_supervisor';
    case 'super_admin':
      return 'role_super_admin';
    case 'unknown':
      return 'role_unknown';
    default:
      return 'role_unknown';
  }
}
