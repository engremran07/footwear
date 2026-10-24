import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/product_model.dart';
import 'package:footwear_erp/models/product_variant_model.dart';
import 'package:footwear_erp/models/route_model.dart';
import 'package:footwear_erp/models/shop_model.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/product_provider.dart';
import 'package:footwear_erp/providers/route_provider.dart';
import 'package:footwear_erp/providers/shop_provider.dart';
import 'package:footwear_erp/screens/product_form_screen.dart';
import 'package:footwear_erp/screens/shop_form_screen.dart';
import 'package:footwear_erp/screens/variant_form_screen.dart';
import 'package:footwear_erp/widgets/error_state.dart';

void main() {
  testWidgets('product edit waits for data and retries a failed load', (
    tester,
  ) async {
    var attempts = 0;
    final product = _product();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(_admin())),
          productDetailProvider('product-1').overrideWith((ref) {
            attempts += 1;
            return attempts == 1
                ? Stream.error(StateError('product unavailable'))
                : Stream.value(product);
          }),
        ],
        child: const MaterialApp(
          home: ProductFormScreen(productId: 'product-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Save'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(attempts, greaterThan(1));
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      'Existing product',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('product edit does not show defaults while the record loads', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(_admin())),
          productDetailProvider(
            'product-1',
          ).overrideWith((ref) => const Stream.empty()),
        ],
        child: const MaterialApp(
          home: ProductFormScreen(productId: 'product-1'),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('missing product cannot be edited with a blank default', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(_admin())),
          productDetailProvider(
            'product-1',
          ).overrideWith((ref) => Stream.value(null)),
        ],
        child: const MaterialApp(
          home: ProductFormScreen(productId: 'product-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('shop edit waits for data and preserves the stored route', (
    tester,
  ) async {
    var attempts = 0;
    final route = _route();
    final shop = _shop();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(_admin())),
          routesProvider.overrideWith((ref) => Stream.value([route])),
          shopDetailProvider('shop-1').overrideWith((ref) {
            attempts += 1;
            return attempts == 1
                ? Stream.error(StateError('shop unavailable'))
                : Stream.value(shop);
          }),
        ],
        child: const MaterialApp(home: ShopFormScreen(shopId: 'shop-1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Save'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(attempts, greaterThan(1));
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      'Existing shop',
    );
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .initialValue,
      'route-1',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shop edit stays gated while the record loads', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(_admin())),
          routesProvider.overrideWith((ref) => Stream.value([_route()])),
          shopDetailProvider(
            'shop-1',
          ).overrideWith((ref) => const Stream.empty()),
        ],
        child: const MaterialApp(home: ShopFormScreen(shopId: 'shop-1')),
      ),
    );
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('shop form exposes route query failure with a retry action', (
    tester,
  ) async {
    var routeAttempts = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(_admin())),
          routesProvider.overrideWith((ref) {
            routeAttempts += 1;
            return routeAttempts == 1
                ? Stream.error(StateError('route list unavailable'))
                : Stream.value([_route()]);
          }),
        ],
        child: const MaterialApp(home: ShopFormScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shop_route_load_error')), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(routeAttempts, greaterThan(1));
    expect(find.byKey(const Key('shop_route_load_error')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('seller shop form cannot save before route details load', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(_seller())),
          routesBySellerProvider(
            'seller-1',
          ).overrideWith((ref) => const Stream.empty()),
        ],
        child: const MaterialApp(home: ShopFormScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing shop cannot be edited with route defaults', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(_admin())),
          routesProvider.overrideWith((ref) => Stream.value([_route()])),
          shopDetailProvider(
            'shop-1',
          ).overrideWith((ref) => Stream.value(null)),
        ],
        child: const MaterialApp(home: ShopFormScreen(shopId: 'shop-1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('variant edit waits for data and retries a failed load', (
    tester,
  ) async {
    var attempts = 0;
    final variant = _variant();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(_admin())),
          productVariantsProvider('product-1').overrideWith((ref) {
            attempts += 1;
            return attempts == 1
                ? Stream.error(StateError('variants unavailable'))
                : Stream.value([variant]);
          }),
        ],
        child: const MaterialApp(
          home: VariantFormScreen(
            productId: 'product-1',
            variantId: 'variant-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Save'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(attempts, greaterThan(1));
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      'Existing variant',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('variant edit stays gated while variants load', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(_admin())),
          productVariantsProvider(
            'product-1',
          ).overrideWith((ref) => const Stream.empty()),
        ],
        child: const MaterialApp(
          home: VariantFormScreen(
            productId: 'product-1',
            variantId: 'variant-1',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('missing variant cannot be edited using an empty default', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(_admin())),
          productVariantsProvider(
            'product-1',
          ).overrideWith((ref) => Stream.value(<ProductVariantModel>[])),
        ],
        child: const MaterialApp(
          home: VariantFormScreen(
            productId: 'product-1',
            variantId: 'missing-variant',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Save'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

UserModel _admin() {
  final now = Timestamp.now();
  return UserModel(
    id: 'admin-1',
    email: 'admin@example.com',
    displayName: 'Admin',
    role: UserRole.tenantAdmin,
    tenantId: 'tenant-1',
    active: true,
    createdAt: now,
    updatedAt: now,
  );
}

UserModel _seller() {
  final now = Timestamp.now();
  return UserModel(
    id: 'seller-1',
    email: 'seller@example.com',
    displayName: 'Seller',
    role: UserRole.seller,
    tenantId: 'tenant-1',
    active: true,
    assignedRouteIds: const ['route-1'],
    createdAt: now,
    updatedAt: now,
  );
}

ProductModel _product() {
  final now = Timestamp.now();
  return ProductModel(
    id: 'product-1',
    name: 'Existing product',
    category: 'Shoes',
    active: true,
    createdAt: now,
    updatedAt: now,
  );
}

RouteModel _route() {
  final now = Timestamp.now();
  return RouteModel(
    id: 'route-1',
    routeNumber: 1,
    name: 'Route One',
    totalShops: 1,
    active: true,
    createdBy: 'admin-1',
    createdAt: now,
    updatedAt: now,
  );
}

ShopModel _shop() {
  final now = Timestamp.now();
  return ShopModel(
    id: 'shop-1',
    name: 'Existing shop',
    routeId: 'route-1',
    routeNumber: 1,
    balance: 250,
    active: true,
    createdBy: 'admin-1',
    createdAt: now,
    updatedAt: now,
  );
}

ProductVariantModel _variant() {
  final now = Timestamp.now();
  return ProductVariantModel(
    id: 'variant-1',
    productId: 'product-1',
    variantName: 'Existing variant',
    quantityAvailable: 12,
    active: true,
    createdAt: now,
    updatedAt: now,
  );
}
