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

  /// Amounts: digits + single decimal point.
  static final amountFormatter = FilteringTextInputFormatter.allow(
    RegExp(r'[\d.]'),
  );

  /// Integer-only input.
  static final intFormatter = FilteringTextInputFormatter.digitsOnly;

  /// Max length helper (returns a [LengthLimitingTextInputFormatter]).
  static LengthLimitingTextInputFormatter maxLength(int max) =>
      LengthLimitingTextInputFormatter(max);
}
