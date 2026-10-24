import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/user_model.dart';
import 'tenant_scope.dart';
import 'role_names.dart';

enum BackupScope {
  disabled,
  platformMetadata,
  workspaceBusiness,
  sellerRoute,
}

class BackupScopePolicy {
  BackupScopePolicy._();

  static const platformMetadataCollections = <String>{'workspaces', 'users'};
  static const workspaceBusinessCollections = <String>{
    'routes',
    'shops',
    'products',
    'inventory',
    'transactions',
    'invoices',
    'settings',
  };
  static const sellerRouteCollections = <String>{
    'routes',
    'shops',
    'inventory',
    'transactions',
    'invoices',
  };

  static BackupScope scopeFor(UserRole role) => switch (role) {
    UserRole.superAdmin => BackupScope.platformMetadata,
    UserRole.tenantAdmin => BackupScope.workspaceBusiness,
    UserRole.seller => BackupScope.sellerRoute,
    _ => BackupScope.disabled,
  };

  static Set<String> collectionsFor(UserRole role) => switch (scopeFor(role)) {
    BackupScope.platformMetadata => platformMetadataCollections,
    BackupScope.workspaceBusiness => workspaceBusinessCollections,
    BackupScope.sellerRoute => sellerRouteCollections,
    BackupScope.disabled => const <String>{},
  };

  static String archiveScopeFor(UserRole role) => switch (scopeFor(role)) {
    BackupScope.platformMetadata => 'platform_metadata',
    BackupScope.workspaceBusiness => 'workspace',
    BackupScope.sellerRoute => 'seller_route',
    BackupScope.disabled => 'disabled',
  };

  static Set<String> routeIdsFor(Iterable<String> routeIds) => {
    for (final routeId in routeIds)
      if (routeId.trim().isNotEmpty) routeId.trim(),
  };

  static bool isSellerTransactionRestorable({
    required Map<String, dynamic> document,
    required String sellerId,
    required String routeId,
    required String tenantId,
    required Set<String> assignedRouteIds,
  }) {
    String stringField(String field) {
      final value = document[field];
      return value is String ? value.trim() : '';
    }

    final id = stringField('__id');
    final normalizedSellerId = sellerId.trim();
    final normalizedRouteId = routeId.trim();
    final shopId = stringField('shop_id');
    final customerId = stringField('customer_id');
    final amount = (document['amount'] as num?)?.toDouble();
    final type = document['type'];
    final invoiceId = stringField('invoice_id');
    final invoiceNumber = stringField('invoice_number');
    final items = document['items'];
    final normalizedAssignedRoutes = routeIdsFor(assignedRouteIds);

    return id.isNotEmpty &&
        normalizedSellerId.isNotEmpty &&
        normalizedRouteId.isNotEmpty &&
        normalizedAssignedRoutes.contains(normalizedRouteId) &&
        document['created_by'] == normalizedSellerId &&
        document['route_id'] == normalizedRouteId &&
        shopId.isNotEmpty &&
        (customerId.isEmpty || customerId == shopId) &&
        (type == 'cash_in' || type == 'cash_out') &&
        amount != null &&
        amount.isFinite &&
        amount > 0 &&
        document['created_at'] is Timestamp &&
        invoiceId.isEmpty &&
        invoiceNumber.isEmpty &&
        document['deleted'] != true &&
        document['edit_request_pending'] != true &&
        (items == null || (items is List && items.isEmpty)) &&
        TenantScope.matchesTenant(document, tenantId);
  }

  static String requireSelectedWorkspace({
    required String? activeWorkspaceId,
    String? requestedWorkspaceId,
  }) {
    final activeWorkspace = TenantScope.normalize(activeWorkspaceId);
    if (activeWorkspace == null ||
        activeWorkspace == TenantScope.globalTenantId) {
      throw StateError('Select an active workspace before accessing backups');
    }
    final requestedWorkspace = TenantScope.normalize(requestedWorkspaceId);
    if (requestedWorkspace == TenantScope.globalTenantId) {
      throw StateError('A concrete workspace is required for backups');
    }
    if (requestedWorkspace != null && requestedWorkspace != activeWorkspace) {
      throw StateError('Backup workspace must match the active workspace');
    }
    return activeWorkspace;
  }

  static bool isPlatformRole(String role) =>
      canonicalRoleName(role) == 'super_admin';
}
