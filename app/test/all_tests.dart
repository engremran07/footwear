/// Convenience entry-point: runs all test suites.
/// Usage:  flutter test test/all_tests.dart
library;

import 'unit/models/user_model_test.dart' as user_model;
import 'unit/models/product_model_test.dart' as product_model;
import 'unit/models/settings_model_test.dart' as settings_model;
import 'unit/models/shop_model_test.dart' as shop_model;
import 'unit/models/route_model_test.dart' as route_model;
import 'unit/models/customer_model_test.dart' as customer_model;
import 'unit/models/inventory_transaction_model_test.dart'
  as inventory_transaction_model;
import 'unit/models/invoice_model_test.dart' as invoice_model;
import 'unit/models/transaction_model_test.dart' as transaction_model;
import 'unit/models/product_variant_model_test.dart' as product_variant_model;
import 'unit/core/validators_test.dart' as validators;
import 'unit/core/formatters_test.dart' as formatters;
import 'unit/core/l10n_test.dart' as l10n;
import 'unit/models/seller_inventory_model_test.dart' as seller_inventory_model;

void main() {
  user_model.main();
  product_model.main();
  settings_model.main();
  shop_model.main();
  route_model.main();
  customer_model.main();
  inventory_transaction_model.main();
  invoice_model.main();
  transaction_model.main();
  product_variant_model.main();
  seller_inventory_model.main();
  validators.main();
  formatters.main();
  l10n.main();
}
