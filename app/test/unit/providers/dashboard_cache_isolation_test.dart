import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/dashboard_provider.dart';
import 'package:footwear_erp/providers/product_provider.dart';
import 'package:footwear_erp/providers/route_provider.dart';
import 'package:footwear_erp/providers/shop_provider.dart';

void main() {
  testWidgets(
    'does not show cached dashboard metrics from another workspace',
    (tester) async {
      final now = Timestamp.now();
      final workspaceAAdmin = UserModel(
        id: 'admin-a',
        email: 'admin-a@example.com',
        displayName: 'Workspace A Admin',
        role: UserRole.admin,
        tenantId: 'workspace-a',
        active: true,
        createdAt: now,
        updatedAt: now,
      );
      final workspaceBAdmin = UserModel(
        id: 'admin-b',
        email: 'admin-b@example.com',
        displayName: 'Workspace B Admin',
        role: UserRole.admin,
        tenantId: 'workspace-b',
        active: true,
        createdAt: now,
        updatedAt: now,
      );
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(_TestFirebaseUser(workspaceBAdmin.id)),
          ),
          authUserProvider.overrideWith((ref) => Stream.value(workspaceBAdmin)),
          routesProvider.overrideWith((ref) => const Stream.empty()),
          shopsProvider.overrideWith((ref) => const Stream.empty()),
          productsProvider.overrideWith((ref) => const Stream.empty()),
          allVariantsProvider.overrideWith((ref) => const Stream.empty()),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(lastGoodDashboardStatsProvider.notifier)
          .setForUser(
            workspaceAAdmin,
            const DashboardStats(totalRoutes: 11, totalShops: 22),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                final stats = ref.watch(dashboardStatsProvider);
                return Scaffold(
                  body: Center(
                    child: Text(
                      stats.when(
                        data: (value) =>
                            'metrics:${value.totalRoutes}/${value.totalShops}',
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
      await tester.pump();

      expect(find.text('metrics:11/22'), findsNothing);
      expect(find.text('loading'), findsOneWidget);
    },
  );

  testWidgets(
    'keeps cached metrics while the same workspace streams refresh',
    (tester) async {
      final now = Timestamp.now();
      final workspaceAdmin = UserModel(
        id: 'admin-a',
        email: 'admin-a@example.com',
        displayName: 'Workspace Admin',
        role: UserRole.admin,
        tenantId: 'workspace-a',
        active: true,
        createdAt: now,
        updatedAt: now,
      );
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(_TestFirebaseUser(workspaceAdmin.id)),
          ),
          authUserProvider.overrideWith((ref) => Stream.value(workspaceAdmin)),
          routesProvider.overrideWith((ref) => const Stream.empty()),
          shopsProvider.overrideWith((ref) => const Stream.empty()),
          productsProvider.overrideWith((ref) => const Stream.empty()),
          allVariantsProvider.overrideWith((ref) => const Stream.empty()),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(lastGoodDashboardStatsProvider.notifier)
          .setForUser(
            workspaceAdmin,
            const DashboardStats(totalRoutes: 11, totalShops: 22),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                final stats = ref.watch(dashboardStatsProvider);
                return Scaffold(
                  body: Center(
                    child: Text(
                      stats.when(
                        data: (value) =>
                            'metrics:${value.totalRoutes}/${value.totalShops}',
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
      await tester.pump();

      expect(find.text('metrics:11/22'), findsOneWidget);
    },
  );
}

class _TestFirebaseUser implements User {
  @override
  final String uid;

  _TestFirebaseUser(this.uid);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
