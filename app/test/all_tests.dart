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
import 'unit/core/backup_cipher_test.dart' as backup_cipher;
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
import 'unit/core/seller_report_currency_test.dart' as seller_report_currency;
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
import 'unit/providers/database_flush_provider_test.dart'
    as database_flush_provider;
import 'unit/providers/changelog_provider_test.dart' as changelog_provider;
import 'widget/confirm_dialog_test.dart' as confirm_dialog_widget;
import 'widget/stat_card_test.dart' as stat_card_widget;
import 'widget/empty_state_test.dart' as empty_state_widget;
import 'widget/error_state_test.dart' as error_state_widget;
import 'widget/status_chip_test.dart' as status_chip_widget;
import 'widget/app_filter_chip_bar_test.dart' as app_filter_chip_bar_widget;
import 'widget/app_balance_badge_test.dart' as app_balance_badge_widget;
import 'widget/app_animations_test.dart' as app_animations_widget;
import 'widget/app_online_indicator_test.dart' as app_online_indicator_widget;
import 'widget/product_form_screen_test.dart' as product_form_screen_widget;
import 'widget/auth_submit_feedback_test.dart' as auth_submit_feedback_widget;
import 'widget/invoice_list_summary_test.dart' as invoice_list_summary_widget;
import 'widget/notification_center_feedback_test.dart'
    as notification_center_feedback_widget;
import 'widget/create_invoice_auth_state_test.dart'
    as create_invoice_auth_state_widget;
import 'widget/profile_dirty_state_test.dart' as profile_dirty_state_widget;
import 'widget/shops_currency_filter_test.dart' as shops_currency_filter_widget;
import 'widget/transaction_description_field_test.dart'
    as transaction_description_field_widget;
import 'widget/users_list_workspace_context_test.dart'
    as users_list_workspace_context_widget;
import 'widget/route_form_seller_load_test.dart'
    as route_form_seller_load_widget;
import 'widget/edit_form_loading_test.dart' as edit_form_loading_widget;
import 'widget/settings_profile_error_test.dart'
    as settings_profile_error_widget;
import 'widget/settings_realtime_hydration_test.dart'
    as settings_realtime_hydration_widget;
import 'widget/tenant_management_error_test.dart'
    as tenant_management_error_widget;
import 'widget/inventory_screen_test.dart' as inventory_screen_widget;
import 'widget/database_backup_screen_test.dart'
    as database_backup_screen_widget;
import 'widget/database_flush_screen_state_test.dart'
    as database_flush_screen_state_widget;
import 'widget/reports_export_feedback_test.dart'
    as reports_export_feedback_widget;
import 'widget/user_route_options_test.dart' as user_route_options_widget;

void main() {
  user_model.main();
  product_model.main();
  settings_model.main();
  shop_model.main();
  route_model.main();
  shop_model_bad_debt.main();
  collections.main();
  backup_cipher.main();
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
  database_flush_provider.main();
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
  seller_report_currency.main();
  confirm_dialog_widget.main();
  stat_card_widget.main();
  empty_state_widget.main();
  error_state_widget.main();
  status_chip_widget.main();
  app_filter_chip_bar_widget.main();
  app_balance_badge_widget.main();
  app_animations_widget.main();
  app_online_indicator_widget.main();
  product_form_screen_widget.main();
  auth_submit_feedback_widget.main();
  invoice_list_summary_widget.main();
  notification_center_feedback_widget.main();
  create_invoice_auth_state_widget.main();
  profile_dirty_state_widget.main();
  shops_currency_filter_widget.main();
  transaction_description_field_widget.main();
  users_list_workspace_context_widget.main();
  route_form_seller_load_widget.main();
  edit_form_loading_widget.main();
  settings_profile_error_widget.main();
  settings_realtime_hydration_widget.main();
  tenant_management_error_widget.main();
  inventory_screen_widget.main();
  database_backup_screen_widget.main();
  database_flush_screen_state_widget.main();
  reports_export_feedback_widget.main();
  user_route_options_widget.main();
}
