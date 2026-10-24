import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/product_model.dart';
import 'package:footwear_erp/models/product_variant_model.dart';
import 'package:footwear_erp/models/seller_inventory_model.dart';
import 'package:footwear_erp/models/settings_model.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/product_provider.dart';
import 'package:footwear_erp/providers/seller_inventory_provider.dart';
import 'package:footwear_erp/providers/settings_provider.dart';
import 'package:footwear_erp/providers/user_provider.dart';
import 'package:footwear_erp/screens/inventory_screen.dart';
import 'package:footwear_erp/widgets/error_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('inventory screen blocks quantity actions when settings fail', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final now = Timestamp.now();
    final admin = _testUser(
      id: 'admin-1',
      name: 'Admin',
      role: UserRole.admin,
      now: now,
    );
    final container = ProviderContainer(
      overrides: [
        authUserProvider.overrideWith((ref) => Stream.value(admin)),
        settingsProvider.overrideWith(
          (ref) => Stream.error(StateError('settings unavailable')),
        ),
        allVariantsProvider.overrideWith(
          (ref) => Stream.value(<ProductVariantModel>[]),
        ),
        sellerInventoryProvider.overrideWith(
          (ref, sellerId) => Stream.value(<SellerInventoryModel>[]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: InventoryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Add Inventory'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'add inventory dialog shows product and variant loading and retry states',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final productStream = StreamController<List<ProductModel>>();
      final variantStream = StreamController<List<ProductVariantModel>>();
      addTearDown(productStream.close);
      addTearDown(variantStream.close);

      var productAttempts = 0;
      var variantAttempts = 0;
      final now = Timestamp.now();
      final admin = _testUser(
        id: 'admin-1',
        name: 'Admin',
        role: UserRole.admin,
        now: now,
      );
      final product = ProductModel(
        id: 'product-1',
        name: 'Product One',
        category: 'Shoes',
        active: true,
        createdAt: now,
        updatedAt: now,
      );
      final variant = ProductVariantModel(
        id: 'variant-1',
        productId: product.id,
        variantName: 'Black / 42',
        quantityAvailable: 12,
        active: true,
        createdAt: now,
        updatedAt: now,
      );

      final container = ProviderContainer(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(admin)),
          settingsProvider.overrideWith(
            (ref) => Stream.value(_testSettings(now)),
          ),
          allVariantsProvider.overrideWith(
            (ref) => Stream.value(<ProductVariantModel>[]),
          ),
          sellerInventoryProvider.overrideWith(
            (ref, sellerId) => Stream.value(<SellerInventoryModel>[]),
          ),
          productsProvider.overrideWith((ref) {
            productAttempts++;
            return productAttempts == 1
                ? productStream.stream
                : Stream.value([product]);
          }),
          productVariantsProvider.overrideWith((ref, productId) {
            variantAttempts++;
            return variantAttempts == 1
                ? variantStream.stream
                : Stream.value([variant]);
          }),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: InventoryScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Inventory'));
      await tester.pump();

      expect(find.text('Loading…'), findsOneWidget);
      expect(
        tester
            .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Save'))
            .onPressed,
        isNull,
      );

      productStream.addError(StateError('products unavailable'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('inventory_product_retry')), findsOneWidget);
      await tester.tap(find.byKey(const Key('inventory_product_retry')));
      await tester.pumpAndSettle();
      expect(productAttempts, 2);

      await tester.tap(find.byType(DropdownButton<ProductModel>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(product.name).last);
      await tester.pump();
      expect(find.text('Loading…'), findsOneWidget);

      variantStream.addError(StateError('variants unavailable'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('inventory_variant_retry')), findsOneWidget);
      await tester.tap(find.byKey(const Key('inventory_variant_retry')));
      await tester.pumpAndSettle();
      expect(variantAttempts, 2);
      await tester.tap(find.byType(DropdownButton<ProductVariantModel>));
      await tester.pumpAndSettle();
      expect(find.textContaining(variant.variantName), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('transfer dialog exposes seller loading and retry states', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final sellerStream = StreamController<List<UserModel>>();
    addTearDown(sellerStream.close);

    var sellerAttempts = 0;
    final now = Timestamp.now();
    final admin = _testUser(
      id: 'admin-1',
      name: 'Admin',
      role: UserRole.admin,
      now: now,
    );
    final seller = _testUser(
      id: 'seller-1',
      name: 'Seller One',
      role: UserRole.seller,
      now: now,
    );
    final product = ProductModel(
      id: 'product-1',
      name: 'Product One',
      category: 'Shoes',
      active: true,
      createdAt: now,
      updatedAt: now,
    );
    final variant = ProductVariantModel(
      id: 'variant-1',
      productId: product.id,
      variantName: 'Black / 42',
      quantityAvailable: 12,
      active: true,
      createdAt: now,
      updatedAt: now,
    );

    final container = ProviderContainer(
      overrides: [
        authUserProvider.overrideWith((ref) => Stream.value(admin)),
        settingsProvider.overrideWith(
          (ref) => Stream.value(_testSettings(now)),
        ),
        allVariantsProvider.overrideWith(
          (ref) => Stream.value(<ProductVariantModel>[]),
        ),
        sellerInventoryProvider.overrideWith(
          (ref, sellerId) => Stream.value(<SellerInventoryModel>[]),
        ),
        productsProvider.overrideWith((ref) => Stream.value([product])),
        productVariantsProvider.overrideWith(
          (ref, productId) => Stream.value([variant]),
        ),
        allUsersProvider.overrideWith((ref) {
          sellerAttempts++;
          return sellerAttempts == 1
              ? sellerStream.stream
              : Stream.value([seller]);
        }),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: InventoryScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transfer to Seller'));
    await tester.pump();

    expect(find.text('Loading…'), findsAtLeastNWidgets(1));
    sellerStream.addError(StateError('users unavailable'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('inventory_seller_retry')), findsOneWidget);
    await tester.tap(find.byKey(const Key('inventory_seller_retry')));
    await tester.pumpAndSettle();

    expect(sellerAttempts, 2);
    await tester.tap(find.byType(DropdownButton<UserModel>));
    await tester.pumpAndSettle();
    expect(find.text(seller.displayName), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('return dialog maps auth profile stream errors', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final authUsers = StreamController<UserModel?>.broadcast();
    addTearDown(authUsers.close);
    final now = Timestamp.now();
    final admin = UserModel(
      id: 'admin-1',
      email: 'admin@example.com',
      displayName: 'Admin',
      role: UserRole.admin,
      tenantId: 'tenant-1',
      active: true,
      createdAt: now,
      updatedAt: now,
    );
    final inventoryItem = SellerInventoryModel(
      id: 'admin-1_variant-1',
      sellerId: admin.id,
      sellerName: admin.displayName,
      productId: 'product-1',
      variantId: 'variant-1',
      variantName: 'Black / 42',
      quantityAvailable: 12,
      active: true,
      createdAt: now,
      updatedAt: now,
    );

    final container = ProviderContainer(
      overrides: [
        authUserProvider.overrideWith((ref) => authUsers.stream),
        settingsProvider.overrideWith(
          (ref) => Stream.value(
            SettingsModel(
              currency: 'SAR',
              pairsPerCarton: 12,
              invoiceHeader: const InvoiceHeaderConfig(nameEn: 'Workspace One'),
              updatedAt: now,
            ),
          ),
        ),
        allVariantsProvider.overrideWith(
          (ref) => Stream.value(<ProductVariantModel>[]),
        ),
        sellerInventoryProvider.overrideWith(
          (ref, sellerId) => Stream.value([inventoryItem]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: InventoryScreen()),
      ),
    );
    authUsers.add(admin);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Seller Stock'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Return to Warehouse'));
    await tester.pumpAndSettle();

    container.invalidate(authUserProvider);
    await tester.pump();
    authUsers.addError(StateError('profile unavailable'));
    await tester.pump();
    expect(container.read(authUserProvider).hasError, isTrue);
    await tester.tap(find.text('Return'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SnackBar), findsOneWidget);
  });
}

UserModel _testUser({
  required String id,
  required String name,
  required UserRole role,
  required Timestamp now,
}) {
  return UserModel(
    id: id,
    email: '$id@example.com',
    displayName: name,
    role: role,
    tenantId: 'tenant-1',
    active: true,
    createdAt: now,
    updatedAt: now,
  );
}

SettingsModel _testSettings(Timestamp now) {
  return SettingsModel(
    currency: 'SAR',
    pairsPerCarton: 12,
    invoiceHeader: const InvoiceHeaderConfig(nameEn: 'Workspace One'),
    updatedAt: now,
  );
}
