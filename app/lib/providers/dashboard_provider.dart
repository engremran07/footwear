import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/product_model.dart';
import '../models/product_variant_model.dart';
import '../models/route_model.dart';
import '../models/shop_model.dart';
import 'product_provider.dart';
import 'route_provider.dart';
import 'shop_provider.dart';

/// Dashboard stats computed reactively from live Firestore stream providers.
class DashboardStats {
  final int totalRoutes;
  final int totalShops;
  final int totalProducts;
  final int totalVariants;
  final double totalOutstanding;
  final int totalStockPairs;

  const DashboardStats({
    this.totalRoutes = 0,
    this.totalShops = 0,
    this.totalProducts = 0,
    this.totalVariants = 0,
    this.totalOutstanding = 0,
    this.totalStockPairs = 0,
  });
}

/// Derives admin dashboard stats reactively from live stream providers.
/// Updates automatically whenever any underlying Firestore collection changes.
final dashboardStatsProvider = Provider<AsyncValue<DashboardStats>>((ref) {
  final routes = ref.watch(routesProvider);
  final shops = ref.watch(shopsProvider);
  final products = ref.watch(productsProvider);
  final variants = ref.watch(allVariantsProvider);

  if (routes is AsyncLoading ||
      shops is AsyncLoading ||
      products is AsyncLoading ||
      variants is AsyncLoading) {
    return const AsyncLoading();
  }

  if (routes is AsyncError) {
    return AsyncError(
        routes.error as Object, routes.stackTrace ?? StackTrace.empty);
  }
  if (shops is AsyncError) {
    return AsyncError(
        shops.error as Object, shops.stackTrace ?? StackTrace.empty);
  }
  if (products is AsyncError) {
    return AsyncError(
        products.error as Object, products.stackTrace ?? StackTrace.empty);
  }
  if (variants is AsyncError) {
    return AsyncError(
        variants.error as Object, variants.stackTrace ?? StackTrace.empty);
  }

  final routeList = routes.valueOrNull ?? const <RouteModel>[];
  final shopList = shops.valueOrNull ?? const <ShopModel>[];
  final productList = products.valueOrNull ?? const <ProductModel>[];
  final variantList = variants.valueOrNull ?? const <ProductVariantModel>[];

  final totalOutstanding =
      shopList.fold<double>(0, (s, shop) => s + shop.balance);
  final totalStockPairs =
      variantList.fold<int>(0, (s, v) => s + v.quantityAvailable);

  return AsyncData(DashboardStats(
    totalRoutes: routeList.length,
    totalShops: shopList.length,
    totalProducts: productList.length,
    totalVariants: variantList.length,
    totalOutstanding: totalOutstanding,
    totalStockPairs: totalStockPairs,
  ));
});
