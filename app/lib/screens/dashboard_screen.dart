import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/constants/app_brand.dart';
import '../core/design/app_tokens.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/formatters.dart';
import '../providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/route_provider.dart';
import '../providers/seller_inventory_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/shop_provider.dart';
import '../providers/transaction_provider.dart';
import '../models/route_model.dart';
import '../models/shop_model.dart';
import '../models/transaction_model.dart';
import '../models/user_model.dart';
import '../widgets/app_chart_card.dart';
import '../widgets/app_section_header.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/stat_card.dart';

Widget _buildDashboardAsyncError(
  BuildContext context,
  WidgetRef ref,
  Object error, {
  Widget? fallback,
}) {
  if (AppErrorMapper.isPermissionOrAuthError(error)) {
    return fallback ?? ShimmerLoading.cards();
  }
  return Center(child: Text(tr(AppErrorMapper.key(error), ref)));
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider).valueOrNull;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('dashboard', ref))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (!user.isAdmin) {
      return _SellerDashboard(user: user);
    }

    final stats = ref.watch(dashboardStatsProvider);
    final ppc = ref.watch(settingsProvider).valueOrNull?.pairsPerCarton ?? 12;
    final routesAsync = ref.watch(routesProvider);
    final shopsAsync = ref.watch(shopsProvider);
    final transactionsAsync = ref.watch(allTransactionsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(tr('dashboard', ref))),
      floatingActionButton: _AdminSpeedDial(),
      body: RefreshIndicator(
        onRefresh: () async {
          // Refresh only the dashboard stats aggregation — derived stream
          // providers will re-query automatically. This avoids triggering
          // 5 concurrent Firestore re-subscriptions (48K reads/day on Spark tier).
          ref.invalidate(dashboardStatsProvider);
        },
        child: stats.when(
          data: (s) {
            // Alerts: outstanding > 0 is a warning banner
            final hasOutstandingAlert = s.totalOutstanding > 0;

            return ListView(
              padding: const EdgeInsets.all(AppTokens.s16),
              children: [
                // Welcome
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTokens.s16),
                  child: Text(
                    '${tr('welcome', ref)}, ${user.displayName}',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ).animate().fadeIn(duration: AppTokens.durNormal),

                // Alerts banner
                if (hasOutstandingAlert)
                  Card(
                    color: AppBrand.warningColor.withValues(alpha: 0.1),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppTokens.brMD,
                      side: BorderSide(
                          color: AppBrand.warningColor.withValues(alpha: 0.3)),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.warning_amber_rounded,
                          color: AppBrand.warningColor),
                      title: Text(
                        tr('dashboard_outstanding_alert', ref).replaceAll(
                            '%s', AppFormatters.sar(s.totalOutstanding)),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(tr('dashboard_pending_dues', ref)),
                      trailing: TextButton(
                        onPressed: () => context.go('/customers'),
                        child: Text(tr('lbl_view', ref)),
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(duration: AppTokens.durNormal)
                      .slideY(begin: -0.1, end: 0, curve: AppTokens.curveStd),

                if (hasOutstandingAlert) const SizedBox(height: AppTokens.s12),

                // Stat cards grid
                GridView.count(
                  crossAxisCount:
                      MediaQuery.of(context).size.width > 600 ? 3 : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: AppTokens.s8,
                  crossAxisSpacing: AppTokens.s8,
                  childAspectRatio: 1.2,
                  children: [
                    StatCard(
                      title: tr('total_routes', ref),
                      value: s.totalRoutes.toString(),
                      icon: Icons.route,
                      color: AppBrand.primaryColor,
                      staggerIndex: 0,
                      onTap: () => context.go('/routes'),
                    ),
                    StatCard(
                      title: tr('total_shops', ref),
                      value: s.totalShops.toString(),
                      icon: Icons.store,
                      color: AppBrand.secondaryColor,
                      staggerIndex: 1,
                      onTap: () => context.go('/shops'),
                    ),
                    StatCard(
                      title: tr('outstanding_balance', ref),
                      value: AppFormatters.sar(s.totalOutstanding),
                      icon: Icons.account_balance_wallet,
                      color: s.totalOutstanding > 0
                          ? AppBrand.errorColor
                          : AppBrand.successColor,
                      staggerIndex: 2,
                      onTap: () => context.go('/shops'),
                    ),
                    StatCard(
                      title: tr('products', ref),
                      value: s.totalProducts.toString(),
                      icon: Icons.inventory_2,
                      color: AppBrand.adminRoleColor,
                      staggerIndex: 3,
                      onTap: () => context.go('/products'),
                    ),
                    StatCard(
                      title: tr('variants', ref),
                      value: s.totalVariants.toString(),
                      icon: Icons.style,
                      color: AppBrand.warningColor,
                      staggerIndex: 4,
                      onTap: () => context.go('/inventory'),
                    ),
                    StatCard(
                      title: tr('dashboard_stock_cartons', ref),
                      value: AppFormatters.number(s.totalStockPairs ~/ ppc),
                      subtitle: tr('dashboard_pairs_remainder', ref)
                          .replaceAll('%s', '${s.totalStockPairs % ppc}'),
                      icon: Icons.warehouse,
                      color: AppBrand.stockColor,
                      staggerIndex: 5,
                      onTap: () => context.go('/inventory'),
                    ),
                  ],
                ),

                const SizedBox(height: AppTokens.s16),

                // Route analytics section (extracted)
                _RouteAnalyticsSection(
                  routesAsync: routesAsync,
                  shopsAsync: shopsAsync,
                  transactionsAsync: transactionsAsync,
                ),

                const SizedBox(height: AppTokens.s16),

                // Cash flow chart
                _CashFlowChart(transactionsAsync: transactionsAsync),
              ],
            );
          },
          loading: () => ShimmerLoading.cards(),
          error: (e, _) => _buildDashboardAsyncError(context, ref, e),
        ),
      ),
    );
  }
}

class _SellerDashboard extends ConsumerWidget {
  final UserModel user;
  const _SellerDashboard({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routeId = user.assignedRouteId;
    if (routeId == null || routeId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('dashboard', ref))),
        body: Center(
          child: Text(tr('dashboard_no_route_assigned', ref)),
        ),
      );
    }

    final routeAsync = ref.watch(routeDetailProvider(routeId));
    final shopsAsync = ref.watch(shopsByRouteProvider(routeId));
    final inventoryPairsAsync =
        ref.watch(sellerInventoryTotalPairsProvider(user.id));

    return Scaffold(
      appBar: AppBar(title: Text(tr('dashboard', ref))),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(routeDetailProvider(routeId));
          ref.invalidate(shopsByRouteProvider(routeId));
          ref.invalidate(sellerInventoryProvider(user.id));
          ref.invalidate(sellerInventoryTotalPairsProvider(user.id));
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                '${tr('welcome', ref)}, ${user.displayName}',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            routeAsync.when(
              data: (route) => route == null
                  ? const SizedBox.shrink()
                  : Card(
                      child: ListTile(
                        leading: const Icon(Icons.route),
                        title: Text(route.name),
                        subtitle: Text(tr('dashboard_route_number', ref)
                            .replaceAll('%s', '${route.routeNumber}')),
                      ),
                    ),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 12),
            shopsAsync.when(
              data: (shops) {
                final outstanding =
                    shops.fold<double>(0, (acc, shop) => acc + shop.balance);
                return inventoryPairsAsync.when(
                  data: (pairs) => GridView.count(
                    crossAxisCount:
                        MediaQuery.of(context).size.width > 600 ? 3 : 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                    childAspectRatio: 1.5,
                    children: [
                      StatCard(
                        title: tr('dashboard_my_shops', ref),
                        value: shops.length.toString(),
                        icon: Icons.store,
                        color: AppBrand.secondaryColor,
                        staggerIndex: 0,
                        onTap: () => context.go('/shops'),
                      ),
                      StatCard(
                        title: tr('dashboard_outstanding', ref),
                        value: AppFormatters.sar(outstanding),
                        icon: Icons.account_balance_wallet,
                        color: outstanding > 0
                            ? AppBrand.errorColor
                            : AppBrand.successColor,
                        staggerIndex: 1,
                        onTap: () => context.go('/shops'),
                      ),
                      StatCard(
                        title: tr('dashboard_my_inventory', ref),
                        value: AppFormatters.compact(pairs.toDouble()),
                        icon: Icons.inventory,
                        color: AppBrand.stockColor,
                        staggerIndex: 2,
                        onTap: () => context.go('/inventory'),
                      ),
                    ],
                  ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, __) => const SizedBox.shrink(),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _buildDashboardAsyncError(
                context,
                ref,
                e,
                fallback: const Center(child: CircularProgressIndicator()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Extracted Route Analytics Section ───────────────────────────────────────

class _RouteAnalytics {
  final RouteModel route;
  final int totalShops;
  final double outstanding;
  final double cashOut;
  final double cashIn;
  final int transactions;

  const _RouteAnalytics({
    required this.route,
    required this.totalShops,
    required this.outstanding,
    required this.cashOut,
    required this.cashIn,
    required this.transactions,
  });

  double get netFlow => cashOut - cashIn;
}

class _RouteAnalyticsSection extends ConsumerWidget {
  final AsyncValue<List<RouteModel>> routesAsync;
  final AsyncValue<List<ShopModel>> shopsAsync;
  final AsyncValue<List<TransactionModel>> transactionsAsync;

  const _RouteAnalyticsSection({
    required this.routesAsync,
    required this.shopsAsync,
    required this.transactionsAsync,
  });

  List<_RouteAnalytics> _compute(
    List<RouteModel> routes,
    List<ShopModel> shops,
    List<TransactionModel> transactions,
  ) {
    final routeIds = routes.map((r) => r.id).toSet();
    final shopsByRoute = <String, List<ShopModel>>{};
    for (final s in shops.where((s) => routeIds.contains(s.routeId))) {
      shopsByRoute.putIfAbsent(s.routeId, () => []).add(s);
    }
    final txByRoute = <String, List<TransactionModel>>{};
    for (final t in transactions.where((t) => routeIds.contains(t.routeId))) {
      txByRoute.putIfAbsent(t.routeId, () => []).add(t);
    }

    final rows = routes.map((route) {
      final rs = shopsByRoute[route.id] ?? const <ShopModel>[];
      final rt = txByRoute[route.id] ?? const <TransactionModel>[];
      return _RouteAnalytics(
        route: route,
        totalShops: rs.length,
        outstanding: rs.fold<double>(0, (s, sh) => s + sh.balance),
        cashOut: rt
            .where((t) => t.type == 'cash_out')
            .fold<double>(0, (s, t) => s + t.amount),
        cashIn: rt
            .where((t) => t.type == 'cash_in')
            .fold<double>(0, (s, t) => s + t.amount),
        transactions: rt.length,
      );
    }).toList()
      ..sort((a, b) => b.netFlow.compareTo(a.netFlow));
    return rows;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routes = routesAsync.valueOrNull;
    final shops = shopsAsync.valueOrNull;
    final txs = transactionsAsync.valueOrNull;

    if (routes == null || shops == null || txs == null) {
      return const SizedBox.shrink();
    }

    final analytics = _compute(routes, shops, txs);
    if (analytics.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: AppTokens.brMD),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSectionHeader(title: tr('routes', ref)),
            ...analytics.map(
              (row) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 14,
                  child: Text('${row.route.routeNumber}'),
                ),
                title: Text(row.route.name),
                subtitle: Text(
                  '${row.totalShops} ${tr('shops', ref)} • ${row.transactions} tx',
                ),
                trailing: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      tr('dashboard_net', ref)
                          .replaceAll('%s', AppFormatters.sar(row.netFlow)),
                      style: TextStyle(
                        color: row.netFlow >= 0
                            ? AppBrand.successColor
                            : AppBrand.errorColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(tr('dashboard_due', ref)
                        .replaceAll('%s', AppFormatters.sar(row.outstanding))),
                  ],
                ),
                onTap: () => context.push('/routes/${row.route.id}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Cash Flow Chart ─────────────────────────────────────────────────────────

class _CashFlowChart extends ConsumerWidget {
  final AsyncValue<List<TransactionModel>> transactionsAsync;
  const _CashFlowChart({required this.transactionsAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txs = transactionsAsync.valueOrNull;
    if (txs == null || txs.isEmpty) return const SizedBox.shrink();

    // Group transactions by month for last 6 months
    final now = DateTime.now();
    final months = <String>[];
    final cashInByMonth = <String, double>{};
    final cashOutByMonth = <String, double>{};

    for (int i = 5; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      months.add(key);
      cashInByMonth[key] = 0;
      cashOutByMonth[key] = 0;
    }

    for (final tx in txs) {
      final ts = tx.createdAt.toDate();
      final key = '${ts.year}-${ts.month.toString().padLeft(2, '0')}';
      if (tx.type == 'cash_in') {
        cashInByMonth[key] = (cashInByMonth[key] ?? 0) + tx.amount;
      } else if (tx.type == 'cash_out') {
        cashOutByMonth[key] = (cashOutByMonth[key] ?? 0) + tx.amount;
      }
    }

    final spots1 = <FlSpot>[];
    final spots2 = <FlSpot>[];
    for (int i = 0; i < months.length; i++) {
      spots1.add(FlSpot(i.toDouble(), cashInByMonth[months[i]]!));
      spots2.add(FlSpot(i.toDouble(), cashOutByMonth[months[i]]!));
    }

    final monthLabels = months.map((m) => m.substring(5)).toList(); // MM only

    return AppChartCard(
      title: tr('dashboard_cash_flow', ref),
      subtitle: tr('dashboard_last_6_months', ref),
      isEmpty: spots1.every((s) => s.y == 0) && spots2.every((s) => s.y == 0),
      legend: [
        ChartLegendItem(
            color: AppBrand.successColor,
            label: tr('dashboard_cash_in_legend', ref)),
        ChartLegendItem(
            color: AppBrand.errorColor,
            label: tr('dashboard_cash_out_legend', ref)),
      ],
      chart: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, _) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= monthLabels.length) {
                    return const SizedBox.shrink();
                  }
                  return Text(monthLabels[idx],
                      style: const TextStyle(fontSize: 10));
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots1,
              isCurved: true,
              color: AppBrand.successColor,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: AppBrand.successColor.withValues(alpha: 0.1),
              ),
            ),
            LineChartBarData(
              spots: spots2,
              isCurved: true,
              color: AppBrand.errorColor,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: AppBrand.errorColor.withValues(alpha: 0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Admin Speed Dial FAB ────────────────────────────────────────────────────

class _AdminSpeedDial extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider).valueOrNull;
    if (user == null || !user.isAdmin) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FloatingActionButton.small(
          heroTag: 'fab_customer',
          tooltip: tr('dashboard_new_customer', ref),
          onPressed: () => context.push('/customers/new'),
          child: const Icon(Icons.person_add),
        ),
        const SizedBox(height: AppTokens.s8),
        FloatingActionButton.small(
          heroTag: 'fab_invoice',
          tooltip: tr('dashboard_new_invoice', ref),
          onPressed: () => context.push('/invoices'),
          child: const Icon(Icons.receipt_long),
        ),
        const SizedBox(height: AppTokens.s8),
        FloatingActionButton(
          heroTag: 'fab_main',
          tooltip: tr('dashboard_quick_actions', ref),
          onPressed: () => context.push('/inventory'),
          child: const Icon(Icons.add),
        ),
      ],
    );
  }
}
