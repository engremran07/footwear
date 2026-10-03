import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/models/tenant_model.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/dashboard_provider.dart';
import 'package:footwear_erp/providers/tenant_provider.dart';
import 'package:footwear_erp/providers/user_provider.dart';

void main() {
  testWidgets(
    'root super-admin dashboard does not wait for workspace user list',
    (tester) async {
      final user = UserModel(
        id: 'platform-admin',
        email: 'platform@example.com',
        displayName: 'Platform Admin',
        role: UserRole.superAdmin,
        active: true,
        createdAt: Timestamp.now(),
        updatedAt: Timestamp.now(),
      );
      final workspace = TenantModel(
        id: 'workspace-1',
        name: 'Workspace One',
        slug: 'workspace-one',
        createdAt: Timestamp.now(),
        updatedAt: Timestamp.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith((ref) => Stream.value(user)),
            tenantsProvider.overrideWith((ref) => Stream.value([workspace])),
            allUsersProvider.overrideWith(
              (ref) => const Stream<List<UserModel>>.empty(),
            ),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                final stats = ref.watch(dashboardStatsProvider);
                return Scaffold(
                  body: Center(
                    child: Text(
                      stats.when(
                        data: (value) => '${value.totalWorkspaces}',
                        loading: () => 'loading',
                        error: (_, _) => 'error',
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
      expect(find.text('loading'), findsNothing);
    },
  );

  testWidgets(
    'selected-workspace super-admin dashboard still shows scoped user count',
    (tester) async {
      final user = UserModel(
        id: 'platform-admin',
        email: 'platform@example.com',
        displayName: 'Platform Admin',
        role: UserRole.superAdmin,
        activeWorkspaceId: 'workspace-1',
        active: true,
        createdAt: Timestamp.now(),
        updatedAt: Timestamp.now(),
      );
      final workspace = TenantModel(
        id: 'workspace-1',
        name: 'Workspace One',
        slug: 'workspace-one',
        createdAt: Timestamp.now(),
        updatedAt: Timestamp.now(),
      );
      final workspaceUser = UserModel(
        id: 'workspace-admin',
        email: 'admin@example.com',
        displayName: 'Workspace Admin',
        role: UserRole.tenantAdmin,
        tenantId: 'workspace-1',
        active: true,
        createdAt: Timestamp.now(),
        updatedAt: Timestamp.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith((ref) => Stream.value(user)),
            tenantsProvider.overrideWith((ref) => Stream.value([workspace])),
            allUsersProvider.overrideWith(
              (ref) => Stream.value([workspaceUser]),
            ),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                final stats = ref.watch(dashboardStatsProvider);
                return Scaffold(
                  body: Center(
                    child: Text(
                      stats.when(
                        data: (value) => '${value.totalUsers}',
                        loading: () => 'loading',
                        error: (_, _) => 'error',
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
    },
  );
}
