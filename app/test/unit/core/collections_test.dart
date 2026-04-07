// Tests for Collections constants alignment.
//
// Verifies that Collections.shops is an alias for Collections.customers
// (same value) and that all canonical collection names are correct.
// This test guards against accidental renaming of collection constants.

import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/constants/collections.dart';

void main() {
  group('Collections — canonical Firestore collection names', () {
    test('customers collection name is "customers"', () {
      expect(Collections.customers, 'customers');
    });

    test('shops alias equals customers (same Firestore collection)', () {
      // CRITICAL: shops and customers must resolve to identical paths.
      // Both ShopModel reads/writes use the same collection.
      expect(Collections.shops, equals(Collections.customers));
    });

    test('transactions collection name is "transactions"', () {
      expect(Collections.transactions, 'transactions');
    });

    test('invoices collection name is "invoices"', () {
      expect(Collections.invoices, 'invoices');
    });

    test('inventory_transactions collection name is correct', () {
      expect(Collections.inventoryTransactions, 'inventory_transactions');
    });

    test('seller_inventory collection name is correct', () {
      expect(Collections.sellerInventory, 'seller_inventory');
    });

    test('product_variants collection name is correct', () {
      expect(Collections.productVariants, 'product_variants');
    });

    test('settings collection name is "settings"', () {
      expect(Collections.settings, 'settings');
    });

    test('users collection name is "users"', () {
      expect(Collections.users, 'users');
    });

    test('routes collection name is "routes"', () {
      expect(Collections.routes, 'routes');
    });

    test('all collections are distinct (no accidental duplicates)', () {
      // shops == customers intentionally; everything else must be unique
      final all = [
        Collections.users,
        Collections.products,
        Collections.productVariants,
        Collections.sellerInventory,
        Collections.inventoryTransactions,
        Collections.routes,
        Collections.transactions,
        Collections.invoices,
        Collections.settings,
      ];
      final unique = all.toSet();
      expect(
        unique.length,
        equals(all.length),
        reason: 'Duplicate collection constant detected',
      );
    });
  });
}
