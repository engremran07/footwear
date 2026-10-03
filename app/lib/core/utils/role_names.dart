String canonicalRoleName(String value) {
  switch (value.trim().toLowerCase()) {
    case 'admin':
    case 'manager':
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
      return 'unknown';
  }
}
