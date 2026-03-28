/// Convenience entry-point: runs all test suites.
/// Usage:  flutter test test/all_tests.dart
library;

import 'unit/models/user_model_test.dart' as user_model;
import 'unit/models/product_model_test.dart' as product_model;
import 'unit/models/settings_model_test.dart' as settings_model;
import 'unit/core/validators_test.dart' as validators;
import 'unit/core/formatters_test.dart' as formatters;

void main() {
  user_model.main();
  product_model.main();
  settings_model.main();
  validators.main();
  formatters.main();
}
