import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/pnl_provider.dart';
import '../models/pnl_snapshot_model.dart';
import '../widgets/error_state.dart';
import '../widgets/stat_card.dart';
import '../core/utils/formatters.dart';
import '../widgets/export_sheet.dart';
import '../core/l10n/app_locale.dart';

class PnlScreen extends ConsumerStatefulWidget {
  const PnlScreen({super.key});

  @override
  ConsumerState<PnlScreen> createState() => _PnlScreenState();
}

class _PnlScreenState extends ConsumerState<PnlScreen> {
  int _year = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final currentPnl = ref.watch(currentPnlProvider);
    final yearlyPnl = ref.watch(yearlyPnlProvider(_year));

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('profit_loss', ref)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: tr('export_share', ref),
            onPressed: () {
              final list = yearlyPnl.valueOrNull ?? [];
              if (list.isEmpty) return;
              ExportSheet.show(
                context,
                ref,
                title: 'P&L $_year',
                fileName: 'pnl_$_year',
                headers: [
                  tr('period', ref),
                  tr('revenue', ref),
                  tr('cogs', ref),
                  tr('gross_profit', ref),
                  tr('expenses', ref),
                  tr('worker_cost', ref),
                  tr('net_profit', ref)
                ],
                rows: list
                    .map((p) => [
                          p.period,
                          p.revenue,
                          p.cogs,
                          p.grossProfit,
                          p.expenses,
                          p.workerCost,
                          p.netProfit,
                        ])
                    .toList(),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => _year--),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child:
                Text('$_year', style: Theme.of(context).textTheme.titleMedium),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _year < DateTime.now().year
                ? () => setState(() => _year++)
                : null,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Current month stats
          currentPnl.when(
            data: (pnl) => pnl != null
                ? _CurrentMonthSection(pnl: pnl)
                : const SizedBox.shrink(),
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => ErrorState(message: e.toString()),
          ),
          const SizedBox(height: 24),
          Text('$_year — ${tr('monthly_chart', ref)}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          yearlyPnl.when(
            data: (list) => list.isEmpty
                ? Center(
                    child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(tr('no_data_year', ref)),
                  ))
                : _YearlyChartSection(snapshots: list, year: _year),
            loading: () => const SizedBox(
                height: 200, child: Center(child: CircularProgressIndicator())),
            error: (e, _) => ErrorState(message: e.toString()),
          ),
          const SizedBox(height: 24),
          yearlyPnl.when(
            data: (list) => list.isEmpty
                ? const SizedBox.shrink()
                : _SummaryTable(snapshots: list),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _CurrentMonthSection extends ConsumerWidget {
  final PnlSnapshotModel pnl;
  const _CurrentMonthSection({required this.pnl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${tr('current_month', ref)} (${pnl.period})',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.2,
          children: [
            StatCard(
              title: tr('revenue', ref),
              value: AppFormatters.sar(pnl.revenue),
              icon: Icons.trending_up,
              color: Colors.green,
            ),
            StatCard(
              title: tr('cogs', ref),
              value: AppFormatters.sar(pnl.cogs),
              icon: Icons.inventory_2,
              color: Colors.orange,
            ),
            StatCard(
              title: tr('gross_profit', ref),
              value: AppFormatters.sar(pnl.grossProfit),
              icon: Icons.bar_chart,
              color: Colors.blue,
            ),
            StatCard(
              title: tr('expenses', ref),
              value: AppFormatters.sar(pnl.expenses),
              icon: Icons.receipt_long,
              color: Colors.red,
            ),
            StatCard(
              title: tr('worker_cost', ref),
              value: AppFormatters.sar(pnl.workerCost),
              icon: Icons.people,
              color: Colors.purple,
            ),
            StatCard(
              title: tr('net_profit', ref),
              value: AppFormatters.sar(pnl.netProfit),
              icon: Icons.account_balance_wallet,
              color: pnl.netProfit >= 0 ? Colors.green : Colors.red,
            ),
          ],
        ),
      ],
    );
  }
}

class _YearlyChartSection extends ConsumerWidget {
  final List<PnlSnapshotModel> snapshots;
  final int year;

  const _YearlyChartSection({required this.snapshots, required this.year});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final months = List.generate(12, (i) => (i + 1).toString().padLeft(2, '0'));
    final byPeriod = {for (final s in snapshots) s.period.split('-').last: s};

    final revenueColor = Colors.green.shade400;
    final expensesColor = Colors.red.shade400;
    final profitColor = Colors.blue.shade400;

    final List<BarChartGroupData> groups = List.generate(12, (i) {
      final month = months[i];
      final pnl = byPeriod[month];
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
              toY: pnl?.revenue ?? 0,
              color: revenueColor,
              width: 8,
              borderRadius: BorderRadius.circular(2)),
          BarChartRodData(
              toY: pnl?.expenses ?? 0,
              color: expensesColor,
              width: 8,
              borderRadius: BorderRadius.circular(2)),
          BarChartRodData(
              toY: pnl?.netProfit ?? 0,
              color: profitColor,
              width: 8,
              borderRadius: BorderRadius.circular(2)),
        ],
      );
    });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            RepaintBoundary(
              child: SizedBox(
                height: 220,
                child: BarChart(
                  BarChartData(
                    barGroups: groups,
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 48,
                          getTitlesWidget: (v, _) => Text(
                            AppFormatters.compact(v),
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                      ),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (v, _) {
                            final abbr = tr('month_labels', ref).split(',');
                            return Text(abbr[v.toInt()],
                                style: theme.textTheme.labelSmall);
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    gridData: FlGridData(
                      drawVerticalLine: false,
                      horizontalInterval: 1,
                      getDrawingHorizontalLine: (v) => FlLine(
                        color: theme.dividerColor,
                        strokeWidth: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Legend(color: revenueColor, label: tr('pnl_revenue', ref)),
                const SizedBox(width: 16),
                _Legend(color: expensesColor, label: tr('pnl_expenses', ref)),
                const SizedBox(width: 16),
                _Legend(color: profitColor, label: tr('pnl_net_profit', ref)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _SummaryTable extends ConsumerWidget {
  final List<PnlSnapshotModel> snapshots;
  const _SummaryTable({required this.snapshots});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Compute yearly totals
    double totalRevenue = 0,
        totalCogs = 0,
        totalExpenses = 0,
        totalWorkerCost = 0;
    for (final s in snapshots) {
      totalRevenue += s.revenue;
      totalCogs += s.cogs;
      totalExpenses += s.expenses;
      totalWorkerCost += s.workerCost;
    }
    final totalGross = totalRevenue - totalCogs;
    final totalNet = totalGross - totalExpenses - totalWorkerCost;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('year_summary', ref),
                style: Theme.of(context).textTheme.titleSmall),
            const Divider(),
            _SummaryRow(tr('revenue', ref), totalRevenue),
            _SummaryRow(tr('cogs', ref), totalCogs, negative: true),
            _SummaryRow(tr('gross_profit', ref), totalGross, bold: true),
            _SummaryRow(tr('expenses', ref), totalExpenses, negative: true),
            _SummaryRow(tr('worker_cost', ref), totalWorkerCost,
                negative: true),
            const Divider(),
            _SummaryRow(tr('net_profit', ref), totalNet,
                bold: true, color: totalNet >= 0 ? Colors.green : Colors.red),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final double value;
  final bool negative;
  final bool bold;
  final Color? color;
  const _SummaryRow(this.label, this.value,
      {this.negative = false, this.bold = false, this.color});

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(fontWeight: FontWeight.bold, color: color)
        : Theme.of(context).textTheme.bodyMedium?.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(
            '${negative ? '- ' : ''}${AppFormatters.sar(value.abs())}',
            style: style,
          ),
        ],
      ),
    );
  }
}
