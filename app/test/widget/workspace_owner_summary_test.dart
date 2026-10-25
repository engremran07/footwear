import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/models/tenant_model.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/tenant_provider.dart';
import 'package:footwear_erp/screens/tenant_management_screen.dart';

void main() {
  testWidgets(
    'selected super-admin sees live workspace owner, role counts, and seats',
    (tester) async {
      final now = Timestamp.now();
      final tenant = TenantModel(
        id: 'workspace-1',
        name: 'Workspace One',
        slug: 'workspace-one',
        plan: 'free',
        activeUserCount: 3,
        maxActiveUsers: 10,
        ownerUserId: 'owner-1',
        createdAt: now,
        updatedAt: now,
      );
      final platformAdmin = UserModel(
        id: 'platform-admin',
        email: 'platform@example.com',
        displayName: 'Platform Admin',
        role: UserRole.superAdmin,
        active: true,
        activeWorkspaceId: tenant.id,
        activeWorkspaceReason: 'Workspace support review',
        activeWorkspaceSelectedAt: now,
        createdAt: now,
        updatedAt: now,
      );
      final users = [
        UserModel(
          id: 'owner-1',
          email: 'owner@example.com',
          displayName: 'Workspace Owner',
          role: UserRole.tenantAdmin,
          phone: '+966501234567',
          tenantId: tenant.id,
          active: true,
          emailVerified: true,
          createdAt: now,
          updatedAt: now,
        ),
        UserModel(
          id: 'legacy-admin',
          email: 'admin@example.com',
          displayName: 'Legacy Admin',
          role: UserRole.admin,
          tenantId: tenant.id,
          active: true,
          createdAt: now,
          updatedAt: now,
        ),
        UserModel(
          id: 'seller-1',
          email: 'seller@example.com',
          displayName: 'Route Seller',
          role: UserRole.seller,
          tenantId: tenant.id,
          active: true,
          createdAt: now,
          updatedAt: now,
        ),
        UserModel(
          id: 'inactive-seller',
          email: 'inactive@example.com',
          displayName: 'Inactive Seller',
          role: UserRole.seller,
          tenantId: tenant.id,
          active: false,
          createdAt: now,
          updatedAt: now,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith((ref) => Stream.value(platformAdmin)),
            tenantsProvider.overrideWith((ref) => Stream.value([tenant])),
            tenantWorkspaceUsersProvider.overrideWith(
              (ref, tenantId) => Stream.value(users),
            ),
          ],
          child: const MaterialApp(home: TenantManagementScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Free tier'), findsOneWidget);
      expect(find.text('3 / 10'), findsOneWidget);
      expect(find.text('Workspace Owner'), findsOneWidget);
      expect(find.text('owner@example.com'), findsOneWidget);
      expect(find.text('+966501234567'), findsOneWidget);
      expect(find.text('Email verified'), findsOneWidget);
      expect(find.textContaining('Active users: 3'), findsOneWidget);
      expect(find.textContaining('Inactive users: 1'), findsOneWidget);
      expect(find.textContaining('Workspace admins: 2'), findsOneWidget);
      expect(find.textContaining('Sellers: 1'), findsOneWidget);
      expect(find.textContaining('Seats remaining: 7'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('workspace owner PII stays hidden without support context', (
    tester,
  ) async {
    final now = Timestamp.now();
    final tenant = TenantModel(
      id: 'workspace-1',
      name: 'Workspace One',
      slug: 'workspace-one',
      plan: 'free',
      activeUserCount: 1,
      maxActiveUsers: 10,
      ownerUserId: 'owner-1',
      createdAt: now,
      updatedAt: now,
    );
    final platformAdmin = UserModel(
      id: 'platform-admin',
      email: 'platform@example.com',
      displayName: 'Platform Admin',
      role: UserRole.superAdmin,
      active: true,
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(platformAdmin)),
          tenantsProvider.overrideWith((ref) => Stream.value([tenant])),
          tenantWorkspaceUsersProvider.overrideWith(
            (ref, tenantId) => Stream.value([
              UserModel(
                id: 'owner-1',
                email: 'owner@example.com',
                displayName: 'Workspace Owner',
                role: UserRole.tenantAdmin,
                tenantId: tenant.id,
                active: true,
                createdAt: now,
                updatedAt: now,
              ),
            ]),
          ),
        ],
        child: const MaterialApp(home: TenantManagementScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 / 10'), findsOneWidget);
    expect(find.text('Workspace Owner'), findsNothing);
    expect(find.text('owner@example.com'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
