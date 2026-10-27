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
    case 'supervisor':
      return 'supervisor';
    case 'seller':
      return 'seller';
    default:
      return 'unknown';
  }
}

enum AppCapability {
  manageWorkspaces,
  manageUsers,
  createSupervisor,
  viewSettingsHub,
  manageSettings,
  manageBackup,
  viewDashboard,
  viewNotifications,
  viewReports,
  viewRoutes,
  manageRoutes,
  viewShops,
  manageShops,
  viewProducts,
  manageProducts,
  viewInventory,
  manageInventory,
  viewInvoices,
  createInvoice,
  createCashReceipt,
  settleInvoice,
  viewHistory,
  writeOff,
  voidInvoice,
  creditNote,
  editLedger,
  assignRouteSeller,
  reassignShopRoute,
  manageDataMaintenance,
}

class RoleCapabilities {
  RoleCapabilities._();

  static const _businessAdmin = <AppCapability>{
    AppCapability.manageUsers,
    AppCapability.viewSettingsHub,
    AppCapability.manageSettings,
    AppCapability.manageBackup,
    AppCapability.viewDashboard,
    AppCapability.viewNotifications,
    AppCapability.viewReports,
    AppCapability.viewRoutes,
    AppCapability.manageRoutes,
    AppCapability.viewShops,
    AppCapability.manageShops,
    AppCapability.viewProducts,
    AppCapability.manageProducts,
    AppCapability.viewInventory,
    AppCapability.manageInventory,
    AppCapability.viewInvoices,
    AppCapability.createInvoice,
    AppCapability.createCashReceipt,
    AppCapability.settleInvoice,
    AppCapability.viewHistory,
    AppCapability.writeOff,
    AppCapability.voidInvoice,
    AppCapability.creditNote,
    AppCapability.editLedger,
    AppCapability.assignRouteSeller,
    AppCapability.reassignShopRoute,
  };

  static const _supervisor = <AppCapability>{
    AppCapability.viewDashboard,
    AppCapability.viewNotifications,
    AppCapability.viewReports,
    AppCapability.viewRoutes,
    AppCapability.manageRoutes,
    AppCapability.viewShops,
    AppCapability.manageShops,
    AppCapability.viewProducts,
    AppCapability.manageProducts,
    AppCapability.viewInventory,
    AppCapability.manageInventory,
    AppCapability.viewInvoices,
    AppCapability.createInvoice,
    AppCapability.createCashReceipt,
    AppCapability.viewHistory,
  };

  static const _seller = <AppCapability>{
    AppCapability.viewDashboard,
    AppCapability.viewShops,
    AppCapability.manageShops,
    AppCapability.viewProducts,
    AppCapability.viewInventory,
    AppCapability.viewInvoices,
    AppCapability.createInvoice,
    AppCapability.createCashReceipt,
    AppCapability.viewHistory,
  };

  static const Map<String, Set<AppCapability>> matrix = {
    'admin': _businessAdmin,
    'tenant_admin': {..._businessAdmin, AppCapability.createSupervisor},
    'super_admin': {
      AppCapability.manageWorkspaces,
      AppCapability.manageDataMaintenance,
      AppCapability.createSupervisor,
      ..._businessAdmin,
    },
    'supervisor': _supervisor,
    'seller': _seller,
  };

  static bool allows(String role, AppCapability capability) =>
      matrix[canonicalRoleName(role)]?.contains(capability) ?? false;

  static bool canManageTargetRole(String managerRole, String targetRole) {
    final manager = canonicalRoleName(managerRole);
    final target = canonicalRoleName(targetRole);
    return switch (manager) {
      'admin' => target == 'seller',
      'tenant_admin' => target == 'supervisor' || target == 'seller',
      'super_admin' =>
        target == 'admin' ||
            target == 'tenant_admin' ||
            target == 'supervisor' ||
            target == 'seller',
      _ => false,
    };
  }
}
