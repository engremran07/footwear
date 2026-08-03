import '../../models/user_model.dart';

String normalizeRoleName(String role) {
  final normalized = role.trim().toLowerCase();
  switch (normalized) {
    case 'manager':
    case 'admin':
      return 'admin';
    case 'tenant_admin':
    case 'tenant-admin':
    case 'tenantadmin':
      return 'tenant_admin';
    case 'super_admin':
    case 'super-admin':
    case 'superadmin':
      return 'super_admin';
    case 'seller':
      return 'seller';
    default:
      return 'seller';
  }
}

bool isPrivilegedRoleName(String role) {
  final normalized = normalizeRoleName(role);
  return normalized == 'admin' ||
      normalized == 'tenant_admin' ||
      normalized == 'super_admin';
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
    case 'super_admin':
      return 'role_super_admin';
    default:
      return 'lbl_seller';
  }
}
