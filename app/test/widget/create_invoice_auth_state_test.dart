import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:footwear_erp/models/settings_model.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/product_provider.dart';
import 'package:footwear_erp/providers/seller_inventory_provider.dart';
import 'package:footwear_erp/providers/settings_provider.dart';
import 'package:footwear_erp/screens/create_sale_invoice_screen.dart';
import 'package:footwear_erp/providers/shop_provider.dart';
import 'package:footwear_erp/providers/route_provider.dart';
import 'package:footwear_erp/widgets/error_state.dart';

void main() {
  testWidgets('invoice creation shows retry when profile loading fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith(
            (ref) => Stream.error(StateError('profile unavailable')),
          ),
        ],
        child: const MaterialApp(home: CreateSaleInvoiceScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin stock empty state explains allocation and non-stock mode', (
    tester,
  ) async {
    final now = Timestamp.now();
    final admin = UserModel(
      id: 'admin-uid',
      email: 'admin@example.com',
      displayName: 'Admin',
      role: UserRole.admin,
      tenantId: 'tenant-1',
      active: true,
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(admin)),
          shopsProvider.overrideWith((ref) => Stream.value(const [])),
          sellerInventoryProvider.overrideWith(
            (ref, sellerId) => Stream.value(const []),
          ),
          settingsProvider.overrideWith(
            (ref) => Stream.value(
              SettingsModel(
                tenantId: 'tenant-1',
                currency: 'SAR',
                pairsPerCarton: 12,
                allowNonStockInvoices: false,
                invoiceHeader: const InvoiceHeaderConfig(nameEn: 'Workspace'),
                updatedAt: now,
              ),
            ),
          ),
          productsProvider.overrideWith((ref) => Stream.value(const [])),
          allVariantsProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: const MaterialApp(home: CreateSaleInvoiceScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.text(
        'No stock is allocated to you. Transfer warehouse stock to your account, '
        'or choose a non-stock invoice if this workspace allows it.',
      ),
      findsOneWidget,
    );
    expect(find.text('No inventory items available'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'tenant-enabled non-stock mode is visible to every invoice-creating role',
    (tester) async {
      final now = Timestamp.now();
      for (final role in [
        UserRole.admin,
        UserRole.tenantAdmin,
        UserRole.supervisor,
        UserRole.seller,
      ]) {
        final user = UserModel(
          id: 'user-${role.name}',
          email: 'user@example.com',
          displayName: role.name,
          role: role,
          tenantId: 'tenant-1',
          assignedRouteIds: role == UserRole.seller
              ? const ['route-1']
              : const [],
          active: true,
          createdAt: now,
          updatedAt: now,
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authUserProvider.overrideWith((ref) => Stream.value(user)),
              shopsProvider.overrideWith((ref) => Stream.value(const [])),
              sellerAllShopsProvider.overrideWith(
                (ref) => Stream.value(const []),
              ),
              sellerInventoryProvider.overrideWith(
                (ref, sellerId) => Stream.value(const []),
              ),
              settingsProvider.overrideWith(
                (ref) => Stream.value(
                  SettingsModel(
                    tenantId: 'tenant-1',
                    currency: 'SAR',
                    pairsPerCarton: 12,
                    allowNonStockInvoices: true,
                    invoiceHeader: const InvoiceHeaderConfig(
                      nameEn: 'Workspace',
                    ),
                    updatedAt: now,
                  ),
                ),
              ),
              productsProvider.overrideWith((ref) => Stream.value(const [])),
              allVariantsProvider.overrideWith((ref) => Stream.value(const [])),
              routeCurrencyProvider.overrideWith((ref, routeId) => 'SAR'),
            ],
            child: const MaterialApp(home: CreateSaleInvoiceScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Non-stock Invoice'),
          findsOneWidget,
          reason: role.name,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
}
