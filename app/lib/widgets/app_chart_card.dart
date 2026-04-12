import 'package:flutter/material.dart';
import '../core/design/app_tokens.dart';
import 'empty_state.dart';

/// Wrapper card for fl_chart widgets with a header, optional legend, and
/// empty-state fallback when [isEmpty] is true.
class AppChartCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget chart;
  final bool isEmpty;
  final String emptyMessage;
  final List<ChartLegendItem>? legend;
  final double height;

  const AppChartCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.chart,
    this.isEmpty = false,
    this.emptyMessage = 'No data available',
    this.legend,
    this.height = 240,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: AppTokens.brMD),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppTokens.s4),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: AppTokens.s16),

            // Chart or empty state
            SizedBox(
              height: height,
              child: isEmpty
                  ? EmptyState(
                      icon: Icons.bar_chart_rounded,
                      message: emptyMessage,
                    )
                  : chart,
            ),

            // Legend
            if (legend != null && legend!.isNotEmpty) ...[
              const SizedBox(height: AppTokens.s12),
              Wrap(
                spacing: AppTokens.s16,
                runSpacing: AppTokens.s8,
                children: legend!
                    .map((item) => _LegendDot(item: item))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Data class for a legend entry.
class ChartLegendItem {
  final Color color;
  final String label;
  const ChartLegendItem({required this.color, required this.label});
}

class _LegendDot extends StatelessWidget {
  final ChartLegendItem item;
  const _LegendDot({required this.item});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: item.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppTokens.s4),
        Text(item.label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
