// CANONICAL COLLECTION NAMES — always use these constants, never raw strings.
//
// ARCHITECTURE NOTE (2026-04-07):
// The Firestore collection for retail shops is named 'customers' for legacy
// reasons. In the app it is exclusively referred to as ShopModel.
// Use `Collections.shops` in all new code. `Collections.customers` is the
// underlying Firestore path and must not be renamed without a data migration.
//
// FINANCIAL PATHWAY SUMMARY:
//   Sale with stock    → Invoice (CreateSaleInvoiceScreen + InvoiceNotifier)
//   Cash from old debt → Ledger entry only (TransactionNotifier, type: cash_in)
//   Bad debt write-off → ShopNotifier.markAsBadDebt (type: write_off)
class Collections {
  Collections._();
  static const users = 'users';
  static const products = 'products';
  static const productVariants = 'product_variants';
  static const sellerInventory = 'seller_inventory';
  static const inventoryTransactions = 'inventory_transactions';
  static const routes = 'routes';
  // 'customers' is the legacy Firestore collection name for shops.
  // Use Collections.shops in new code — both point to the same collection.
  static const customers = 'customers';
  static const shops =
      customers; // alias — same Firestore collection 'customers'
  static const transactions = 'transactions';
  static const invoices = 'invoices';
  static const settings = 'settings';

  /// Admin-only collection — stores SA credentials for admin auth pipeline.
  static const adminConfig = 'admin_config';
}
