import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/utils/permission_policy.dart';
import 'package:footwear_erp/core/utils/role_names.dart';
import 'package:footwear_erp/models/user_model.dart';

void main() {
  final now = DateTime.utc(2026, 10, 27, 10);
  final createdAt = Timestamp.fromDate(now);

  UserModel user({
    required UserRole role,
    String? tenantId = 'workspace-a',
    String? activeWorkspaceId,
    String? supportReason,
    Timestamp? selectedAt,
    bool active = true,
    List<String> assignedRouteIds = const [],
  }) => UserModel(
    id: 'user-1',
    email: 'user@example.test',
    displayName: 'Test User',
    role: role,
    tenantId: tenantId,
    activeWorkspaceId: activeWorkspaceId,
    activeWorkspaceReason: supportReason,
    activeWorkspaceSelectedAt: selectedAt,
    active: active,
    createdAt: createdAt,
    updatedAt: createdAt,
    assignedRouteIds: assignedRouteIds,
  );

  group('RoleCapabilities', () {
    test('canonical role aliases share one capability policy', () {
      expect(
        RoleCapabilities.allows('manager', AppCapability.writeOff),
        isTrue,
      );
      expect(
        RoleCapabilities.allows('tenant-admin', AppCapability.manageUsers),
        isTrue,
      );
      expect(
        RoleCapabilities.allows('super-admin', AppCapability.manageWorkspaces),
        isTrue,
      );
    });

    test('notifications are limited to workspace admins and supervisors', () {
      for (final role in ['admin', 'tenant_admin']) {
        expect(
          RoleCapabilities.allows(role, AppCapability.viewNotifications),
          isTrue,
        );
      }
      expect(
        RoleCapabilities.allows('supervisor', AppCapability.viewNotifications),
        isTrue,
      );
      expect(
        RoleCapabilities.allows('super_admin', AppCapability.viewNotifications),
        isFalse,
      );
    });

    test('workspace admins can view the disabled data maintenance screen', () {
      for (final role in [UserRole.admin, UserRole.tenantAdmin]) {
        final account = user(role: role);
        expect(
          PermissionPolicy.can(account, AppCapability.viewDataMaintenance),
          isTrue,
        );
        expect(
          PermissionPolicy.can(account, AppCapability.manageDataMaintenance),
          isFalse,
        );
      }
      expect(
        PermissionPolicy.can(
          user(role: UserRole.supervisor),
          AppCapability.viewDataMaintenance,
        ),
        isFalse,
      );
    });

    test(
      'invoice creation capabilities are consistent across business roles',
      () {
        for (final role in [
          UserRole.admin,
          UserRole.tenantAdmin,
          UserRole.supervisor,
          UserRole.seller,
        ]) {
          final account = user(role: role);
          expect(
            PermissionPolicy.can(
              account,
              AppCapability.createInvoice,
              now: now,
            ),
            isTrue,
            reason: '$role must be able to create sale invoices',
          );
          expect(
            PermissionPolicy.can(
              account,
              AppCapability.createCashReceipt,
              now: now,
            ),
            isTrue,
            reason: '$role must be able to create cash receipts',
          );
        }

        final supervisor = user(role: UserRole.supervisor);
        final seller = user(role: UserRole.seller);
        expect(
          PermissionPolicy.can(
            supervisor,
            AppCapability.settleInvoice,
            now: now,
          ),
          isFalse,
        );
        expect(
          PermissionPolicy.can(seller, AppCapability.settleInvoice, now: now),
          isFalse,
        );
        expect(
          PermissionPolicy.can(
            seller,
            AppCapability.createCashReceipt,
            tenantId: 'workspace-b',
            now: now,
          ),
          isFalse,
        );
      },
    );

    test('supervisors can create invoices but not financial corrections', () {
      final supervisor = user(role: UserRole.supervisor);

      expect(
        PermissionPolicy.can(
          supervisor,
          AppCapability.viewNotifications,
          now: now,
        ),
        isTrue,
      );
      expect(
        PermissionPolicy.can(supervisor, AppCapability.viewReports, now: now),
        isTrue,
      );
      expect(
        PermissionPolicy.can(supervisor, AppCapability.createInvoice, now: now),
        isTrue,
      );
      expect(
        PermissionPolicy.can(
          supervisor,
          AppCapability.createCashReceipt,
          now: now,
        ),
        isTrue,
      );
      expect(
        PermissionPolicy.can(supervisor, AppCapability.writeOff, now: now),
        isFalse,
      );
      expect(
        PermissionPolicy.can(supervisor, AppCapability.creditNote, now: now),
        isFalse,
      );
      expect(
        PermissionPolicy.can(supervisor, AppCapability.voidInvoice, now: now),
        isFalse,
      );
      expect(
        PermissionPolicy.can(supervisor, AppCapability.manageBackup, now: now),
        isFalse,
      );
    });

    test('operational write permissions use action-specific capabilities', () {
      for (final capability in [
        AppCapability.manageRoutes,
        AppCapability.manageProducts,
        AppCapability.manageInventory,
      ]) {
        expect(
          RoleCapabilities.allows('supervisor', capability),
          isTrue,
          reason: 'supervisors must be allowed to $capability',
        );
        expect(
          RoleCapabilities.allows('seller', capability),
          isFalse,
          reason: 'sellers must not be allowed to $capability',
        );
      }
    });

    test('role assignment is limited to the permitted target roles', () {
      final legacyAdmin = user(role: UserRole.admin);
      final tenantAdmin = user(role: UserRole.tenantAdmin);

      expect(
        PermissionPolicy.can(
          legacyAdmin,
          AppCapability.manageUsers,
          targetRole: 'seller',
          now: now,
        ),
        isTrue,
      );
      expect(
        PermissionPolicy.can(
          legacyAdmin,
          AppCapability.manageUsers,
          targetRole: 'supervisor',
          now: now,
        ),
        isFalse,
      );
      expect(
        PermissionPolicy.can(
          tenantAdmin,
          AppCapability.createSupervisor,
          now: now,
        ),
        isTrue,
      );
      expect(
        PermissionPolicy.can(
          tenantAdmin,
          AppCapability.manageUsers,
          targetRole: 'admin',
          now: now,
        ),
        isFalse,
      );
    });
  });

  group('PermissionPolicy tenant context', () {
    test('inactive and cross-workspace profiles are denied', () {
      final inactive = user(role: UserRole.tenantAdmin, active: false);
      final tenantAdmin = user(role: UserRole.tenantAdmin);

      expect(
        PermissionPolicy.can(inactive, AppCapability.manageSettings, now: now),
        isFalse,
      );
      expect(
        PermissionPolicy.can(
          tenantAdmin,
          AppCapability.viewNotifications,
          tenantId: 'workspace-b',
          now: now,
        ),
        isFalse,
      );
    });

    test('super-admin business access requires a current audited context', () {
      final unselected = user(role: UserRole.superAdmin, tenantId: null);
      final selectedAt = Timestamp.fromDate(
        now.subtract(const Duration(hours: 1)),
      );
      final selected = user(
        role: UserRole.superAdmin,
        tenantId: null,
        activeWorkspaceId: 'workspace-a',
        supportReason: 'Investigating a reported issue',
        selectedAt: selectedAt,
      );

      expect(
        PermissionPolicy.can(
          unselected,
          AppCapability.manageWorkspaces,
          now: now,
        ),
        isTrue,
      );
      expect(
        PermissionPolicy.can(
          unselected,
          AppCapability.viewNotifications,
          now: now,
        ),
        isFalse,
      );
      expect(
        PermissionPolicy.can(
          selected,
          AppCapability.viewNotifications,
          now: now,
        ),
        isFalse,
      );
      expect(
        PermissionPolicy.can(selected, AppCapability.createInvoice, now: now),
        isTrue,
      );
      expect(
        PermissionPolicy.can(
          selected,
          AppCapability.createCashReceipt,
          now: now,
        ),
        isTrue,
      );
      expect(
        PermissionPolicy.can(
          selected,
          AppCapability.viewNotifications,
          now: now.add(const Duration(hours: 8)),
        ),
        isFalse,
      );
    });
  });

  group('PermissionPolicy routes', () {
    test('super-admin dashboard requires a current support context', () {
      final currentTime = DateTime.now();
      final unselected = user(role: UserRole.superAdmin, tenantId: null);
      final selectedAt = Timestamp.fromDate(
        currentTime.subtract(const Duration(hours: 1)),
      );
      final selected = user(
        role: UserRole.superAdmin,
        tenantId: null,
        activeWorkspaceId: 'workspace-a',
        supportReason: 'Investigating a reported issue',
        selectedAt: selectedAt,
      );

      expect(PermissionPolicy.canAccessRoute(unselected, '/'), isFalse);
      expect(PermissionPolicy.canAccessRoute(unselected, '/tenants'), isTrue);
      expect(
        PermissionPolicy.routeAccessDecision(unselected, '/routes'),
        RouteAccessDecision.workspaceSelectionRequired,
      );
      expect(
        PermissionPolicy.routeAccessDecision(unselected, '/unknown'),
        RouteAccessDecision.denied,
      );
      expect(
        PermissionPolicy.routeAccessDecision(unselected, '/tenants'),
        RouteAccessDecision.allowed,
      );
      expect(PermissionPolicy.canAccessRoute(selected, '/'), isTrue);
      final expired = user(
        role: UserRole.superAdmin,
        tenantId: null,
        activeWorkspaceId: 'workspace-a',
        supportReason: 'Investigating a reported issue',
        selectedAt: Timestamp.fromDate(
          currentTime.subtract(const Duration(hours: 9)),
        ),
      );
      expect(PermissionPolicy.canAccessRoute(expired, '/'), isFalse);
      expect(PermissionPolicy.canAccessRoute(expired, '/tenants'), isTrue);
      expect(
        PermissionPolicy.routeAccessDecision(expired, '/routes'),
        RouteAccessDecision.workspaceSelectionRequired,
      );
    });

    test('settings descendants are restricted to workspace administrators', () {
      final admin = user(role: UserRole.tenantAdmin);
      final supervisor = user(role: UserRole.supervisor);
      final rootSuperAdmin = user(role: UserRole.superAdmin, tenantId: null);

      expect(
        PermissionPolicy.canAccessRoute(rootSuperAdmin, '/settings'),
        isTrue,
      );
      expect(
        PermissionPolicy.canAccessRoute(
          rootSuperAdmin,
          '/settings/invoice-header',
        ),
        isFalse,
      );
      expect(
        PermissionPolicy.canAccessRoute(admin, '/settings/invoice-header'),
        isTrue,
      );
      expect(
        PermissionPolicy.canAccessRoute(supervisor, '/settings/invoice-header'),
        isFalse,
      );
    });

    test('seller and supervisor routes follow capability policy', () {
      final seller = user(
        role: UserRole.seller,
        assignedRouteIds: const ['route-1'],
      );
      final supervisor = user(role: UserRole.supervisor);

      expect(PermissionPolicy.canAccessRoute(seller, '/reports'), isFalse);
      expect(PermissionPolicy.canAccessRoute(seller, '/routes'), isFalse);
      expect(PermissionPolicy.canAccessRoute(seller, '/shops/new'), isTrue);
      expect(PermissionPolicy.canAccessRoute(seller, '/invoices/new'), isTrue);
      expect(
        PermissionPolicy.canAccessRoute(supervisor, '/invoices/new'),
        isTrue,
      );
      expect(
        PermissionPolicy.canAccessRoute(supervisor, '/notifications'),
        isTrue,
      );
      expect(
        PermissionPolicy.canAccessRoute(supervisor, '/settings/backup'),
        isFalse,
      );
      expect(PermissionPolicy.canAccessRoute(supervisor, '/unknown'), isFalse);
    });
  });
}
