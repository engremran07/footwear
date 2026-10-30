import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/shop_model.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/route_provider.dart';
import 'package:footwear_erp/providers/shop_provider.dart';
import 'package:footwear_erp/providers/transaction_provider.dart';
import 'package:footwear_erp/screens/shop_detail_screen.dart';
import 'package:footwear_erp/widgets/app_contextual_actions.dart';

void main() {
  final now = Timestamp.fromDate(DateTime.utc(2026, 10, 30));

  Future<void> pumpShopDetail(
    WidgetTester tester, {
    required UserRole role,
    List<String> assignedRouteIds = const [],
  }) async {
    final user = UserModel(
      id: 'user-1',
      email: 'user@example.test',
      displayName: 'Test User',
      role: role,
      tenantId: 'tenant-1',
      assignedRouteIds: assignedRouteIds,
      active: true,
      createdAt: now,
      updatedAt: now,
    );
    final shop = ShopModel(
      id: 'shop-1',
      name: 'Test Shop',
      routeId: 'route-1',
      routeNumber: 1,
      phone: '+966500000000',
      balance: 100,
      active: true,
      createdBy: user.id,
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(user)),
          shopDetailProvider('shop-1')
              .overrideWith((ref) => Stream.value(shop)),
          shopTransactionsProvider('shop-1')
              .overrideWith((ref) => Stream.value(const [])),
          routeCurrencyProvider('route-1').overrideWith((ref) => 'SAR'),
        ],
        child: const MaterialApp(home: ShopDetailScreen(shopId: 'shop-1')),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openShopActions(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('shop_detail_actions')));
    await tester.pumpAndSettle();
  }

  testWidgets('admin shop actions are in the contact card and preserved', (
    tester,
  ) async {
    await pumpShopDetail(tester, role: UserRole.admin);

    final actionButton = find.byKey(const ValueKey('shop_detail_actions'));
    expect(find.byType(AppContextualActions), findsOneWidget);
    expect(find.byType(AppContextualActionsButton), findsOneWidget);
    expect(
      find.ancestor(of: actionButton, matching: find.byType(Card)),
      findsOneWidget,
    );

    await openShopActions(tester);
    expect(find.text('Edit shop'), findsOneWidget);
    expect(find.text('Delete shop'), findsOneWidget);
    expect(find.text('Mark as Bad Debt'), findsOneWidget);
    expect(find.text('Export & Share'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('supervisors retain shop edit/export but not admin actions', (
    tester,
  ) async {
    await pumpShopDetail(tester, role: UserRole.supervisor);
    await openShopActions(tester);

    expect(find.text('Edit shop'), findsOneWidget);
    expect(find.text('Export & Share'), findsOneWidget);
    expect(find.text('Delete shop'), findsNothing);
    expect(find.text('Mark as Bad Debt'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('assigned sellers retain shop edit/export only', (tester) async {
    await pumpShopDetail(
      tester,
      role: UserRole.seller,
      assignedRouteIds: const ['route-1'],
    );
    await openShopActions(tester);

    expect(find.text('Edit shop'), findsOneWidget);
    expect(find.text('Export & Share'), findsOneWidget);
    expect(find.text('Delete shop'), findsNothing);
    expect(find.text('Mark as Bad Debt'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
