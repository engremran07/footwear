import 'package:flutter/foundation.dart' show debugPrint;
import '../../models/user_model.dart';
import 'role_names.dart';

String normalizeRoleName(String role) {
  final canonical = canonicalRoleName(role);
  if (canonical == 'unknown') {
    debugPrint('[SEC] Unsupported account role; access remains blocked');
  }
  return canonical;
}

bool canManageUserAccountsRole(String role) {
  final normalized = normalizeRoleName(role);
  // P1-6 FIX: tenant_admin should be able to manage users within their tenant
  return normalized == 'admin' ||
      normalized == 'tenant_admin' ||
      normalized == 'super_admin';
}

bool canManageWorkspaceRole(String role) {
  final normalized = normalizeRoleName(role);
  return normalized == 'super_admin';
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
    case 'super_admin':
      return 'role_super_admin';
    case 'unknown':
      return 'role_unknown';
    default:
      return 'role_unknown';
  }
}
