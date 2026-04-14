import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/design/app_animations.dart';
import '../core/l10n/app_locale.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/formatters.dart';
import '../core/utils/pdf_export.dart';
import '../core/utils/snack_helper.dart';
import '../models/shop_model.dart';
import '../models/transaction_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/product_provider.dart';
import '../providers/seller_inventory_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/shop_provider.dart';
import '../providers/transaction_provider.dart';
import '../providers/user_provider.dart';
import '../widgets/export_sheet.dart';
import '../widgets/error_state.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  void _showNoData(BuildContext context, WidgetRef ref) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(infoSnackBar(tr('no_data', ref)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authUserProvider);
    final stats = ref.watch(dashboardStatsProvider);
    final shopsAsync = ref.watch(shopsProvider);
    final ppc = ref.watch(settingsProvider).value?.pairsPerCarton ?? 12;
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Summary card
          stats.when(
            data: (s) {
              // Outstanding always from live shops stream — never from stats cache
              final totalOutstanding =
                  shopsAsync.value?.fold<double>(
                    0.0,
                    (acc, sh) => acc + sh.balance,
                  ) ??
                  0.0;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('summary', ref),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      _Row(
                        label: tr('total_routes', ref),
                        value: '${s.totalRoutes}',
                      ),
                      _Row(
                        label: tr('total_shops', ref),
                        value: '${s.totalShops}',
                      ),
                      _Row(
                        label: tr('outstanding_balance', ref),
                        value: AppFormatters.sar(totalOutstanding),
                      ),
                      _Row(
                        label: tr('total_products', ref),
                        value: '${s.totalProducts}',
                      ),
                      _Row(
                        label: tr('total_variants', ref),
                        value: '${s.totalVariants}',
                      ),
                      _Row(
                        label: tr('stock_pairs', ref),
                        value: AppFormatters.stock(s.totalStockPairs, ppc),
                      ),
                    ],
                  ),
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => mappedErrorState(
              error: e,
              ref: ref,
              onRetry: () => ref.invalidate(dashboardStatsProvider),
            ),
          ),
          const SizedBox(height: 16),
          // Monthly Cash Flow Chart
          _MonthlyCashFlowChart(),
          const SizedBox(height: 16),
          // Outstanding Distribution Chart
          _OutstandingPieChart(),
          const SizedBox(height: 16),
          // Export sections
          _ExportCard(
            icon: Icons.storefront,
            title: tr('shops_report', ref),
            onExport: () => _exportShops(context, ref),
          ),
          _ExportCard(
            icon: Icons.inventory_2,
            title: tr('inventory_report', ref),
            onExport: () => _exportInventory(context, ref, ppc),
          ),
          _ExportCard(
            icon: Icons.receipt_long,
            title: tr('transactions_report', ref),
            onExport: () => _exportTransactions(context, ref),
          ),
          _ExportCard(
            icon: Icons.account_balance_wallet,
            title: tr('outstanding_report', ref),
            onExport: () => _exportOutstanding(context, ref),
          ),
          _ExportCard(
            icon: Icons.money_off,
            title: tr('bad_debts_report', ref),
            onExport: () => _exportBadDebts(context, ref),
          ),
          const _AccountStatementCard(),
          const _SellerReportCard(),
        ],
      ).screenEntry(),
    );
  }

  void _exportShops(BuildContext context, WidgetRef ref) {
    final user = ref.read(authUserProvider).value;
    if (user == null) {
      _showNoData(context, ref);
      return;
    }
    final routeId = user.assignedRouteId ?? '';
    final shops = user.isAdmin
        ? ref.read(shopsProvider).value ?? <ShopModel>[]
        : (routeId.isNotEmpty
              ? ref.read(shopsByRouteProvider(routeId)).value ?? <ShopModel>[]
              : <ShopModel>[]);
    if (shops.isEmpty) {
      _showNoData(context, ref);
      return;
    }
    final title = tr('shops_report', ref);
    final headers = [
      tr('name', ref),
      tr('route', ref),
      tr('phone', ref),
      tr('area', ref),
      tr('city', ref),
      tr('balance', ref),
    ];
    final rows = shops
        .map(
          (s) => [
            s.name,
            'R${s.routeNumber}',
            s.phone ?? '',
            s.area ?? '',
            s.city ?? '',
            AppFormatters.sar(s.balance),
          ],
        )
        .toList();
    ExportSheet.show(
      context,
      ref,
      title: title,
      headers: headers,
      rows: rows,
      fileName: 'shops_report',
    );
  }

  void _exportInventory(
    BuildContext context,
    WidgetRef ref,
    int ppc,
  ) {
    final user = ref.read(authUserProvider).value;
    if (user == null) {
      _showNoData(context, ref);
      return;
    }
    final rows = user.isAdmin
        ? (ref.read(allVariantsProvider).value ?? [])
              .map(
                (v) => [
                  v.variantName,
                  AppFormatters.stock(v.quantityAvailable, ppc),
                ],
              )
              .toList()
        : (ref.read(sellerInventoryProvider(user.id)).value ?? [])
              .map(
                (v) => [
                  v.variantName,
                  AppFormatters.stock(v.quantityAvailable, ppc),
                ],
              )
              .toList();
    if (rows.isEmpty) {
      _showNoData(context, ref);
      return;
    }
    final title = tr('inventory_report', ref);
    final headers = [tr('variant_name', ref), tr('stock_pairs', ref)];
    ExportSheet.show(
      context,
      ref,
      title: title,
      headers: headers,
      rows: rows,
      fileName: 'inventory_report',
    );
  }

  void _exportTransactions(BuildContext context, WidgetRef ref) {
    final user = ref.read(authUserProvider).value;
    if (user == null) {
      _showNoData(context, ref);
      return;
    }
    final txs = user.isAdmin
        ? ref.read(allTransactionsProvider).value ?? []
        : ref.read(sellerTransactionsProvider(user.id)).value ?? [];
    if (txs.isEmpty) {
      _showNoData(context, ref);
      return;
    }
    final title = tr('transactions_report', ref);
    final headers = [
      tr('date', ref),
      tr('shop_name', ref),
      tr('type', ref),
      tr('amount', ref),
      tr('description', ref),
    ];
    final rows = txs
        .map(
          (t) => [
            AppFormatters.dateTime(t.createdAt),
            t.shopName,
            t.type == 'cash_in' ? tr('cash_in', ref) : tr('cash_out', ref),
            AppFormatters.sar(t.amount),
            t.description ?? '',
          ],
        )
        .toList();
    ExportSheet.show(
      context,
      ref,
      title: title,
      headers: headers,
      rows: rows,
      fileName: 'transactions_report',
    );
  }

  void _exportOutstanding(BuildContext context, WidgetRef ref) {
    final user = ref.read(authUserProvider).value;
    if (user == null) {
      _showNoData(context, ref);
      return;
    }
    final routeId = user.assignedRouteId ?? '';
    final shops = user.isAdmin
        ? ref.read(outstandingShopsProvider).value ?? <ShopModel>[]
        : (routeId.isNotEmpty
              ? ref.read(outstandingShopsByRouteProvider(routeId)).value ??
                    <ShopModel>[]
              : <ShopModel>[]);
    if (shops.isEmpty) {
      _showNoData(context, ref);
      return;
    }
    final title = tr('outstanding_report', ref);
    final headers = [
      tr('name', ref),
      tr('route', ref),
      tr('phone', ref),
      tr('balance', ref),
    ];
    final rows = shops
        .map(
          (s) => [
            s.name,
            'R${s.routeNumber}',
            s.phone ?? '',
            AppFormatters.sar(s.balance),
          ],
        )
        .toList();
    ExportSheet.show(
      context,
      ref,
      title: title,
      headers: headers,
      rows: rows,
      fileName: 'outstanding_report',
    );
  }

  void _exportBadDebts(BuildContext context, WidgetRef ref) {
    final user = ref.read(authUserProvider).value;
    if (user == null) {
      _showNoData(context, ref);
      return;
    }
    final routeId = user.assignedRouteId ?? '';
    final shops = user.isAdmin
        ? ref.read(shopsProvider).value ?? <ShopModel>[]
        : (routeId.isNotEmpty
              ? ref.read(shopsByRouteProvider(routeId)).value ?? <ShopModel>[]
              : <ShopModel>[]);
    final badDebtShops = shops.where((s) => s.badDebt).toList();
    if (badDebtShops.isEmpty) {
      _showNoData(context, ref);
      return;
    }
    final title = tr('bad_debts_report', ref);
    final headers = [
      tr('name', ref),
      tr('phone', ref),
      tr('bad_debt_amount', ref),
      tr('date', ref),
    ];
    final rows = badDebtShops
        .map(
          (s) => [
            s.name,
            s.phone ?? '',
            AppFormatters.sar(s.badDebtAmount),
            s.badDebtDate != null ? AppFormatters.dateTime(s.badDebtDate!) : '',
          ],
        )
        .toList();
    ExportSheet.show(
      context,
      ref,
      title: title,
      headers: headers,
      rows: rows,
      fileName: 'bad_debts_report',
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onExport;
  const _ExportCard({
    required this.icon,
    required this.title,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          icon,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        trailing: const Icon(Icons.download),
        onTap: onExport,
      ),
    );
  }
}

// ─── Monthly Cash Flow Chart ─────────────────────────────────────────────────

class _MonthlyCashFlowChart extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider).value;
    final txsAsync = user?.isAdmin == true
        ? ref.watch(allTransactionsProvider)
        : ref.watch(sellerTransactionsProvider(user?.id ?? ''));
    final cs = Theme.of(context).colorScheme;

    return txsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (txs) {
        if (txs.isEmpty) return const SizedBox.shrink();

        // Aggregate by month
        final cashIn = <String, double>{};
        final cashOut = <String, double>{};
        for (final tx in txs) {
          final dt = tx.createdAt.toDate();
          final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
          if (tx.type == 'cash_in') {
            cashIn[key] = (cashIn[key] ?? 0) + tx.amount;
          } else {
            cashOut[key] = (cashOut[key] ?? 0) + tx.amount;
          }
        }

        // Take last 6 months
        final periods = AppFormatters.last12Periods().reversed
            .take(6)
            .toList()
            .reversed
            .toList();
        final displayPeriods = periods
            .where((p) => (cashIn[p] ?? 0) > 0 || (cashOut[p] ?? 0) > 0)
            .toList();
        if (displayPeriods.isEmpty) return const SizedBox.shrink();

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('cash_flow', ref),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _LegendDot(
                      color: AppTheme.clearFg(cs),
                      label: tr('cash_in', ref),
                    ),
                    const SizedBox(width: 12),
                    _LegendDot(
                      color: AppTheme.debtFg(cs),
                      label: tr('cash_out', ref),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 180,
                  child: BarChart(
                    BarChartData(
                      barGroups: List.generate(displayPeriods.length, (i) {
                        final p = displayPeriods[i];
                        return BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: cashIn[p] ?? 0,
                              color: AppTheme.clearFg(cs),
                              width: 10,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                            BarChartRodData(
                              toY: cashOut[p] ?? 0,
                              color: AppTheme.debtFg(cs),
                              width: 10,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ],
                        );
                      }),
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 48,
                            getTitlesWidget: (v, _) => Text(
                              AppFormatters.compact(v),
                              style: TextStyle(
                                fontSize: 9,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 20,
                            getTitlesWidget: (v, _) {
                              final idx = v.toInt();
                              if (idx < 0 || idx >= displayPeriods.length) {
                                return const SizedBox.shrink();
                              }
                              return Text(
                                AppFormatters.period(
                                  displayPeriods[idx],
                                ).substring(0, 3),
                                style: TextStyle(
                                  fontSize: 9,
                                  color: cs.onSurfaceVariant,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barTouchData: const BarTouchData(enabled: false),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ─── Outstanding Distribution Pie Chart ──────────────────────────────────────

class _OutstandingPieChart extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider).value;
    final shopsAsync = user?.isAdmin == true
        ? ref.watch(shopsProvider)
        : ref.watch(shopsByRouteProvider(user?.assignedRouteId ?? ''));
    final cs = Theme.of(context).colorScheme;

    return shopsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (shops) {
        final withDebt = shops.where((s) => s.balance > 0).toList()
          ..sort((a, b) => b.balance.compareTo(a.balance));
        if (withDebt.isEmpty) return const SizedBox.shrink();

        // Group: top 5 + "others"
        final top = withDebt.take(5).toList();
        final othersTotal = withDebt
            .skip(5)
            .fold<double>(0, (s, sh) => s + sh.balance);

        final colors = [
          cs.primary,
          cs.secondary,
          cs.tertiary,
          AppTheme.warningFg(cs),
          AppTheme.clearFg(cs),
          cs.onSurfaceVariant,
        ];

        final sections = <PieChartSectionData>[];
        for (var i = 0; i < top.length; i++) {
          sections.add(
            PieChartSectionData(
              value: top[i].balance,
              title: AppFormatters.sar(top[i].balance),
              color: colors[i % colors.length],
              radius: 50,
              titleStyle: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color:
                    ThemeData.estimateBrightnessForColor(
                          colors[i % colors.length],
                        ) ==
                        Brightness.dark
                    ? cs.surface
                    : cs.onSurface,
              ),
            ),
          );
        }
        if (othersTotal > 0) {
          sections.add(
            PieChartSectionData(
              value: othersTotal,
              title: AppFormatters.sar(othersTotal),
              color: colors.last,
              radius: 50,
              titleStyle: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color:
                    ThemeData.estimateBrightnessForColor(colors.last) ==
                        Brightness.dark
                    ? cs.surface
                    : cs.onSurface,
              ),
            ),
          );
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('outstanding_report', ref),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 160,
                  child: Row(
                    children: [
                      Expanded(
                        child: PieChart(
                          PieChartData(
                            sections: sections,
                            sectionsSpace: 2,
                            centerSpaceRadius: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < top.length; i++)
                            _LegendDot(
                              color: colors[i % colors.length],
                              label: top[i].name.length > 12
                                  ? '${top[i].name.substring(0, 12)}…'
                                  : top[i].name,
                            ),
                          if (othersTotal > 0)
                            _LegendDot(color: colors.last, label: 'Others'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Account Statement Card ────────────────────────────────────────────────
class _AccountStatementCard extends ConsumerStatefulWidget {
  const _AccountStatementCard();
  @override
  ConsumerState<_AccountStatementCard> createState() =>
      _AccountStatementCardState();
}

class _AccountStatementCardState extends ConsumerState<_AccountStatementCard> {
  String? _selectedShopId;
  bool _generating = false;

  String _transactionTypeLabel(TransactionModel tx) {
    return switch (tx.type) {
      TransactionModel.typeCashIn => tr('cash_in', ref),
      TransactionModel.typeCashOut => tr('cash_out', ref),
      TransactionModel.typeReturn => tr('return', ref),
      'write_off' => tr('write_off', ref),
      _ => tx.type.replaceAll('_', ' '),
    };
  }

  Map<String, String> _labels(WidgetRef ref) {
    final keys = [
      'date',
      'description',
      'sale_type',
      'debit',
      'credit',
      'running_balance',
      'account_statement',
      'opening_balance',
      'net_payable',
      'shop',
      'seller',
      'total',
      'page',
      'report_date',
      'entry_by',
      'mode',
      'cash_in',
      'cash_out',
      'total_entries',
      'generated_by',
      'duration',
    ];
    return {for (final k in keys) k: tr(k, ref)};
  }

  Future<void> _generate() async {
    if (_selectedShopId == null) return;
    setState(() => _generating = true);
    try {
      final locale = ref.read(appLocaleProvider);
      final user = ref.read(authUserProvider).value;
      final routeId = user?.assignedRouteId ?? '';
      final shops = user?.isAdmin == true
          ? ref.read(shopsProvider).value ?? <ShopModel>[]
          : (routeId.isNotEmpty
                ? ref.read(shopsByRouteProvider(routeId)).value ?? <ShopModel>[]
                : <ShopModel>[]);
      final shop = shops.firstWhere((s) => s.id == _selectedShopId);

      final txs = await ref.read(
        shopTransactionsExportProvider(_selectedShopId!).future,
      );

      final settings = await ref.read(settingsProvider.future);
      final allUsers = user?.isAdmin == true
          ? await ref.read(allUsersProvider.future)
          : <UserModel>[];
      final entryByMap = <String, String>{
        for (final u in allUsers) u.id: u.displayName,
      };
      if (user != null) entryByMap[user.id] = user.displayName;

      // Reconcile opening balance so the final running balance equals
      // the stored customer.balance regardless of transaction-count limits.
      final netTx = txs.fold<double>(0.0, (s, t) => s + t.balanceImpact);
      final labels = _labels(ref);
      final openingBalance = shop.balance - netTx;

      if (!mounted) return;
      ExportSheet.show(
        context,
        ref,
        title: '${shop.name} - ${tr('account_statement', ref)}',
        headers: [
          tr('date', ref),
          tr('type', ref),
          tr('amount', ref),
          tr('description', ref),
        ],
        rows: txs
            .map(
              (t) => [
                AppFormatters.dateTime(t.createdAt),
                _transactionTypeLabel(t),
                AppFormatters.sar(t.amount),
                t.description ?? '',
              ],
            )
            .toList(),
        fileName: 'account_statement_${shop.name.replaceAll(' ', '_')}',
        pdfBytesBuilder: () => buildPdfLedger(
          shopName: shop.name,
          companyName: settings.companyName,
          generatedBy: user?.displayName ?? '',
          openingBalance: openingBalance,
          transactions: txs,
          entryByMap: entryByMap,
          showEntryBy: true,
          dateFrom: txs.isNotEmpty ? txs.first.createdAt.toDate() : null,
          dateTo: txs.isNotEmpty ? txs.last.createdAt.toDate() : null,
          labels: labels,
          locale: locale,
          currency: settings.currency,
          logoBytes: settings.logoBytes,
        ),
      );
    } catch (e) {
      if (mounted) {
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(tr(key, ref)));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).value;
    final routeId = user?.assignedRouteId ?? '';
    final AsyncValue<List<ShopModel>> shopsAsync = user?.isAdmin == true
        ? ref.watch(shopsProvider)
        : (routeId.isNotEmpty
              ? ref.watch(shopsByRouteProvider(routeId))
              : const AsyncData(<ShopModel>[]));
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_balance,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  tr('account_statement', ref),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            shopsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => mappedErrorState(
                error: e,
                ref: ref,
                onRetry: () {
                  if (user?.isAdmin == true) {
                    ref.invalidate(shopsProvider);
                  } else if (routeId.isNotEmpty) {
                    ref.invalidate(shopsByRouteProvider(routeId));
                  }
                },
              ),
              data: (shops) => DropdownButtonFormField<String>(
                initialValue: _selectedShopId,
                decoration: InputDecoration(
                  labelText: tr('shop', ref),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                items: shops
                    .map(
                      (s) => DropdownMenuItem(value: s.id, child: Text(s.name)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedShopId = v),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _selectedShopId == null || _generating
                    ? null
                    : _generate,
                icon: _generating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf),
                label: Text(tr('export', ref)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Seller Report Card (admin only) ─────────────────────────────────────────
class _SellerReportCard extends ConsumerStatefulWidget {
  const _SellerReportCard();
  @override
  ConsumerState<_SellerReportCard> createState() => _SellerReportCardState();
}

class _SellerReportCardState extends ConsumerState<_SellerReportCard> {
  String? _selectedSellerId;
  bool _generating = false;

  Map<String, String> _labels(WidgetRef ref) {
    final keys = [
      'seller_report',
      'seller',
      'route',
      'inventory',
      'shops',
      'shop',
      'stock_sold',
      'stock_received',
      'stock_remaining',
      'revenue',
      'outstanding',
      'total',
      'pairs',
      'report_date',
      'page',
    ];
    return {for (final k in keys) k: tr(k, ref)};
  }

  Future<void> _generate() async {
    if (_selectedSellerId == null) return;
    setState(() => _generating = true);
    try {
      final locale = ref.read(appLocaleProvider);
      final users = ref.read(allUsersProvider).value ?? [];
      final seller = users.firstWhere((u) => u.id == _selectedSellerId);
      final allTxs = ref.read(allTransactionsProvider).value ?? [];
      final inventory =
          ref.read(sellerInventoryProvider(_selectedSellerId!)).value ?? [];
      final allShops = ref.read(shopsProvider).value ?? <ShopModel>[];

      // Build per-customer summary
      final txsBySeller = allTxs
          .where((t) => t.createdBy == _selectedSellerId)
          .toList();
      final customerMap = <String, SellerReportCustomer>{};
      for (final tx in txsBySeller) {
        final cid = tx.shopId;
        if (cid.isEmpty) continue;
        final cname = tx.shopName.isNotEmpty
            ? tx.shopName
            : allShops.where((s) => s.id == cid).firstOrNull?.name ?? '';
        final existing = customerMap[cid];
        final pairsSold = tx.items.fold<int>(0, (acc, item) => acc + item.qty);
        final revenue = tx.isCashOut ? tx.amount : 0.0;
        customerMap[cid] = SellerReportCustomer(
          name: cname,
          totalPairsSold: (existing?.totalPairsSold ?? 0) + pairsSold,
          totalRevenue: (existing?.totalRevenue ?? 0) + revenue,
          outstandingBalance: 0,
        );
      }
      // Add outstanding balance from shops collection
      for (final entry in customerMap.entries) {
        final match = allShops.where((s) => s.id == entry.key);
        if (match.isNotEmpty) {
          customerMap[entry.key] = SellerReportCustomer(
            name: entry.value.name,
            totalPairsSold: entry.value.totalPairsSold,
            totalRevenue: entry.value.totalRevenue,
            outstandingBalance: match.first.balance,
          );
        }
      }

      final stockReceived = inventory.fold<int>(
        0,
        (s, i) => s + i.quantityAvailable,
      );
      final stockSold = txsBySeller
          .expand((t) => t.items)
          .fold<int>(0, (s, item) => s + item.qty);
      final stockRemaining = (stockReceived - stockSold).clamp(0, 999999);

      final settings = await ref.read(settingsProvider.future);
      final labels = _labels(ref);
      if (!mounted) return;
      ExportSheet.show(
        context,
        ref,
        title: '${seller.displayName} - ${tr('seller_report', ref)}',
        headers: [
          tr('shop', ref),
          tr('stock_sold', ref),
          tr('revenue', ref),
          tr('outstanding', ref),
        ],
        rows: customerMap.values
            .map(
              (c) => [
                c.name,
                c.totalPairsSold,
                AppFormatters.sar(c.totalRevenue),
                AppFormatters.sar(c.outstandingBalance),
              ],
            )
            .toList(),
        fileName: 'seller_report_${seller.displayName.replaceAll(' ', '_')}',
        pdfBytesBuilder: () => buildPdfSellerReport(
          sellerName: seller.displayName,
          sellerPhone: seller.phone ?? '',
          routeName: seller.assignedRouteId ?? '',
          customers: customerMap.values.toList(),
          stockReceived: stockReceived,
          stockSold: stockSold,
          stockRemaining: stockRemaining,
          labels: labels,
          locale: locale,
          logoBytes: settings.logoBytes,
        ),
      );
    } catch (e) {
      if (mounted) {
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(tr(key, ref)));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authUserProvider);
    final user = authAsync.value;
    if (user == null || !user.isAdmin) return const SizedBox.shrink();

    final usersAsync = ref.watch(allUsersProvider);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.bar_chart,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  tr('seller_report', ref),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            usersAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => mappedErrorState(
                error: e,
                ref: ref,
                onRetry: () => ref.invalidate(allUsersProvider),
              ),
              data: (users) {
                final sellers = users.where((u) => u.isSeller).toList();
                return DropdownButtonFormField<String>(
                  initialValue: _selectedSellerId,
                  decoration: InputDecoration(
                    labelText: tr('select_seller', ref),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  items: sellers
                      .map(
                        (u) => DropdownMenuItem(
                          value: u.id,
                          child: Text(u.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedSellerId = v),
                );
              },
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _selectedSellerId == null || _generating
                    ? null
                    : _generate,
                icon: _generating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf),
                label: Text(tr('export', ref)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
