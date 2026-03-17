import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole { admin, manager, viewer, workerPk, workerKsa, seller }

/// All granular permissions in the system. Each maps to a Firestore string.
/// When creating/editing a user, the admin picks individual permissions.
/// Roles serve as templates that pre-select a set of permissions.
class AppPermissions {
  AppPermissions._();

  // ── Dashboard ──
  static const viewDashboard = 'view_dashboard';

  // ── Products ──
  static const viewProducts = 'view_products';
  static const createProducts = 'create_products';
  static const editProducts = 'edit_products';
  static const deleteProducts = 'delete_products';

  // ── Inventory ──
  static const viewInventory = 'view_inventory';
  static const createInventory = 'create_inventory';
  static const editInventory = 'edit_inventory';

  // ── Orders ──
  static const viewOrders = 'view_orders';
  static const createOrders = 'create_orders';
  static const editOrders = 'edit_orders';

  // ── Customers ──
  static const viewCustomers = 'view_customers';
  static const createCustomers = 'create_customers';
  static const editCustomers = 'edit_customers';

  // ── Workers ──
  static const viewWorkers = 'view_workers';
  static const createWorkers = 'create_workers';
  static const editWorkers = 'edit_workers';
  static const payWorkers = 'pay_workers';

  // ── Expenses ──
  static const viewExpenses = 'view_expenses';
  static const createExpenses = 'create_expenses';

  // ── Cash ──
  static const viewCash = 'view_cash';
  static const createCash = 'create_cash';

  // ── Approvals ──
  static const manageApprovals = 'manage_approvals';

  // ── Purchase Orders ──
  static const viewPurchaseOrders = 'view_purchase_orders';
  static const createPurchaseOrders = 'create_purchase_orders';
  static const editPurchaseOrders = 'edit_purchase_orders';

  // ── Suppliers ──
  static const viewSuppliers = 'view_suppliers';
  static const createSuppliers = 'create_suppliers';
  static const editSuppliers = 'edit_suppliers';

  // ── Shops (merged into customers) ──
  // Shop permissions removed — use customer permissions instead

  // ── Returns ──
  static const viewReturns = 'view_returns';
  static const createReturns = 'create_returns';
  static const approveReturns = 'approve_returns';

  // ── QC & Waste ──
  static const manageQc = 'manage_qc';
  static const viewWaste = 'view_waste';
  static const manageWaste = 'manage_waste';

  // ── Reports & P&L ──
  static const viewPnl = 'view_pnl';
  static const viewReports = 'view_reports';

  // ── Settings ──
  static const manageSettings = 'manage_settings';
  static const manageUsers = 'manage_users';

  /// All permissions grouped by category for the UI.
  static const Map<String, List<String>> grouped = {
    'dashboard': [viewDashboard],
    'products': [viewProducts, createProducts, editProducts, deleteProducts],
    'inventory': [viewInventory, createInventory, editInventory],
    'orders': [viewOrders, createOrders, editOrders],
    'customers': [viewCustomers, createCustomers, editCustomers],
    'workers': [viewWorkers, createWorkers, editWorkers, payWorkers],
    'expenses': [viewExpenses, createExpenses],
    'cash': [viewCash, createCash],
    'approvals': [manageApprovals],
    'purchase_orders': [
      viewPurchaseOrders,
      createPurchaseOrders,
      editPurchaseOrders
    ],
    'suppliers': [viewSuppliers, createSuppliers, editSuppliers],
    'returns': [viewReturns, createReturns, approveReturns],
    'qc_waste': [manageQc, viewWaste, manageWaste],
    'reports': [viewPnl, viewReports],
    'settings': [manageSettings, manageUsers],
  };

  /// Flat list of every permission string.
  static List<String> get all => grouped.values.expand((v) => v).toList();

  /// Default permissions for each role template.
  static List<String> defaultsForRole(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return List.of(all); // admin gets everything
      case UserRole.manager:
        return all
            .where((p) => p != manageUsers && p != manageSettings)
            .toList();
      case UserRole.seller:
        return [
          viewDashboard,
          viewProducts,
          viewOrders,
          createOrders,
          editOrders,
          viewCustomers,
          createCustomers,
          editCustomers,
          viewInventory,
          viewReturns,
          createReturns,
        ];
      case UserRole.viewer:
        return all.where((p) => p.startsWith('view_')).toList()
          ..add(viewDashboard);
      case UserRole.workerPk:
      case UserRole.workerKsa:
        return [viewDashboard, viewInventory, viewProducts];
    }
  }
}

UserRole _roleFromString(String s) {
  switch (s) {
    case 'admin':
      return UserRole.admin;
    case 'manager':
      return UserRole.manager;
    case 'worker_pk':
      return UserRole.workerPk;
    case 'worker_ksa':
      return UserRole.workerKsa;
    case 'seller':
      return UserRole.seller;
    default:
      return UserRole.viewer;
  }
}

String _roleToString(UserRole r) {
  switch (r) {
    case UserRole.admin:
      return 'admin';
    case UserRole.manager:
      return 'manager';
    case UserRole.workerPk:
      return 'worker_pk';
    case UserRole.workerKsa:
      return 'worker_ksa';
    case UserRole.seller:
      return 'seller';
    case UserRole.viewer:
      return 'viewer';
  }
}

class UserModel {
  final String id;
  final String email;
  final String displayName;
  final UserRole role;
  final String? workerId;
  final String factoryAccess;
  final String country;
  final String currency;
  final bool active;
  final List<String> permissions;
  final Timestamp? lastActive;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const UserModel({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    this.workerId,
    this.factoryAccess = 'both',
    this.country = 'KSA',
    this.currency = 'SAR',
    required this.active,
    this.permissions = const [],
    this.lastActive,
    required this.createdAt,
    required this.updatedAt,
  });

  // ── Legacy role helpers (still used for backward-compat) ──
  bool get isAdmin => role == UserRole.admin;
  bool get isManager => role == UserRole.manager || role == UserRole.admin;
  bool get canWrite => role == UserRole.admin || role == UserRole.manager;
  bool get isWorker => role == UserRole.workerPk || role == UserRole.workerKsa;
  bool get isSeller => role == UserRole.seller;

  /// Check if the user has a specific granular permission.
  /// Admins always have all permissions regardless of the list.
  bool hasPermission(String permission) {
    if (role == UserRole.admin) return true;
    return permissions.contains(permission);
  }

  /// Check if user has ANY of the given permissions.
  bool hasAnyPermission(List<String> perms) {
    if (role == UserRole.admin) return true;
    return perms.any((p) => permissions.contains(p));
  }

  factory UserModel.fromJson(Map<String, dynamic> json, String docId) {
    final role = _roleFromString(json['role'] as String? ?? 'viewer');
    final rawPerms = json['permissions'] as List<dynamic>?;
    // If no permissions stored yet, derive from role for backward compat
    final permissions = rawPerms != null
        ? rawPerms.cast<String>()
        : AppPermissions.defaultsForRole(role);

    return UserModel(
      id: docId,
      email: json['email'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      role: role,
      workerId: json['worker_id'] as String?,
      factoryAccess: json['factory_access'] as String? ?? 'both',
      country: json['country'] as String? ?? 'KSA',
      currency: json['currency'] as String? ?? 'SAR',
      active: json['active'] as bool? ?? true,
      permissions: permissions,
      lastActive: json['last_active'] as Timestamp?,
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'email': email,
        'display_name': displayName,
        'role': _roleToString(role),
        'worker_id': workerId,
        'factory_access': factoryAccess,
        'country': country,
        'currency': currency,
        'active': active,
        'permissions': permissions,
        'last_active': lastActive,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  UserModel copyWith({
    String? id,
    String? email,
    String? displayName,
    UserRole? role,
    String? workerId,
    String? factoryAccess,
    String? country,
    String? currency,
    bool? active,
    List<String>? permissions,
    Timestamp? lastActive,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      workerId: workerId ?? this.workerId,
      factoryAccess: factoryAccess ?? this.factoryAccess,
      country: country ?? this.country,
      currency: currency ?? this.currency,
      active: active ?? this.active,
      permissions: permissions ?? this.permissions,
      lastActive: lastActive ?? this.lastActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
