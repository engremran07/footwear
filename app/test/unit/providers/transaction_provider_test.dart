import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/transaction_model.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/transaction_provider.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);
  final seller = UserModel(
    id: 'seller-1',
    email: 'seller@example.com',
    displayName: 'Seller',
    role: UserRole.seller,
    assignedRouteIds: ['route-1'],
    active: true,
    createdAt: ts,
    updatedAt: ts,
  );

  ProviderContainer containerWithUser(UserModel? user) {
    return ProviderContainer(
      overrides: [
        authUserProvider.overrideWith((ref) => Stream<UserModel?>.value(user)),
      ],
    );
  }

  ProviderSubscription<AsyncValue<UserModel?>> keepAuthAlive(
    ProviderContainer container,
  ) {
    return container.listen<AsyncValue<UserModel?>>(
      authUserProvider,
      (_, _) {},
      fireImmediately: true,
    );
  }

  group('Transaction export guard providers', () {
    test(
      'sortTransactionsForExport orders the ledger from oldest to newest',
      () {
        final txs = [
          TransactionModel(
            id: 'b',
            shopId: 'shop-1',
            shopName: 'Shop',
            routeId: 'route-1',
            type: 'cash_out',
            amount: 25,
            description: 'later',
            createdBy: 'seller-1',
            createdAt: Timestamp.fromDate(DateTime(2026, 7, 6)),
            items: const [],
            deleted: false,
          ),
          TransactionModel(
            id: 'a',
            shopId: 'shop-1',
            shopName: 'Shop',
            routeId: 'route-1',
            type: 'cash_in',
            amount: 10,
            description: 'earlier',
            createdBy: 'seller-1',
            createdAt: Timestamp.fromDate(DateTime(2026, 7, 1)),
            items: const [],
            deleted: false,
          ),
        ];

        final sorted = sortTransactionsForExport(txs);

        expect(sorted.map((tx) => tx.id), ['a', 'b']);
      },
    );

    test(
      'shopTransactionsExportProvider returns empty for blank shop id',
      () async {
        final container = containerWithUser(seller);
        addTearDown(container.dispose);
        final authSub = keepAuthAlive(container);
        addTearDown(authSub.close);

        final result = await container.read(
          shopTransactionsExportProvider('   ').future,
        );

        expect(result, isEmpty);
      },
    );

    test(
      'routeTransactionsExportProvider returns empty for seller outside assigned route',
      () async {
        final container = containerWithUser(seller);
        addTearDown(container.dispose);
        final authSub = keepAuthAlive(container);
        addTearDown(authSub.close);
        await container.read(authUserProvider.future);

        final result = await container.read(
          routeTransactionsExportProvider('route-2').future,
        );

        expect(result, isEmpty);
      },
    );

    test('allTransactionsExportProvider returns empty for seller', () async {
      final container = containerWithUser(seller);
      addTearDown(container.dispose);
      final authSub = keepAuthAlive(container);
      addTearDown(authSub.close);
      await container.read(authUserProvider.future);

      final result = await container.read(allTransactionsExportProvider.future);

      expect(result, isEmpty);
    });

    test(
      'sellerTransactionsExportProvider returns empty for seller (non-admin)',
      () async {
        final container = containerWithUser(seller);
        addTearDown(container.dispose);
        final authSub = keepAuthAlive(container);
        addTearDown(authSub.close);
        await container.read(authUserProvider.future);

        final result = await container.read(
          sellerTransactionsExportProvider('seller-1').future,
        );

        expect(result, isEmpty);
      },
    );

    test(
      'sellerTransactionsExportProvider returns empty for blank seller id',
      () async {
        final container = containerWithUser(seller);
        addTearDown(container.dispose);
        final authSub = keepAuthAlive(container);
        addTearDown(authSub.close);

        final result = await container.read(
          sellerTransactionsExportProvider('').future,
        );

        expect(result, isEmpty);
      },
    );
  });
}
