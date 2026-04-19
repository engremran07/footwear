import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/constants/app_brand.dart';
import '../core/design/app_animations.dart';
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

  void _showPendingEditRequestsSheet(
    BuildContext context,
    WidgetRef ref,
    List<TransactionModel> pendingEdits,
  ) {
    if (pendingEdits.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(
                  'pending_edit_requests_count',
                  ref,
                ).replaceAll('%s', '${pendingEdits.length}'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppTokens.s8),
              Text(
                tr('pending_edit_requests_subtitle', ref),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppTokens.s12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(sheetContext).size.height * 0.6,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: pendingEdits.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final tx = pendingEdits[index];
                    return ListTile(
                      leading: const Icon(
                        Icons.pending_actions,
                        color: AppBrand.warningColor,
                      ),
                      title: Text(
                        tx.shopName.isNotEmpty ? tx.shopName : tx.shopId,
                      ),
                      subtitle: Text(
                        '${AppFormatters.dateTime(tx.createdAt)} • '
                        '${AppFormatters.currency(tx.amount)}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: tx.shopId.isEmpty
                          ? null
                          : () {
                              Navigator.pop(sheetContext);
                              context.push('/shops/${tx.shopId}');
                            },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider).value;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!user.isAdmin) {
      return _SellerDashboard(user: user);
    }

    final stats = ref.watch(dashboardStatsProvider);
    final ppc = ref.watch(settingsProvider).value?.pairsPerCarton ?? 12;
    final routesAsync = ref.watch(routesProvider);
    final shopsAsync = ref.watch(shopsProvider);
    final pendingEditsAsync = ref.watch(pendingEditRequestsProvider);

    return Scaffold(
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
            // Outstanding balance always from the LIVE shops stream — never from
            // the dashboardStatsProvider cache. This ensures immediate consistency
            // after any balance change or DB-level data flush.
            final totalOutstanding =
                shopsAsync.value?.fold<double>(
                  0.0,
                  (sum, sh) => sum + sh.balance,
                ) ??
                0.0;
            final pendingEdits =
                pendingEditsAsync.value ?? const <TransactionModel>[];
            // Alerts: outstanding > 0 is a warning banner
            final hasOutstandingAlert = totalOutstanding > 0;
            final hasPendingEditRequests = pendingEdits.isNotEmpty;

            return ListView(
              padding: const EdgeInsets.all(AppTokens.s16),
              children: [
                // Welcome
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTokens.s16),
                  child: Text(
                    '${tr('welcome', ref)}, ${user.displayName}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ).animate().fadeIn(duration: AppTokens.durNormal),

                // Alerts banner
                if (hasOutstandingAlert)
                  _OutstandingAlertCard(
                        currencyStats: s.currencyStats,
                        // NOTE: no /customers route — shops are the customers
                        onViewCurrency: (c) => context.go('/shops?currency=$c'),
                      )
                      .animate()
                      .fadeIn(duration: AppTokens.durNormal)
                      .slideY(begin: -0.1, end: 0, curve: AppTokens.curveStd),

                if (hasOutstandingAlert) const SizedBox(height: AppTokens.s12),

                if (hasPendingEditRequests)
                  Card(
                    color: AppBrand.primaryColor.withAlpha(18),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppTokens.brMD,
                      side: BorderSide(
                        color: AppBrand.primaryColor.withAlpha(64),
                      ),
                    ),
                    child: ListTile(
                      leading: const Icon(
                        Icons.pending_actions,
                        color: AppBrand.primaryColor,
                      ),
                      title: Text(
                        tr(
                          'pending_edit_requests_count',
                          ref,
                        ).replaceAll('%s', '${pendingEdits.length}'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(tr('pending_edit_requests_subtitle', ref)),
                      trailing: TextButton(
                        onPressed: () => _showPendingEditRequestsSheet(
                          context,
                          ref,
                          pendingEdits,
                        ),
                        child: Text(tr('lbl_view', ref)),
                      ),
                      onTap: () => _showPendingEditRequestsSheet(
                        context,
                        ref,
                        pendingEdits,
                      ),
                    ),
                  ).screenEntry(),

                if (hasPendingEditRequests)
                  const SizedBox(height: AppTokens.s12),

                // Stat cards grid
                GridView.count(
                  crossAxisCount: MediaQuery.of(context).size.width > 600
                      ? 3
                      : 2,
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
                    _OutstandingStatCard(
                      title: tr('outstanding_balance', ref),
                      currencyStats: s.currencyStats,
                      totalOutstanding: totalOutstanding,
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
                      subtitle: tr(
                        'dashboard_pairs_remainder',
                        ref,
                      ).replaceAll('%s', '${s.totalStockPairs % ppc}'),
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
                ),
              ],
            ).screenEntry();
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
    final routeIds = user.assignedRouteIds;
    if (routeIds.isEmpty) {
      return Scaffold(
        body: Center(child: Text(tr('dashboard_no_route_assigned', ref))),
      );
    }

    final routesAsync = ref.watch(routesBySellerProvider(user.id));
    final shopsAsync = ref.watch(sellerAllShopsProvider);
    final inventoryPairsAsync = ref.watch(
      sellerInventoryTotalPairsProvider(user.id),
    );

    // Unified loading gate: show shimmer until routes AND shops both settle.
    // Prevents route cards rendering with zero shop data (causing flicker) and
    // prevents independent-section spinners popping in at different times.
    if (routesAsync.isLoading || shopsAsync.isLoading) {
      return Scaffold(
        body: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(routesBySellerProvider(user.id));
            ref.invalidate(sellerAllShopsProvider);
          },
          child: ShimmerLoading.cards(),
        ),
      );
    }

    // Degrade gracefully on error (permission errors during auth warm-up are silent).
    if (routesAsync.hasError &&
        !AppErrorMapper.isPermissionOrAuthError(routesAsync.error!)) {
      return Scaffold(
        body: Center(
          child: Text(tr(AppErrorMapper.key(routesAsync.error!), ref)),
        ),
      );
    }
    if (shopsAsync.hasError &&
        !AppErrorMapper.isPermissionOrAuthError(shopsAsync.error!)) {
      return Scaffold(
        body: Center(
          child: Text(tr(AppErrorMapper.key(shopsAsync.error!), ref)),
        ),
      );
    }

    // All data is ready — extract synchronously (no nested .when()).
    final routes = routesAsync.value ?? const <RouteModel>[];
    final shops = shopsAsync.value ?? const <ShopModel>[];
    // Inventory: use .value if loaded, 0 while still loading — stat grid
    // renders immediately without a nested spinner.
    final pairs = inventoryPairsAsync.value ?? 0;

    final outstanding = shops.fold<double>(0, (acc, s) => acc + s.balance);
    final hasMultipleRoutes = routeIds.length > 1;
    // Currency from the first assigned route — no extra provider watch needed.
    final primaryCurrency = routes.firstOrNull?.currency ?? 'SAR';
    final sortedRoutes = List.of(routes)
      ..sort((a, b) => a.routeNumber.compareTo(b.routeNumber));

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(routesBySellerProvider(user.id));
          ref.invalidate(sellerAllShopsProvider);
          ref.invalidate(sellerInventoryProvider(user.id));
          ref.invalidate(sellerInventoryTotalPairsProvider(user.id));
          for (final rid in routeIds) {
            ref.invalidate(routeDetailProvider(rid));
          }
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                '${tr('welcome', ref)}, ${user.displayName}',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),

            // Route cards — rendered once with correct shop data (no double rebuild).
            if (sortedRoutes.isNotEmpty)
              Column(
                children: sortedRoutes.map((route) {
                  final routeShops = shops
                      .where((shop) => shop.routeId == route.id)
                      .toList();
                  final routeOutstanding = routeShops.fold<double>(
                    0,
                    (sum, shop) => sum + shop.balance,
                  );

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => context.push('/routes/${route.id}'),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '${route.routeNumber}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          route.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          [
                                            if (route.area?.isNotEmpty == true)
                                              route.area,
                                            route.currency,
                                          ].join(' · '),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _SellerRouteMetricChip(
                                      icon: Icons.storefront,
                                      label: tr('shops', ref),
                                      value: '${routeShops.length}',
                                      color: AppBrand.secondaryColor,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _SellerRouteMetricChip(
                                      icon: Icons.account_balance_wallet,
                                      label: tr('outstanding_balance', ref),
                                      value: AppFormatters.currency(
                                        routeOutstanding,
                                        route.currency,
                                      ),
                                      color: routeOutstanding > 0
                                          ? AppBrand.errorColor
                                          : AppBrand.successColor,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

            const SizedBox(height: 12),

            // Stat grid — rendered immediately with whatever inventory value
            // is available (0 while still streaming) — no nested spinner.
            GridView.count(
              crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
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
                  value: hasMultipleRoutes
                      ? AppFormatters.compact(outstanding)
                      : AppFormatters.currency(outstanding, primaryCurrency),
                  subtitle: hasMultipleRoutes
                      ? '${routeIds.length} ${tr('routes', ref).toLowerCase()}'
                      : null,
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
          ],
        ),
      ),
    );
  }
}

class _SellerRouteMetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SellerRouteMetricChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Extracted Route Analytics Section ───────────────────────────────────────

class _RouteAnalytics {
  final RouteModel route;
  final int totalShops;
  final double outstanding;

  const _RouteAnalytics({
    required this.route,
    required this.totalShops,
    required this.outstanding,
  });
}

class _RouteAnalyticsSection extends ConsumerWidget {
  final AsyncValue<List<RouteModel>> routesAsync;
  final AsyncValue<List<ShopModel>> shopsAsync;

  const _RouteAnalyticsSection({
    required this.routesAsync,
    required this.shopsAsync,
  });

  List<_RouteAnalytics> _compute(
    List<RouteModel> routes,
    List<ShopModel> shops,
  ) {
    final routeIds = routes.map((r) => r.id).toSet();
    final shopsByRoute = <String, List<ShopModel>>{};
    for (final s in shops.where((s) => routeIds.contains(s.routeId))) {
      shopsByRoute.putIfAbsent(s.routeId, () => []).add(s);
    }

    return routes.map((route) {
      final rs = shopsByRoute[route.id] ?? const <ShopModel>[];
      return _RouteAnalytics(
        route: route,
        totalShops: rs.length,
        outstanding: rs.fold<double>(0.0, (s, sh) => s + sh.balance),
      );
    }).toList()..sort((a, b) => b.outstanding.compareTo(a.outstanding));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routes = routesAsync.value;
    final shops = shopsAsync.value;

    if (routes == null || shops == null) {
      return const SizedBox.shrink();
    }

    final analytics = _compute(routes, shops);
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
                subtitle: Text('${row.totalShops} ${tr('shops', ref)}'),
                trailing: Text(
                  AppFormatters.currency(row.outstanding, row.route.currency),
                  style: TextStyle(
                    color: row.outstanding > 0
                        ? AppBrand.errorColor
                        : AppBrand.successColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
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

// ─── Outstanding Alert Banner (per-currency with View buttons) ──────────────

class _OutstandingAlertCard extends ConsumerWidget {
  final Map<String, CurrencyStats> currencyStats;
  final void Function(String currency) onViewCurrency;

  const _OutstandingAlertCard({
    required this.currencyStats,
    required this.onViewCurrency,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = currencyStats.entries
        .where((e) => e.value.outstanding > 0)
        .toList();
    if (entries.isEmpty) return const SizedBox.shrink();

    return Card(
      color: AppBrand.warningColor.withAlpha(25),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppTokens.brMD,
        side: BorderSide(color: AppBrand.warningColor.withAlpha(76)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppBrand.warningColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  tr('outstanding_balance', ref),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              tr('dashboard_pending_dues', ref),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            ...entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppFormatters.currency(e.value.outstanding, e.key),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppBrand.errorColor,
                        ),
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: () => onViewCurrency(e.key),
                      child: Text(tr('lbl_view', ref)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Outstanding Stat Card (multi-currency stacked) ───────────────────────────

class _OutstandingStatCard extends ConsumerWidget {
  final String title;
  final Map<String, CurrencyStats> currencyStats;
  final double totalOutstanding;
  final int staggerIndex;
  final VoidCallback onTap;

  const _OutstandingStatCard({
    required this.title,
    required this.currencyStats,
    required this.totalOutstanding,
    required this.staggerIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cardColor = totalOutstanding > 0
        ? AppBrand.errorColor
        : AppBrand.successColor;
    final entries = currencyStats.entries.toList();
    final semanticLabel = entries.isEmpty
        ? AppFormatters.currency(0)
        : entries
              .map((e) => AppFormatters.currency(e.value.outstanding, e.key))
              .join(', ');

    return Semantics(
          key: ValueKey('stat_outstanding_$staggerIndex'),
          label: '$title: $semanticLabel',
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                onTap();
              },
              child: Padding(
                padding: const EdgeInsets.all(AppTokens.s12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: cardColor.withValues(alpha: 0.12),
                            borderRadius: AppTokens.brSM,
                          ),
                          child: Icon(
                            Icons.account_balance_wallet,
                            color: cardColor,
                            size: AppTokens.iconSizeSM,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (entries.isEmpty)
                      Text(
                        AppFormatters.currency(0),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: cardColor,
                        ),
                      )
                    else
                      ...entries.map(
                        (e) => FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            AppFormatters.currency(e.value.outstanding, e.key),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: cardColor,
                              fontSize: entries.length == 1 ? null : 16,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        )
        .animate()
        .fadeIn(
          duration: AppTokens.durNormal,
          delay: Duration(milliseconds: 60 * staggerIndex),
          curve: AppTokens.curveEnter,
        )
        .slideY(
          begin: 0.1,
          end: 0,
          duration: AppTokens.durNormal,
          delay: Duration(milliseconds: 60 * staggerIndex),
          curve: AppTokens.curveEnter,
        );
  }
}

// ─── Admin Speed Dial FAB ────────────────────────────────────────────────────

class _AdminSpeedDial extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider).value;
    if (user == null || !user.isAdmin) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FloatingActionButton.small(
          heroTag: 'fab_shop',
          tooltip: tr('new_shop', ref),
          onPressed: () => context.push('/shops/new'),
          child: const Icon(Icons.store),
        ),
        const SizedBox(height: AppTokens.s8),
        FloatingActionButton.small(
          heroTag: 'fab_invoice',
          tooltip: tr('dashboard_new_invoice', ref),
          onPressed: () => context.push('/invoices/new'),
          child: const Icon(Icons.receipt_long),
        ),
        const SizedBox(height: AppTokens.s8),
        FloatingActionButton(
          heroTag: 'fab_main',
          tooltip: tr('dashboard_quick_actions', ref),
          onPressed: () => context.go('/inventory'),
          child: const Icon(Icons.add),
        ),
      ],
    );
  }
}
