import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/error_mapper.dart';
import '../models/product_model.dart';
import '../models/product_variant_model.dart';
import '../models/route_model.dart';
import '../models/shop_model.dart';
import '../models/user_model.dart';
import 'auth_provider.dart';
import 'product_provider.dart';
import 'route_provider.dart';
import 'shop_provider.dart';
import 'tenant_provider.dart';
import 'user_provider.dart';

/// Per-currency aggregated stats for dashboard conditional widgets.
class CurrencyStats {
  final String currency;
  final int routeCount;
  final int shopCount;
  final double outstanding;

  const CurrencyStats({
    required this.currency,
    this.routeCount = 0,
    this.shopCount = 0,
    this.outstanding = 0,
  });
}

/// Dashboard stats computed reactively from live Firestore stream providers.
class DashboardStats {
  final int totalRoutes;
  final int totalShops;
  final int totalProducts;
  final int totalVariants;
  final int totalStockPairs;
  final int totalWorkspaces;
  final int activeWorkspaces;
  final int totalUsers;
  final int usersInActiveWorkspaces;

  /// Per-currency breakdown (e.g. {'SAR': CurrencyStats(...), 'PKR': ...}).
  final Map<String, CurrencyStats> currencyStats;

  const DashboardStats({
    this.totalRoutes = 0,
    this.totalShops = 0,
    this.totalProducts = 0,
    this.totalVariants = 0,
    this.totalStockPairs = 0,
    this.totalWorkspaces = 0,
    this.activeWorkspaces = 0,
    this.totalUsers = 0,
    this.usersInActiveWorkspaces = 0,
    this.currencyStats = const {},
  });
}

/// Holds the last successfully computed dashboard stats so we can serve a
/// cached result during loading states or when sub-providers temporarily error
/// (e.g. resource-exhausted). This prevents blank-screen regressions.
/// Exposed (not private) so auth_provider can invalidate it on sign-out
/// to prevent stale stats from flashing when a new user signs in (SM-01).
final lastGoodDashboardStatsProvider =
    NotifierProvider<LastGoodDashboardStatsNotifier, DashboardStats?>(
      LastGoodDashboardStatsNotifier.new,
    );

class LastGoodDashboardStatsNotifier extends Notifier<DashboardStats?> {
  @override
  DashboardStats? build() => null;

  void set(DashboardStats stats) => state = stats;
}

final _lastGoodDashboardStatsProvider = lastGoodDashboardStatsProvider;

/// Derives dashboard stats reactively from live stream providers.
/// Role-aware: admin sees all data, seller sees only their route's data.
final dashboardStatsProvider = Provider<AsyncValue<DashboardStats>>((ref) {
  final userAsync = ref.watch(authUserProvider);
  if (userAsync.isLoading) {
    final cached = ref.read(_lastGoodDashboardStatsProvider);
    return cached != null ? AsyncData(cached) : const AsyncLoading();
  }
  if (userAsync.hasError && userAsync.error != null) {
    if (AppErrorMapper.isPermissionOrAuthError(userAsync.error!)) {
      return const AsyncLoading();
    }
    final cached = ref.read(_lastGoodDashboardStatsProvider);
    return cached != null ? AsyncData(cached) : const AsyncLoading();
  }

  final user = userAsync.value;
  if (user == null) {
    final cached = ref.read(_lastGoodDashboardStatsProvider);
    return cached != null ? AsyncData(cached) : const AsyncLoading();
  }

  final AsyncValue<List<RouteModel>> routes;
  final AsyncValue<List<ShopModel>> shops;
  if (user.isSuperAdmin) {
    final workspaces = ref.watch(tenantsProvider);
    final users = ref.watch(allUsersProvider);
    if (workspaces.isLoading || users.isLoading) {
      final cached = ref.read(_lastGoodDashboardStatsProvider);
      return cached != null ? AsyncData(cached) : const AsyncLoading();
    }

    final workspaceList = workspaces.value ?? const <dynamic>[];
    final userList = users.value ?? const <UserModel>[];
    final activeWorkspaces = workspaceList.where((w) => w.active == true).length;
    final stats = DashboardStats(
      totalWorkspaces: workspaceList.length,
      activeWorkspaces: activeWorkspaces,
      totalUsers: userList.length,
      usersInActiveWorkspaces: userList.where((u) => u.active).length,
    );
    Future.microtask(
      () => ref.read(_lastGoodDashboardStatsProvider.notifier).set(stats),
    );
    return AsyncData(stats);
  }

  if (user.isAdmin) {
    routes = ref.watch(routesProvider);
    shops = ref.watch(shopsProvider);
  } else {
    routes = ref.watch(routesBySellerProvider(user.id));
    // Seller multi-route: watch shops across all assigned routes.
    final routeIds = user.assignedRouteIds;
    if (routeIds.isEmpty) {
      shops = const AsyncData([]);
    } else if (routeIds.length == 1) {
      shops = ref.watch(shopsByRouteProvider(routeIds.first));
    } else {
      // Merge shops from all assigned routes.
      final shopLists = routeIds
          .map((rid) => ref.watch(shopsByRouteProvider(rid)))
          .toList();
      if (shopLists.any((s) => s is AsyncLoading)) {
        shops = const AsyncLoading();
      } else {
        final merged = <ShopModel>[];
        for (final sl in shopLists) {
          merged.addAll(sl.value ?? const []);
        }
        shops = AsyncData(merged);
      }
    }
  }
  final products = ref.watch(productsProvider);
  final variants = ref.watch(allVariantsProvider);

  if (routes is AsyncLoading ||
      shops is AsyncLoading ||
      products is AsyncLoading ||
      variants is AsyncLoading) {
    final cached = ref.read(_lastGoodDashboardStatsProvider);
    return cached != null ? AsyncData(cached) : const AsyncLoading();
  }

  // Degrade gracefully: use zero/empty fallback for any errored sub-provider
  // instead of propagating AsyncError and blanking the entire dashboard.
  // A single quota-exhausted stream must never black out all metrics.
  final routeList = routes.value ?? const <RouteModel>[];
  final shopList = shops.value ?? const <ShopModel>[];
  final productList = products.value ?? const <ProductModel>[];
  final variantList = variants.value ?? const <ProductVariantModel>[];

  final totalStockPairs = variantList.fold<int>(
    0,
    (s, v) => s + v.quantityAvailable,
  );

  // Build per-currency breakdown from routes + shops.
  final routeCurrencyMap = <String, String>{};
  final currencyRouteCount = <String, int>{};
  for (final route in routeList) {
    routeCurrencyMap[route.id] = route.currency;
    currencyRouteCount[route.currency] =
        (currencyRouteCount[route.currency] ?? 0) + 1;
  }
  final currencyShopCount = <String, int>{};
  final currencyOutstanding = <String, double>{};
  for (final shop in shopList) {
    final cur = routeCurrencyMap[shop.routeId] ?? 'SAR';
    currencyShopCount[cur] = (currencyShopCount[cur] ?? 0) + 1;
    currencyOutstanding[cur] =
        (currencyOutstanding[cur] ?? 0) + shop.balance;
  }
  final allCurrencies = {
    ...currencyRouteCount.keys,
    ...currencyShopCount.keys,
  };
  final cStats = <String, CurrencyStats>{};
  for (final c in allCurrencies) {
    cStats[c] = CurrencyStats(
      currency: c,
      routeCount: currencyRouteCount[c] ?? 0,
      shopCount: currencyShopCount[c] ?? 0,
      outstanding: currencyOutstanding[c] ?? 0,
    );
  }

  final stats = DashboardStats(
    totalRoutes: routeList.length,
    totalShops: shopList.length,
    totalProducts: productList.length,
    totalVariants: variantList.length,
    totalStockPairs: totalStockPairs,
    currencyStats: cStats,
  );

  // Persist the latest successful computation for use as a fallback.
  Future.microtask(
    () => ref.read(_lastGoodDashboardStatsProvider.notifier).set(stats),
  );

  return AsyncData(stats);
});
