import 'package:flutter/services.dart';

/// Re-usable [TextInputFormatter]s for common field types.
class AppInputFormatters {
  AppInputFormatters._();

  /// SKU: uppercase alphanumeric + hyphens + underscores.
  static final skuFormatter = FilteringTextInputFormatter.allow(
    RegExp(r'[a-zA-Z0-9\-_]'),
  );

  /// Phone: digits, +, -, spaces.
  static final phoneFormatter = FilteringTextInputFormatter.allow(
    RegExp(r'[\d+\-\s]'),
  );

  /// Amounts: Western, Arabic-Indic, and Eastern Arabic digits and separators.
  static final amountFormatter = FilteringTextInputFormatter.allow(
    RegExp(r'[0-9٠-٩۰-۹.,٫٬،]'),
  );

  /// Integer-only input.
  static final intFormatter = FilteringTextInputFormatter.digitsOnly;

  /// Max length helper (returns a [LengthLimitingTextInputFormatter]).
  static LengthLimitingTextInputFormatter maxLength(int max) =>
      LengthLimitingTextInputFormatter(max);
}
