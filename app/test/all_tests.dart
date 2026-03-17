/// Convenience entry-point: runs all test suites.
/// Usage:  flutter test test/all_tests.dart
library;

import 'unit/models/user_model_test.dart' as user_model;
import 'unit/models/product_model_test.dart' as product_model;
import 'unit/models/inventory_batch_model_test.dart' as inventory_batch;
import 'unit/models/inventory_item_model_test.dart' as inventory_item;
import 'unit/models/order_model_test.dart' as order_model;
import 'unit/models/order_item_model_test.dart' as order_item;
import 'unit/models/customer_model_test.dart' as customer_model;
import 'unit/models/worker_model_test.dart' as worker_model;
import 'unit/models/worker_payment_model_test.dart' as worker_payment;
import 'unit/models/expense_model_test.dart' as expense_model;
import 'unit/models/cash_transaction_model_test.dart' as cash_transaction;
import 'unit/models/cash_approval_model_test.dart' as cash_approval;
import 'unit/models/expense_approval_model_test.dart' as expense_approval;
import 'unit/models/pnl_snapshot_model_test.dart' as pnl_snapshot;
import 'unit/models/supplier_model_test.dart' as supplier_model;
import 'unit/models/purchase_order_model_test.dart' as purchase_order;
import 'unit/models/qc_record_model_test.dart' as qc_record;
import 'unit/models/waste_record_model_test.dart' as waste_record;
import 'unit/models/settings_model_test.dart' as settings_model;
import 'unit/models/order_return_model_test.dart' as order_return;
import 'unit/core/validators_test.dart' as validators;
import 'unit/core/formatters_test.dart' as formatters;
import 'widget/stat_card_test.dart' as stat_card;
import 'widget/status_chip_test.dart' as status_chip;
import 'widget/empty_state_test.dart' as empty_state;
import 'widget/error_state_test.dart' as error_state;

void main() {
  user_model.main();
  product_model.main();
  inventory_batch.main();
  inventory_item.main();
  order_model.main();
  order_item.main();
  customer_model.main();
  worker_model.main();
  worker_payment.main();
  expense_model.main();
  cash_transaction.main();
  cash_approval.main();
  expense_approval.main();
  pnl_snapshot.main();
  supplier_model.main();
  purchase_order.main();
  qc_record.main();
  waste_record.main();
  settings_model.main();
  order_return.main();
  validators.main();
  formatters.main();
  stat_card.main();
  status_chip.main();
  empty_state.main();
  error_state.main();
}
