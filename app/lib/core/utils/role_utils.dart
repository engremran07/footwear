import 'package:flutter/foundation.dart' show debugPrint;
import '../../models/user_model.dart';

/// P1-8 FIX: Normalize role name with explicit defaulting and Vibe Debt logging.
String normalizeRoleName(String role) {
  if (role.isEmpty) {
    debugPrint(
      '[VIB] P1-8 Signal: Empty role string in normalizeRoleName; defaulting to seller',
    );
    return 'seller';
  }

  final normalized = role.trim().toLowerCase();

  if (normalized.isEmpty) {
    debugPrint(
      '[VIB] P1-8 Signal: Whitespace-only role string in normalizeRoleName; defaulting to seller',
    );
    return 'seller';
  }

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
      debugPrint(
        '[VIB] P1-8 Signal: Unknown role "$role" in normalizeRoleName; defaulting to seller',
      );
      return 'seller';
  }
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
