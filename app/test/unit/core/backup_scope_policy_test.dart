import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/utils/backup_scope_policy.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  test(
    'platform backups contain only workspace metadata and user profiles',
    () {
      expect(
        BackupScopePolicy.scopeFor(UserRole.superAdmin),
        BackupScope.platformMetadata,
      );
      expect(BackupScopePolicy.collectionsFor(UserRole.superAdmin), {
        'workspaces',
        'users',
      });
    },
  );

  test('tenant-admin backups cover workspace data but not user accounts', () {
    expect(
      BackupScopePolicy.scopeFor(UserRole.tenantAdmin),
      BackupScope.workspaceBusiness,
    );
    expect(BackupScopePolicy.collectionsFor(UserRole.tenantAdmin), {
      'routes',
      'shops',
      'products',
      'inventory',
      'transactions',
      'invoices',
      'settings',
    });
  });

  test('workspace archives allow every expanded collection they serialize', () {
    expect(BackupScopePolicy.archiveCollectionsFor(UserRole.tenantAdmin), {
      'routes',
      'shops',
      'products',
      'product_variants',
      'seller_inventory',
      'inventory_transactions',
      'transactions',
      'invoices',
      'settings',
    });
  });

  test('seller backups contain only assigned-route business records', () {
    expect(
      BackupScopePolicy.scopeFor(UserRole.seller),
      BackupScope.sellerRoute,
    );
    expect(BackupScopePolicy.archiveScopeFor(UserRole.seller), 'seller_route');
    expect(BackupScopePolicy.collectionsFor(UserRole.seller), {
      'routes',
      'shops',
      'inventory',
      'transactions',
      'invoices',
    });
  });

  test(
    'seller archives allow serialized route data without workspace records',
    () {
      expect(BackupScopePolicy.archiveCollectionsFor(UserRole.seller), {
        'routes',
        'shops',
        'seller_inventory',
        'inventory_transactions',
        'transactions',
        'invoices',
      });
      expect(
        BackupScopePolicy.archiveCollectionsFor(UserRole.seller),
        isNot(contains('products')),
      );
      expect(
        BackupScopePolicy.archiveCollectionsFor(UserRole.seller),
        isNot(contains('settings')),
      );
    },
  );

  test('admin-equivalent accounts can back up workspaces, not supervisors', () {
    expect(
      BackupScopePolicy.scopeFor(UserRole.admin),
      BackupScope.workspaceBusiness,
    );
    expect(
      BackupScopePolicy.collectionsFor(UserRole.admin),
      BackupScopePolicy.workspaceBusinessCollections,
    );
    expect(
      BackupScopePolicy.scopeFor(UserRole.supervisor),
      BackupScope.disabled,
    );
    expect(BackupScopePolicy.collectionsFor(UserRole.supervisor), isEmpty);
  });

  test(
    'seller restore accepts only own unlinked cash rows in current scope',
    () {
      final document = <String, dynamic>{
        '__id': 'tx-1',
        'tenant_id': 'tenant-1',
        'route_id': 'route-1',
        'created_by': 'seller-1',
        'shop_id': 'shop-1',
        'type': 'cash_in',
        'amount': 25,
        'items': <Object>[],
        'created_at': Timestamp.fromMillisecondsSinceEpoch(0),
      };

      bool eligible([Map<String, dynamic>? override]) =>
          BackupScopePolicy.isSellerTransactionRestorable(
            document: {...document, ...?override},
            sellerId: 'seller-1',
            routeId: 'route-1',
            tenantId: 'tenant-1',
            assignedRouteIds: {'route-1'},
          );

      expect(eligible(), isTrue);
      expect(eligible({'created_by': 'seller-2'}), isFalse);
      expect(eligible({'route_id': 'route-2'}), isFalse);
      expect(eligible({'tenant_id': 'tenant-2'}), isFalse);
      expect(eligible({'invoice_id': 'invoice-1'}), isFalse);
      expect(eligible({'invoice_number': 'INV-1'}), isFalse);
      expect(eligible({'deleted': true}), isFalse);
      expect(eligible({'edit_request_pending': true}), isFalse);
      expect(
        eligible({
          'items': <Object>[
            {'variant_id': 'variant-1'},
          ],
        }),
        isFalse,
      );
      expect(eligible({'amount': double.nan}), isFalse);
      expect(
        BackupScopePolicy.isSellerTransactionRestorable(
          document: {...document, '__id': ''},
          sellerId: 'seller-1',
          routeId: 'route-1',
          tenantId: 'tenant-1',
          assignedRouteIds: {'route-1'},
        ),
        isFalse,
      );
    },
  );

  test('seller archives reject inventory records owned by another seller', () {
    expect(
      BackupScopePolicy.isSellerOwnedArchiveRecord(
        document: {'seller_id': 'seller-1'},
        sellerId: 'seller-1',
      ),
      isTrue,
    );
    expect(
      BackupScopePolicy.isSellerOwnedArchiveRecord(
        document: {'seller_id': 'seller-2'},
        sellerId: 'seller-1',
      ),
      isFalse,
    );
    expect(
      BackupScopePolicy.isSellerOwnedArchiveRecord(
        document: const {},
        sellerId: ' ',
      ),
      isFalse,
    );
  });

  test(
    'recognizes all canonical super-admin aliases for profile filtering',
    () {
      expect(BackupScopePolicy.isPlatformRole('super_admin'), isTrue);
      expect(BackupScopePolicy.isPlatformRole(' SuperAdmin '), isTrue);
      expect(BackupScopePolicy.isPlatformRole('tenant_admin'), isFalse);
    },
  );

  test('backup access is limited to the currently selected workspace', () {
    expect(
      BackupScopePolicy.requireSelectedWorkspace(
        activeWorkspaceId: 'tenant-1',
        requestedWorkspaceId: 'tenant-1',
      ),
      'tenant-1',
    );
    expect(
      () => BackupScopePolicy.requireSelectedWorkspace(
        activeWorkspaceId: 'tenant-1',
        requestedWorkspaceId: 'tenant-2',
      ),
      throwsStateError,
    );
    expect(
      () => BackupScopePolicy.requireSelectedWorkspace(activeWorkspaceId: null),
      throwsStateError,
    );
  });

  test('backup access rejects the global placeholder as a workspace', () {
    expect(
      () => BackupScopePolicy.requireSelectedWorkspace(
        activeWorkspaceId: '__global__',
      ),
      throwsStateError,
    );
    expect(
      () => BackupScopePolicy.requireSelectedWorkspace(
        activeWorkspaceId: 'tenant-1',
        requestedWorkspaceId: 'global',
      ),
      throwsStateError,
    );
  });
}
