import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/settings_model.dart';
import 'package:footwear_erp/models/route_model.dart';
import 'package:footwear_erp/models/shop_model.dart';
import 'package:footwear_erp/models/transaction_model.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/core/l10n/financial_document_localization.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/route_provider.dart';
import 'package:footwear_erp/providers/settings_provider.dart';
import 'package:footwear_erp/providers/shop_provider.dart';
import 'package:footwear_erp/providers/transaction_provider.dart';
import 'package:footwear_erp/providers/user_provider.dart';
import 'package:footwear_erp/screens/shops_list_screen.dart';
import 'package:footwear_erp/widgets/shimmer_loading.dart';

void main() {
  testWidgets('currency-filtered shops wait for route scope data', (
    tester,
  ) async {
    final now = Timestamp.now();
    final user = UserModel(
      id: 'admin-1',
      email: 'admin@example.com',
      displayName: 'Admin',
      role: UserRole.admin,
      tenantId: 'tenant-1',
      active: true,
      createdAt: now,
      updatedAt: now,
    );
    final shop = ShopModel(
      id: 'shop-1',
      name: 'Unscoped Shop',
      routeId: '',
      routeNumber: 0,
      balance: 10,
      active: true,
      createdBy: user.id,
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(user)),
          routesProvider.overrideWith(
            (ref) => const Stream<List<RouteModel>>.empty(),
          ),
          shopsProvider.overrideWith((ref) => Stream.value([shop])),
          shopsAnalyticsTransactionsProvider.overrideWith(
            (ref) => const Stream.empty(),
          ),
        ],
        child: const MaterialApp(home: ShopsListScreen(filterCurrency: 'PKR')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(ShimmerLoading), findsOneWidget);
    expect(find.text('Unscoped Shop'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shop flow totals stay currency-scoped and unabridged', (
    tester,
  ) async {
    final now = Timestamp.now();
    final user = UserModel(
      id: 'admin-1',
      email: 'admin@example.com',
      displayName: 'Admin',
      role: UserRole.admin,
      tenantId: 'tenant-1',
      active: true,
      createdAt: now,
      updatedAt: now,
    );
    RouteModel route(String id, String currency) => RouteModel(
      id: id,
      routeNumber: 1,
      name: id,
      totalShops: 1,
      currency: currency,
      active: true,
      createdBy: user.id,
      createdAt: now,
      updatedAt: now,
    );
    ShopModel shop(String id, String routeId, double balance) => ShopModel(
      id: id,
      name: id,
      routeId: routeId,
      routeNumber: 1,
      balance: balance,
      active: true,
      createdBy: user.id,
      createdAt: now,
      updatedAt: now,
    );
    TransactionModel transaction(
      String id,
      String shopId,
      String routeId,
      String type,
      double amount,
    ) => TransactionModel(
      id: id,
      shopId: shopId,
      shopName: shopId,
      routeId: routeId,
      type: type,
      amount: amount,
      createdBy: user.id,
      createdAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(user)),
          routesProvider.overrideWith(
            (ref) => Stream.value([
              route('sar-route', 'SAR'),
              route('pkr-route', 'PKR'),
            ]),
          ),
          shopsProvider.overrideWith(
            (ref) => Stream.value([
              shop('sar-shop', 'sar-route', 22500),
              shop('pkr-shop', 'pkr-route', 2500000),
            ]),
          ),
          settingsProvider.overrideWith(
            (ref) => Stream.value(
              SettingsModel(
                currency: 'SAR',
                pairsPerCarton: 12,
                updatedAt: now,
              ),
            ),
          ),
          shopsAnalyticsTransactionsProvider.overrideWith(
            (ref) => Stream.value([
              transaction(
                'sar-in',
                'sar-shop',
                'sar-route',
                TransactionModel.typeCashIn,
                1234567,
              ),
              transaction(
                'pkr-out',
                'pkr-shop',
                'pkr-route',
                TransactionModel.typeCashOut,
                2500000,
              ),
            ]),
          ),
        ],
        child: const MaterialApp(home: ShopsListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('SAR 1,234,567'), findsOneWidget);
    expect(find.textContaining('PKR 0'), findsOneWidget);
    expect(find.textContaining('SAR 0'), findsOneWidget);
    expect(find.textContaining('PKR 2,500,000'), findsNWidgets(2));
    expect(find.textContaining('SAR 22,500'), findsOneWidget);
    expect(find.textContaining('M'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('multi-shop statement export offers Arabic and Urdu', (
    tester,
  ) async {
    final now = Timestamp.now();
    final user = UserModel(
      id: 'admin-1',
      email: 'admin@example.com',
      displayName: 'Admin',
      role: UserRole.admin,
      tenantId: 'tenant-1',
      active: true,
      createdAt: now,
      updatedAt: now,
    );
    final route = RouteModel(
      id: 'route-1',
      routeNumber: 1,
      name: 'Route 1',
      totalShops: 1,
      currency: 'SAR',
      active: true,
      createdBy: user.id,
      createdAt: now,
      updatedAt: now,
    );
    final shop = ShopModel(
      id: 'shop-1',
      name: 'Test Shop',
      routeId: route.id,
      routeNumber: route.routeNumber,
      balance: 0,
      active: true,
      createdBy: user.id,
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(user)),
          routesProvider.overrideWith((ref) => Stream.value([route])),
          shopsProvider.overrideWith((ref) => Stream.value([shop])),
          shopsExportProvider.overrideWith((ref) async => [shop]),
          routesExportProvider.overrideWith((ref) async => [route]),
          settingsProvider.overrideWith(
            (ref) => Stream.value(
              SettingsModel(
                currency: 'SAR',
                pairsPerCarton: 12,
                invoiceHeader: const InvoiceHeaderConfig(
                  documentLanguagePair:
                      FinancialDocumentLanguagePair.englishUrdu,
                ),
                updatedAt: now,
              ),
            ),
          ),
          shopsAnalyticsTransactionsProvider.overrideWith(
            (ref) => const Stream<List<TransactionModel>>.empty(),
          ),
          allTransactionsExportProvider.overrideWith(
            (ref) async => const <TransactionModel>[],
          ),
          allUsersExportProvider.overrideWith(
            (ref) async => const <UserModel>[],
          ),
        ],
        child: const MaterialApp(home: ShopsListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Export Report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PDF Ledger'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    final selector = find.byKey(
      const ValueKey('export_document_language_selector'),
    );
    expect(selector, findsOneWidget);
    expect(
      tester
          .widget<SegmentedButton<FinancialDocumentLanguagePair>>(selector)
          .selected,
      {FinancialDocumentLanguagePair.englishUrdu},
    );

    await tester.tap(find.text('Arabic'));
    await tester.pump();
    expect(
      tester
          .widget<SegmentedButton<FinancialDocumentLanguagePair>>(selector)
          .selected,
      {FinancialDocumentLanguagePair.englishArabic},
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('all-shops export uses the complete export dataset', (
    tester,
  ) async {
    final now = Timestamp.now();
    final user = UserModel(
      id: 'admin-1',
      email: 'admin@example.com',
      displayName: 'Admin',
      role: UserRole.admin,
      tenantId: 'tenant-1',
      active: true,
      createdAt: now,
      updatedAt: now,
    );
    final route = RouteModel(
      id: 'route-1',
      routeNumber: 1,
      name: 'Route 1',
      totalShops: 3,
      currency: 'SAR',
      active: true,
      createdBy: user.id,
      createdAt: now,
      updatedAt: now,
    );
    ShopModel shop(String id) => ShopModel(
      id: id,
      name: id,
      routeId: route.id,
      routeNumber: route.routeNumber,
      balance: 0,
      active: true,
      createdBy: user.id,
      createdAt: now,
      updatedAt: now,
    );
    final completeShops = [shop('Shop 1'), shop('Shop 2'), shop('Shop 3')];
    var exportLoads = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(user)),
          shopsProvider.overrideWith(
            (ref) => Stream.value([completeShops.first]),
          ),
          routesProvider.overrideWith((ref) => Stream.value([route])),
          shopsAnalyticsTransactionsProvider.overrideWith(
            (ref) => Stream.value(const <TransactionModel>[]),
          ),
          settingsProvider.overrideWith(
            (ref) => Stream.value(
              SettingsModel(
                currency: 'SAR',
                pairsPerCarton: 12,
                updatedAt: now,
              ),
            ),
          ),
          shopsExportProvider.overrideWith((ref) async {
            exportLoads++;
            return completeShops;
          }),
          routesExportProvider.overrideWith((ref) async => [route]),
        ],
        child: const MaterialApp(home: ShopsListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Export Report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export All Shops'));
    await tester.pumpAndSettle();

    expect(find.text('3 records'), findsOneWidget);
    expect(exportLoads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('seller all-routes PDF uses only assigned route transactions', (
    tester,
  ) async {
    final now = Timestamp.now();
    final seller = UserModel(
      id: 'seller-1',
      email: 'seller@example.com',
      displayName: 'Seller',
      role: UserRole.seller,
      tenantId: 'tenant-1',
      assignedRouteIds: const ['route-1', 'route-2'],
      active: true,
      createdAt: now,
      updatedAt: now,
    );
    RouteModel route(String id, int number) => RouteModel(
      id: id,
      routeNumber: number,
      name: 'Route $number',
      totalShops: 1,
      assignedSellerIds: [seller.id],
      currency: 'SAR',
      active: true,
      createdBy: seller.id,
      createdAt: now,
      updatedAt: now,
    );
    final routes = [route('route-1', 1), route('route-2', 2)];
    ShopModel shop(String id, RouteModel assignedRoute) => ShopModel(
      id: id,
      name: id,
      routeId: assignedRoute.id,
      routeNumber: assignedRoute.routeNumber,
      balance: 25,
      active: true,
      createdBy: seller.id,
      createdAt: now,
      updatedAt: now,
    );
    final completeShops = [
      shop('Shop 1', routes[0]),
      shop('Shop 2', routes[1]),
    ];
    final routeTransactionCalls = <String>[];
    var allTransactionExportCalls = 0;
    var shopExportCalls = 0;
    TransactionModel transaction(
      RouteModel assignedRoute,
      ShopModel assignedShop,
    ) => TransactionModel(
      id: 'tx-${assignedRoute.id}',
      shopId: assignedShop.id,
      shopName: assignedShop.name,
      routeId: assignedRoute.id,
      type: TransactionModel.typeCashOut,
      amount: 25,
      createdBy: seller.id,
      createdAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(seller)),
          sellerAllShopsProvider.overrideWith(
            (ref) => Stream.value([completeShops.first]),
          ),
          routesBySellerProvider.overrideWith(
            (ref, sellerId) => Stream.value(routes),
          ),
          shopsAnalyticsTransactionsProvider.overrideWith(
            (ref) => Stream.value(const <TransactionModel>[]),
          ),
          settingsProvider.overrideWith(
            (ref) => Stream.value(
              SettingsModel(
                currency: 'SAR',
                pairsPerCarton: 12,
                updatedAt: now,
              ),
            ),
          ),
          shopsExportProvider.overrideWith((ref) async {
            shopExportCalls++;
            return completeShops;
          }),
          routesExportProvider.overrideWith((ref) async => routes),
          routeTransactionsExportProvider.overrideWith((ref, routeId) async {
            routeTransactionCalls.add(routeId);
            final index = routes.indexWhere(
              (candidate) => candidate.id == routeId,
            );
            return [transaction(routes[index], completeShops[index])];
          }),
          allTransactionsExportProvider.overrideWith((ref) async {
            allTransactionExportCalls++;
            return const <TransactionModel>[];
          }),
        ],
        child: const MaterialApp(home: ShopsListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Export Report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PDF Ledger'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(routeTransactionCalls.toSet(), {'route-1', 'route-2'});
    expect(allTransactionExportCalls, 0);
    expect(shopExportCalls, 1);
    expect(find.text('2 records'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
