import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/error_mapper.dart';
import '../models/product_model.dart';
import '../models/product_variant_model.dart';
import '../models/route_model.dart';
import '../models/shop_model.dart';
import 'auth_provider.dart';
import 'product_provider.dart';
import 'route_provider.dart';
import 'shop_provider.dart';

/// Dashboard stats computed reactively from live Firestore stream providers.
class DashboardStats {
  final int totalRoutes;
  final int totalShops;
  final int totalProducts;
  final int totalVariants;
  final int totalStockPairs;

  const DashboardStats({
    this.totalRoutes = 0,
    this.totalShops = 0,
    this.totalProducts = 0,
    this.totalVariants = 0,
    this.totalStockPairs = 0,
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
  if (user.isAdmin) {
    routes = ref.watch(routesProvider);
    shops = ref.watch(shopsProvider);
  } else {
    routes = ref.watch(routesBySellerProvider(user.id));
    final routeId = user.assignedRouteId ?? '';
    shops = routeId.isNotEmpty
        ? ref.watch(shopsByRouteProvider(routeId))
        : const AsyncData([]);
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

  final stats = DashboardStats(
    totalRoutes: routeList.length,
    totalShops: shopList.length,
    totalProducts: productList.length,
    totalVariants: variantList.length,
    totalStockPairs: totalStockPairs,
  );

  // Persist the latest successful computation for use as a fallback.
  Future.microtask(
    () => ref.read(_lastGoodDashboardStatsProvider.notifier).set(stats),
  );

  return AsyncData(stats);
});
