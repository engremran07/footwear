import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/models/product_model.dart';
import 'package:footwear_erp/models/product_variant_model.dart';
import 'package:footwear_erp/models/route_model.dart';
import 'package:footwear_erp/models/shop_model.dart';
import 'package:footwear_erp/providers/archive_provider.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/screens/record_archive_screen.dart';

void main() {
  test(
    'archive provider rejects a seller before querying business records',
    () async {
      final container = ProviderContainer(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(_seller())),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(archivedBusinessRecordsProvider.future),
        throwsA(isA<StateError>()),
      );
    },
  );

  testWidgets(
    'archive lists inactive records and disables permanent deletion',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            archivedBusinessRecordsProvider.overrideWith(
              (ref) async => _archivedRecords(),
            ),
          ],
          child: const MaterialApp(home: RecordArchiveScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Record Archive'), findsOneWidget);
      expect(find.text('Archived Shops (1)'), findsOneWidget);
      expect(find.text('Archived Routes (1)'), findsOneWidget);
      expect(find.text('Archived Products (1)'), findsOneWidget);
      expect(find.text('Archived Variants (1)'), findsOneWidget);
      expect(find.text('Permanently deleted shop'), findsNothing);

      final deleteAction = find.byKey(
        const Key('archive_permanent_delete_unavailable'),
      );
      expect(deleteAction, findsOneWidget);
      expect(tester.widget<OutlinedButton>(deleteAction).onPressed, isNull);

      await tester.scrollUntilVisible(
        find.text('Archived Variant'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Archived Variant'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('archive screen maps failures and offers retry', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          archivedBusinessRecordsProvider.overrideWith((ref) async {
            throw FirebaseException(
              plugin: 'cloud_firestore',
              code: 'permission-denied',
            );
          }),
        ],
        child: const MaterialApp(home: RecordArchiveScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('You do not have permission to perform this action.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

UserModel _seller() {
  final now = Timestamp.now();
  return UserModel(
    id: 'seller-1',
    email: 'seller@example.test',
    displayName: 'Seller',
    role: UserRole.seller,
    tenantId: 'tenant-1',
    assignedRouteIds: const ['route-1'],
    active: true,
    createdAt: now,
    updatedAt: now,
  );
}

ArchivedBusinessRecords _archivedRecords() {
  final now = Timestamp.now();
  return ArchivedBusinessRecords(
    shops: [
      ShopModel(
        id: 'shop-1',
        name: 'Archived Shop',
        routeId: 'route-1',
        routeNumber: 1,
        balance: 0,
        active: false,
        createdBy: 'admin-1',
        createdAt: now,
        updatedAt: now,
      ),
    ],
    routes: [
      RouteModel(
        id: 'route-1',
        routeNumber: 1,
        name: 'Archived Route',
        totalShops: 0,
        active: false,
        createdBy: 'admin-1',
        createdAt: now,
        updatedAt: now,
      ),
    ],
    products: [
      ProductModel(
        id: 'product-1',
        name: 'Archived Product',
        category: 'Footwear',
        active: false,
        createdAt: now,
        updatedAt: now,
      ),
    ],
    variants: [
      ProductVariantModel(
        id: 'variant-1',
        productId: 'product-1',
        variantName: 'Archived Variant',
        quantityAvailable: 0,
        active: false,
        createdAt: now,
        updatedAt: now,
      ),
    ],
  );
}
