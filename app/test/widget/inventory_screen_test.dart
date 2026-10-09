import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/product_variant_model.dart';
import 'package:footwear_erp/models/seller_inventory_model.dart';
import 'package:footwear_erp/models/settings_model.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/product_provider.dart';
import 'package:footwear_erp/providers/seller_inventory_provider.dart';
import 'package:footwear_erp/providers/settings_provider.dart';
import 'package:footwear_erp/screens/inventory_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
              companyName: 'Workspace One',
              currency: 'SAR',
              pairsPerCarton: 12,
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
