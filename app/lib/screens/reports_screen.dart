import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/pnl_provider.dart';
import '../providers/worker_provider.dart';
import '../providers/qc_provider.dart';
import '../models/pnl_snapshot_model.dart';
import '../widgets/error_state.dart';
import '../core/utils/formatters.dart';
import '../widgets/export_sheet.dart';
import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _export(BuildContext context) {
    switch (_tabController.index) {
      case 0: // P&L
        final year = DateTime.now().year;
        final list = ref.read(yearlyPnlProvider(year)).valueOrNull ?? [];
        ExportSheet.show(
          context,
          ref,
          title: 'P&L Summary',
          fileName: 'report_pnl_summary_$year',
          headers: [
            'Period',
            'Revenue',
            'COGS',
            'Gross Profit',
            'Expenses',
            'Worker Cost',
            'Net Profit'
          ],
          rows: list
              .map((p) => [
                    p.period,
                    p.revenue,
                    p.cogs,
                    p.grossProfit,
                    p.expenses,
                    p.workerCost,
                    p.netProfit
                  ])
              .toList(),
        );
        break;
      case 1: // Workers
        final payments = ref.read(allWorkerPaymentsProvider).valueOrNull ?? [];
        final Map<String, ({String name, String type, double paid, int pairs})>
            stats = {};
        for (final p in payments) {
          final existing = stats[p.workerId];
          stats[p.workerId] = (
            name: p.workerName,
            type: p.workerType,
            paid: (existing?.paid ?? 0) + p.amount,
            pairs: (existing?.pairs ?? 0) + p.pairsCount,
          );
        }
        ExportSheet.show(
          context,
          ref,
          title: 'Workers',
          fileName: 'report_workers',
          headers: ['Worker', 'Type', 'Total Paid', 'Total Pairs'],
          rows: stats.values
              .map((s) => [s.name, s.type, s.paid, s.pairs])
              .toList(),
        );
        break;
      case 2: // Waste
        final waste = ref.read(wasteRecordsProvider).valueOrNull ?? [];
        final Map<String, int> byReason = {};
        for (final r in waste) {
          byReason[r.reason] = (byReason[r.reason] ?? 0) + 1;
        }
        ExportSheet.show(
          context,
          ref,
          title: 'Waste',
          fileName: 'report_waste',
          headers: ['Reason', 'Count'],
          rows: byReason.entries.map((e) => [e.key, e.value]).toList(),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('reports', ref)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: tr('export_share', ref),
            onPressed: () => _export(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppBrand.onPrimary,
          unselectedLabelColor: AppBrand.onPrimaryMuted,
          indicatorColor: AppBrand.onPrimary,
          tabs: [
            Tab(text: tr('pnl_summary', ref)),
            Tab(text: tr('workers', ref)),
            Tab(text: tr('waste', ref)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _PnlSummaryTab(),
          _WorkerReportTab(),
          _WasteReportTab(),
        ],
      ),
    );
  }
}

class _PnlSummaryTab extends ConsumerWidget {
  const _PnlSummaryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = DateTime.now().year;
    final yearlyPnl = ref.watch(yearlyPnlProvider(year));

    return yearlyPnl.when(
      data: (list) {
        if (list.isEmpty) {
          return Center(child: Text(tr('no_pnl_data', ref)));
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('$year — ${tr('monthly_breakdown', ref)}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...list.map((pnl) => _PnlMonthTile(pnl: pnl)),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(message: e.toString()),
    );
  }
}

class _PnlMonthTile extends ConsumerWidget {
  final PnlSnapshotModel pnl;
  const _PnlMonthTile({required this.pnl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isProfit = pnl.netProfit >= 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(pnl.period),
        trailing: Text(
          AppFormatters.sar(pnl.netProfit),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isProfit ? Colors.green : Colors.red,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                _DetailRow(tr('revenue', ref), pnl.revenue),
                _DetailRow(tr('cogs', ref), pnl.cogs),
                _DetailRow(tr('gross_profit', ref), pnl.grossProfit,
                    bold: true),
                _DetailRow(tr('expenses', ref), pnl.expenses),
                _DetailRow(tr('worker_cost', ref), pnl.workerCost),
                const Divider(),
                _DetailRow(tr('net_profit', ref), pnl.netProfit,
                    bold: true, color: isProfit ? Colors.green : Colors.red),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final double value;
  final bool bold;
  final Color? color;
  const _DetailRow(this.label, this.value, {this.bold = false, this.color});

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(fontWeight: FontWeight.bold, color: color)
        : Theme.of(context).textTheme.bodySmall?.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(AppFormatters.sar(value), style: style),
        ],
      ),
    );
  }
}

class _WorkerReportTab extends ConsumerWidget {
  const _WorkerReportTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments = ref.watch(allWorkerPaymentsProvider);

    return payments.when(
      data: (list) {
        if (list.isEmpty) {
          return Center(child: Text(tr('no_data', ref)));
        }

        // Group by worker
        final Map<String, _WorkerStats> stats = {};
        for (final p in list) {
          final s = stats.putIfAbsent(p.workerId,
              () => _WorkerStats(name: p.workerName, type: p.workerType));
          s.totalPaid += p.amount;
          s.totalPairs += p.pairsCount;
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(tr('worker_cost_breakdown', ref),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...stats.values.map((s) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(s.name),
                    subtitle:
                        Text('${s.type.toUpperCase()} · ${s.totalPairs} pairs'),
                    trailing: Text(AppFormatters.sar(s.totalPaid),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                )),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(message: e.toString()),
    );
  }
}

class _WorkerStats {
  final String name;
  final String type;
  double totalPaid = 0;
  int totalPairs = 0;
  _WorkerStats({required this.name, required this.type});
}

class _WasteReportTab extends ConsumerWidget {
  const _WasteReportTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wasteAsync = ref.watch(wasteRecordsProvider);

    return wasteAsync.when(
      data: (list) {
        final total = list.length;
        final disposed = list.where((r) => r.disposed).length;
        final undisposed = total - disposed;

        // Group by reason
        final Map<String, int> byReason = {};
        for (final r in list) {
          byReason[r.reason] = (byReason[r.reason] ?? 0) + 1;
        }
        final sorted = byReason.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(tr('waste_summary', ref),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: _StatChip(
                        label: tr('total', ref), value: total.toString())),
                const SizedBox(width: 8),
                Expanded(
                    child: _StatChip(
                        label: tr('disposed', ref),
                        value: disposed.toString())),
                const SizedBox(width: 8),
                Expanded(
                    child: _StatChip(
                        label: tr('pending', ref),
                        value: undisposed.toString(),
                        color: undisposed > 0 ? Colors.orange : null)),
              ],
            ),
            const SizedBox(height: 16),
            if (sorted.isNotEmpty) ...[
              Text(tr('by_reason', ref),
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              ...sorted.map(
                (e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(child: Text(e.key)),
                      Text('${e.value} items',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(message: e.toString()),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _StatChip({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (color ?? Theme.of(context).colorScheme.primary)
            .withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: color)),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
