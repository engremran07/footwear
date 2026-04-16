/// Convenience entry-point: runs all test suites.
/// Usage:  flutter test test/all_tests.dart
library;

import 'unit/models/user_model_test.dart' as user_model;
import 'unit/models/product_model_test.dart' as product_model;
import 'unit/models/settings_model_test.dart' as settings_model;
import 'unit/models/shop_model_test.dart' as shop_model;
import 'unit/models/route_model_test.dart' as route_model;
import 'unit/models/shop_model_bad_debt_test.dart' as shop_model_bad_debt;
import 'unit/core/collections_test.dart' as collections;
import 'unit/business_logic/financial_pathways_test.dart' as financial_pathways;
import 'unit/business_logic/bad_debt_writeoff_test.dart' as bad_debt_writeoff;
import 'unit/business_logic/transaction_type_validation_test.dart'
    as transaction_type_validation;
import 'unit/models/inventory_transaction_model_test.dart'
    as inventory_transaction_model;
import 'unit/models/invoice_model_test.dart' as invoice_model;
import 'unit/models/transaction_model_test.dart' as transaction_model;
import 'unit/models/product_variant_model_test.dart' as product_variant_model;
import 'unit/core/validators_test.dart' as validators;
import 'unit/core/formatters_test.dart' as formatters;
import 'unit/core/l10n_test.dart' as l10n;
import 'unit/core/sanitizer_test.dart' as sanitizer;
import 'unit/core/error_mapper_test.dart' as error_mapper;
import 'unit/core/changelog_data_test.dart' as changelog_data;
import 'unit/core/share_helper_test.dart' as share_helper;
import 'unit/core/excel_export_test.dart' as excel_export;
import 'unit/core/pdf_export_test.dart' as pdf_export;
import 'unit/models/seller_inventory_model_test.dart' as seller_inventory_model;
import 'unit/models/invoice_model_extended_test.dart' as invoice_model_extended;
import 'unit/business_logic/void_invoice_balance_test.dart'
    as void_invoice_balance;
import 'unit/business_logic/create_sale_invoice_guard_test.dart'
    as create_sale_invoice_guard;
import 'unit/business_logic/mark_paid_outstanding_test.dart'
    as mark_paid_outstanding;
import 'unit/providers/settings_provider_test.dart' as settings_provider;
import 'unit/providers/transaction_provider_test.dart' as transaction_provider;
import 'unit/providers/changelog_provider_test.dart' as changelog_provider;
import 'widget/confirm_dialog_test.dart' as confirm_dialog_widget;
import 'widget/stat_card_test.dart' as stat_card_widget;
import 'widget/empty_state_test.dart' as empty_state_widget;
import 'widget/app_online_indicator_test.dart' as app_online_indicator_widget;

void main() {
  user_model.main();
  product_model.main();
  settings_model.main();
  shop_model.main();
  route_model.main();
  shop_model_bad_debt.main();
  collections.main();
  financial_pathways.main();
  bad_debt_writeoff.main();
  transaction_type_validation.main();
  inventory_transaction_model.main();
  invoice_model.main();
  transaction_model.main();
  product_variant_model.main();
  seller_inventory_model.main();
  invoice_model_extended.main();
  void_invoice_balance.main();
  create_sale_invoice_guard.main();
  mark_paid_outstanding.main();
    settings_provider.main();
    transaction_provider.main();
    changelog_provider.main();
  validators.main();
  formatters.main();
  l10n.main();
  sanitizer.main();
  error_mapper.main();
  changelog_data.main();
    share_helper.main();
    excel_export.main();
    pdf_export.main();
    confirm_dialog_widget.main();
    stat_card_widget.main();
    empty_state_widget.main();
    app_online_indicator_widget.main();
}
