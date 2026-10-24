import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/settings_model.dart';
import 'package:footwear_erp/models/route_model.dart';
import 'package:footwear_erp/models/shop_model.dart';
import 'package:footwear_erp/models/transaction_model.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/route_provider.dart';
import 'package:footwear_erp/providers/settings_provider.dart';
import 'package:footwear_erp/providers/shop_provider.dart';
import 'package:footwear_erp/providers/transaction_provider.dart';
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
}
