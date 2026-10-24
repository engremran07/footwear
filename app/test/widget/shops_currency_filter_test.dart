import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/route_model.dart';
import 'package:footwear_erp/models/shop_model.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/route_provider.dart';
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
}
