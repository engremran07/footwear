import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/route_model.dart';
import 'package:footwear_erp/models/settings_model.dart';
import 'package:footwear_erp/models/shop_model.dart';
import 'package:footwear_erp/models/transaction_model.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/dashboard_provider.dart';
import 'package:footwear_erp/providers/route_provider.dart';
import 'package:footwear_erp/providers/settings_provider.dart';
import 'package:footwear_erp/providers/shop_provider.dart';
import 'package:footwear_erp/providers/transaction_provider.dart';
import 'package:footwear_erp/screens/dashboard_screen.dart';

void main() {
  testWidgets(
    'dashboard builds route analytics lazily without dropping later routes',
    (tester) async {
      tester.view.physicalSize = const Size(800, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = Timestamp.now();
      const routeCount = 150;
      final routes = List.generate(
        routeCount,
        (index) => RouteModel(
          id: 'route-$index',
          routeNumber: index,
          name: 'Route item ${index.toString().padLeft(3, '0')}',
          totalShops: 1,
          active: true,
          createdBy: 'admin',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final shops = List.generate(
        routeCount,
        (index) => ShopModel(
          id: 'shop-$index',
          name: 'Shop $index',
          routeId: 'route-$index',
          routeNumber: index,
          balance: routeCount - index.toDouble(),
          active: true,
          createdBy: 'admin',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final user = UserModel(
        id: 'admin',
        email: 'admin@example.com',
        displayName: 'Workspace Admin',
        role: UserRole.admin,
        tenantId: 'workspace-1',
        active: true,
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith((ref) => Stream.value(user)),
            dashboardStatsProvider.overrideWith(
              (ref) => const AsyncData(
                DashboardStats(totalRoutes: routeCount, totalShops: routeCount),
              ),
            ),
            routesProvider.overrideWith((ref) => Stream.value(routes)),
            shopsProvider.overrideWith((ref) => Stream.value(shops)),
            pendingEditRequestsProvider.overrideWith(
              (ref) => const Stream<List<TransactionModel>>.empty(),
            ),
            settingsProvider.overrideWith(
              (ref) => Stream.value(
                SettingsModel(
                  tenantId: 'workspace-1',
                  currency: 'SAR',
                  pairsPerCarton: 12,
                  updatedAt: now,
                ),
              ),
            ),
          ],
          child: const MaterialApp(home: DashboardScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CustomScrollView), findsOneWidget);
      final dashboardScrollable = find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first;

      await tester.scrollUntilVisible(
        find.text('Route item 000'),
        240,
        scrollable: dashboardScrollable,
      );
      expect(find.text('Route item 000'), findsOneWidget);
      expect(find.byType(ListTile).evaluate().length, lessThanOrEqualTo(12));

      await tester.scrollUntilVisible(
        find.text('Route item 149'),
        240,
        scrollable: dashboardScrollable,
      );
      expect(find.byType(ListTile).evaluate().length, lessThanOrEqualTo(12));
      expect(find.text('Route item 149'), findsOneWidget);
    },
  );
}
