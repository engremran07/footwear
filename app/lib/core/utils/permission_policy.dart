import '../../models/user_model.dart';
import 'role_names.dart';
import 'tenant_scope.dart';

enum RouteAccessDecision { allowed, denied, workspaceSelectionRequired }

class PermissionPolicy {
  PermissionPolicy._();

  static bool canUpdateOwnDisplayName(
    UserModel? user,
    String authenticatedUid,
  ) {
    final uid = authenticatedUid.trim();
    return user != null &&
        user.active &&
        uid.isNotEmpty &&
        user.id.trim() == uid;
  }

  static bool hasRoleCapability(UserModel? user, AppCapability capability) =>
      user != null &&
      user.active &&
      RoleCapabilities.allows(_roleValue(user.role), capability);

  static bool can(
    UserModel? user,
    AppCapability capability, {
    String? tenantId,
    String? targetRole,
    DateTime? now,
  }) {
    if (user == null || !user.active) return false;
    if (capability == AppCapability.manageWorkspaces) {
      return user.isSuperAdmin;
    }
    if (capability == AppCapability.viewSettingsHub &&
        user.isSuperAdmin &&
        TenantScope.normalize(user.tenantId) == null) {
      return RoleCapabilities.allows(_roleValue(user.role), capability);
    }

    final scopedTenantId = TenantScope.normalize(tenantId ?? user.tenantId);
    if (scopedTenantId == null ||
        scopedTenantId == TenantScope.globalTenantId) {
      return false;
    }
    if (user.isSuperAdmin) {
      if (!user.hasActiveWorkspaceSupportContextFor(scopedTenantId, now: now)) {
        return false;
      }
    } else if (TenantScope.normalize(user.tenantId) != scopedTenantId) {
      return false;
    }

    if (!RoleCapabilities.allows(_roleValue(user.role), capability)) {
      if (capability == AppCapability.manageBackup &&
          user.isSeller &&
          user.assignedRouteIds.isNotEmpty) {
        return true;
      }
      return false;
    }
    if (capability == AppCapability.createSupervisor &&
        !RoleCapabilities.canManageTargetRole(
          _roleValue(user.role),
          'supervisor',
        )) {
      return false;
    }
    if (capability == AppCapability.manageUsers && targetRole != null) {
      return RoleCapabilities.canManageTargetRole(
        _roleValue(user.role),
        targetRole,
      );
    }
    return true;
  }

  static bool canAccessRoute(UserModel? user, String rawPath) {
    return routeAccessDecision(user, rawPath) == RouteAccessDecision.allowed;
  }

  static RouteAccessDecision routeAccessDecision(
    UserModel? user,
    String rawPath,
  ) {
    var path = Uri.tryParse(rawPath)?.path ?? rawPath;
    path = path.replaceAll(RegExp(r'/+'), '/');
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path == '/') return _routeDecision(user, AppCapability.viewDashboard);
    if (path == '/about' || path == '/profile') {
      return user != null && user.active
          ? RouteAccessDecision.allowed
          : RouteAccessDecision.denied;
    }
    if (path == '/tenants') {
      return _routeDecision(
        user,
        AppCapability.manageWorkspaces,
        workspaceScoped: false,
      );
    }
    if (path == '/users') {
      return _routeDecision(user, AppCapability.manageUsers);
    }
    if (path == '/notifications') {
      return _routeDecision(user, AppCapability.viewNotifications);
    }
    if (path == '/reports') {
      return _routeDecision(user, AppCapability.viewReports);
    }
    if (path == '/settings/backup') {
      return _routeDecision(user, AppCapability.manageBackup);
    }
    if (path == '/settings/flush') {
      if (can(user, AppCapability.viewDataMaintenance) ||
          can(user, AppCapability.manageDataMaintenance)) {
        return RouteAccessDecision.allowed;
      }
      return _routeDecision(user, AppCapability.viewDataMaintenance);
    }
    if (path == '/settings') {
      return _routeDecision(
        user,
        AppCapability.viewSettingsHub,
        workspaceScoped: false,
      );
    }
    if (path.startsWith('/settings/')) {
      return _routeDecision(user, AppCapability.manageSettings);
    }
    if (path == '/routes' || path.startsWith('/routes/')) {
      return _routeDecision(
        user,
        _isRouteMutation(path)
            ? AppCapability.manageRoutes
            : AppCapability.viewRoutes,
      );
    }
    if (path == '/shops' || path.startsWith('/shops/')) {
      return _routeDecision(
        user,
        _isShopMutation(path)
            ? AppCapability.manageShops
            : AppCapability.viewShops,
      );
    }
    if (path == '/products' || path.startsWith('/products/')) {
      return _routeDecision(
        user,
        _isProductMutation(path)
            ? AppCapability.manageProducts
            : AppCapability.viewProducts,
      );
    }
    if (path == '/inventory') {
      return _routeDecision(user, AppCapability.viewInventory);
    }
    if (path == '/invoices' || path.startsWith('/invoices/')) {
      return _routeDecision(
        user,
        path == '/invoices/new'
            ? AppCapability.createInvoice
            : AppCapability.viewInvoices,
      );
    }
    if (path == '/history') {
      return _routeDecision(user, AppCapability.viewHistory);
    }
    return RouteAccessDecision.denied;
  }

  static RouteAccessDecision _routeDecision(
    UserModel? user,
    AppCapability capability, {
    bool workspaceScoped = true,
  }) {
    if (can(user, capability)) return RouteAccessDecision.allowed;
    if (workspaceScoped &&
        user?.isSuperAdmin == true &&
        !can(user, AppCapability.viewDashboard)) {
      return RouteAccessDecision.workspaceSelectionRequired;
    }
    return RouteAccessDecision.denied;
  }

  static bool _isRouteMutation(String path) =>
      path == '/routes/new' || RegExp(r'^/routes/[^/]+/edit$').hasMatch(path);

  static bool _isShopMutation(String path) =>
      path == '/shops/new' || RegExp(r'^/shops/[^/]+/edit$').hasMatch(path);

  static bool _isProductMutation(String path) =>
      path == '/products/new' ||
      RegExp(r'^/products/[^/]+/edit$').hasMatch(path) ||
      RegExp(r'^/products/[^/]+/variants/new$').hasMatch(path) ||
      RegExp(r'^/products/[^/]+/variants/[^/]+/edit$').hasMatch(path);

  static String _roleValue(UserRole role) => switch (role) {
    UserRole.admin => 'admin',
    UserRole.seller => 'seller',
    UserRole.tenantAdmin => 'tenant_admin',
    UserRole.superAdmin => 'super_admin',
    UserRole.supervisor => 'supervisor',
    UserRole.unknown => 'unknown',
  };
}
