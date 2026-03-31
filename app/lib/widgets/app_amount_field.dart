import 'package:flutter/material.dart';
import '../core/design/app_tokens.dart';
import '../core/utils/input_formatters.dart';

/// Numeric input field for amounts with currency prefix and formatting.
class AppAmountField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final bool readOnly;
  final String currencyPrefix;
  final ValueChanged<String>? onChanged;

  const AppAmountField({
    super.key,
    required this.controller,
    this.label = 'Amount',
    this.validator,
    this.readOnly = false,
    this.currencyPrefix = 'PKR',
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        AppInputFormatters.amountFormatter,
        AppInputFormatters.maxLength(15),
      ],
      decoration: InputDecoration(
        labelText: label,
        prefixText: '$currencyPrefix ',
        prefixIcon: const Icon(Icons.attach_money, size: AppTokens.iconSizeMD),
      ),
      validator: validator,
      onChanged: onChanged,
      textInputAction: TextInputAction.next,
    );
  }
}
