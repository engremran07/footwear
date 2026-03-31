import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/design/app_tokens.dart';

/// Red/green pill that shows a formatted currency balance.
class AppBalanceBadge extends StatelessWidget {
  final double amount;
  final String currencySymbol;
  final bool invertColors;

  const AppBalanceBadge({
    super.key,
    required this.amount,
    this.currencySymbol = '\$',
    this.invertColors = false,
  });

  @override
  Widget build(BuildContext context) {
    final isNegative = amount < 0;
    final Color bg;
    final Color fg;

    if (invertColors) {
      bg = isNegative ? Colors.green.shade50 : Colors.red.shade50;
      fg = isNegative ? Colors.green.shade700 : Colors.red.shade700;
    } else {
      bg = isNegative ? Colors.red.shade50 : Colors.green.shade50;
      fg = isNegative ? Colors.red.shade700 : Colors.green.shade700;
    }

    final formatted = NumberFormat.currency(
      symbol: currencySymbol,
      decimalDigits: 2,
    ).format(amount.abs());

    final text = '${isNegative ? '-' : ''}$formatted';

    return Semantics(
      label: 'Balance: $text',
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s8, vertical: AppTokens.s4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AppTokens.brSM,
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}
