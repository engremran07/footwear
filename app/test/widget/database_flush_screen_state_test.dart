import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/models/tenant_model.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/tenant_provider.dart';
import 'package:footwear_erp/screens/database_flush_screen.dart';

void main() {
  testWidgets('workspace admins see disabled component reset options', (
    tester,
  ) async {
    final now = Timestamp.now();
    final tenantAdmin = UserModel(
      id: 'tenant-admin',
      email: 'admin@example.com',
      displayName: 'Workspace Admin',
      role: UserRole.tenantAdmin,
      tenantId: 'tenant-1',
      active: true,
      createdAt: now,
      updatedAt: now,
    );
    final tenant = TenantModel(
      id: 'tenant-1',
      name: 'Workspace One',
      slug: 'workspace-one',
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(tenantAdmin)),
          tenantProvider(tenant.id).overrideWith((ref) => Stream.value(tenant)),
        ],
        child: const MaterialApp(home: DatabaseFlushScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Workspace data cleanup is disabled'), findsNothing);
    expect(find.text('Workspace One'), findsOneWidget);
    for (final title in [
      'Flush Financial Data',
      'Flush Inventory',
      'Flush Shops',
      'Flush Routes',
      'Flush Products',
      'Flush Product Variants',
      'Flush Invoices',
      'Flush Notifications',
      'Flush Users',
      'Flush User Data',
      'Full Database Reset',
      'Reset Settings',
    ]) {
      final tile = find.widgetWithText(ListTile, title);
      expect(tile, findsOneWidget, reason: title);
      expect(tester.widget<ListTile>(tile).enabled, isFalse, reason: title);
      expect(tester.widget<ListTile>(tile).onTap, isNull, reason: title);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'flush controls remain disabled while workspace metadata retries and loads',
    (tester) async {
      var tenantAttempts = 0;
      final now = Timestamp.now();
      final superAdmin = UserModel(
        id: 'platform-admin',
        email: 'admin@example.com',
        displayName: 'Platform Admin',
        role: UserRole.superAdmin,
        activeWorkspaceId: 'tenant-1',
        activeWorkspaceReason: 'Reviewing workspace maintenance access',
        activeWorkspaceSelectedAt: now,
        active: true,
        createdAt: now,
        updatedAt: now,
      );
      final tenant = TenantModel(
        id: 'tenant-1',
        name: 'Workspace One',
        slug: 'workspace-one',
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith((ref) => Stream.value(superAdmin)),
            tenantProvider(tenant.id).overrideWith((ref) {
              tenantAttempts += 1;
              return tenantAttempts == 1
                  ? Stream.error(StateError('workspace unavailable'))
                  : Stream.value(tenant);
            }),
          ],
          child: const MaterialApp(home: DatabaseFlushScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Workspace data cleanup is disabled because client-side deletes can '
          'leave invoices, balances, inventory, routes, and user profiles '
          'inconsistent. Use an encrypted backup and an approved, audited '
          'maintenance process.',
        ),
        findsOneWidget,
      );
      final financialTile = find.widgetWithText(
        ListTile,
        'Flush Financial Data',
      );
      expect(tester.widget<ListTile>(financialTile).enabled, isFalse);
      expect(tester.widget<ListTile>(financialTile).onTap, isNull);
      expect(find.byTooltip('Retry'), findsOneWidget);

      await tester.tap(find.byTooltip('Retry'));
      await tester.pumpAndSettle();

      expect(tenantAttempts, greaterThan(1));
      expect(find.text('Workspace One'), findsOneWidget);
      for (final title in [
        'Flush Financial Data',
        'Flush Inventory',
        'Flush Shops',
        'Flush Routes',
        'Flush Products',
        'Flush Product Variants',
        'Flush Invoices',
        'Flush Notifications',
        'Flush Users',
        'Flush User Data',
        'Full Database Reset',
        'Reset Settings',
      ]) {
        final tile = find.widgetWithText(ListTile, title);
        expect(tile, findsOneWidget, reason: title);
        expect(tester.widget<ListTile>(tile).enabled, isFalse, reason: title);
        expect(tester.widget<ListTile>(tile).onTap, isNull, reason: title);
      }
      expect(tester.takeException(), isNull);
    },
  );
}
