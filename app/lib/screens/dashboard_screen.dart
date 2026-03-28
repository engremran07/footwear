import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/formatters.dart';
import '../providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/product_provider.dart';
import '../providers/route_provider.dart';
import '../providers/seller_inventory_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/shop_provider.dart';
import '../providers/transaction_provider.dart';
import '../models/route_model.dart';
import '../models/shop_model.dart';
import '../models/transaction_model.dart';
import '../models/user_model.dart';
import '../widgets/stat_card.dart';

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

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  List<_RouteAnalytics> _buildRouteAnalytics(
    List<RouteModel> routes,
    List<ShopModel> shops,
    List<TransactionModel> transactions,
  ) {
    final routeIds = routes.map((r) => r.id).toSet();
    final relevantShops = shops.where((s) => routeIds.contains(s.routeId));
    final relevantTransactions =
        transactions.where((t) => routeIds.contains(t.routeId));

    final shopsByRoute = <String, List<ShopModel>>{};
    for (final shop in relevantShops) {
      shopsByRoute.putIfAbsent(shop.routeId, () => []).add(shop);
    }

    final txByRoute = <String, List<TransactionModel>>{};
    for (final tx in relevantTransactions) {
      txByRoute.putIfAbsent(tx.routeId, () => []).add(tx);
    }

    final rows = routes.map((route) {
      final routeShops = shopsByRoute[route.id] ?? const <ShopModel>[];
      final routeTx = txByRoute[route.id] ?? const <TransactionModel>[];

      final outstanding = routeShops.fold<double>(
        0,
        (sum, s) => sum + s.balance,
      );
      final cashOut = routeTx
          .where((t) => t.type == 'cash_out')
          .fold<double>(0, (sum, t) => sum + t.amount);
      final cashIn = routeTx
          .where((t) => t.type == 'cash_in')
          .fold<double>(0, (sum, t) => sum + t.amount);

      return _RouteAnalytics(
        route: route,
        totalShops: routeShops.length,
        outstanding: outstanding,
        cashOut: cashOut,
        cashIn: cashIn,
        transactions: routeTx.length,
      );
    }).toList();

    rows.sort((a, b) => b.netFlow.compareTo(a.netFlow));
    return rows;
  }

  Widget _buildRouteAnalyticsSection(
    BuildContext context,
    WidgetRef ref,
    List<RouteModel> routes,
    List<ShopModel> shops,
    List<TransactionModel> transactions,
  ) {
    final analytics = _buildRouteAnalytics(routes, shops, transactions);
    if (analytics.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('routes', ref),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
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
                      'Net ${AppFormatters.compact(row.netFlow)}',
                      style: TextStyle(
                        color: row.netFlow >= 0
                            ? AppBrand.successColor
                            : AppBrand.errorColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text('Due ${AppFormatters.compact(row.outstanding)}'),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider).valueOrNull;
    final isAdmin = user?.isAdmin ?? false;
    if (user != null && !isAdmin) {
      return _SellerDashboard(user: user);
    }

    final stats = ref.watch(dashboardStatsProvider);
    final ppc = ref.watch(settingsProvider).valueOrNull?.pairsPerCarton ?? 12;
    final routesAsync = isAdmin
        ? ref.watch(routesProvider)
        : ref.watch(routesBySellerProvider(user?.id ?? ''));
    final shopsAsync = ref.watch(shopsProvider);
    final transactionsAsync = ref.watch(allTransactionsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(tr('dashboard', ref))),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(routesProvider);
          ref.invalidate(shopsProvider);
          ref.invalidate(productsProvider);
          ref.invalidate(allVariantsProvider);
          ref.invalidate(allTransactionsProvider);
        },
        child: stats.when(
          data: (s) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (user != null)
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
              GridView.count(
                crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childAspectRatio: 1.5,
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
                    value: AppFormatters.compact(s.totalOutstanding),
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
                    title: 'Stock Cartons',
                    value: AppFormatters.number(s.totalStockPairs ~/ ppc),
                    subtitle: '${s.totalStockPairs % ppc} pairs remainder',
                    icon: Icons.warehouse,
                    color: AppBrand.stockColor,
                    staggerIndex: 5,
                    onTap: () => context.go('/inventory'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              routesAsync.when(
                data: (routes) => shopsAsync.when(
                  data: (shops) => transactionsAsync.when(
                    data: (transactions) => _buildRouteAnalyticsSection(
                      context,
                      ref,
                      routes,
                      shops,
                      transactions,
                    ),
                    loading: () => const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  loading: () => const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                loading: () => const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(tr(AppErrorMapper.key(e), ref))),
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
        body: const Center(
          child: Text('No route assigned to this seller account.'),
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
                        subtitle: Text('Route ${route.routeNumber}'),
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
                        title: 'My Shops',
                        value: shops.length.toString(),
                        icon: Icons.store,
                        color: AppBrand.secondaryColor,
                        staggerIndex: 0,
                        onTap: () => context.go('/shops'),
                      ),
                      StatCard(
                        title: 'Outstanding',
                        value: AppFormatters.compact(outstanding),
                        icon: Icons.account_balance_wallet,
                        color: outstanding > 0
                            ? AppBrand.errorColor
                            : AppBrand.successColor,
                        staggerIndex: 1,
                        onTap: () => context.go('/shops'),
                      ),
                      StatCard(
                        title: 'My Inventory',
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
              error: (e, _) =>
                  Center(child: Text(tr(AppErrorMapper.key(e), ref))),
            ),
          ],
        ),
      ),
    );
  }
}
