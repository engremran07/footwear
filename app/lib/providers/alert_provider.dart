import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/shop_model.dart';
import '../models/product_variant_model.dart';
import 'product_provider.dart';
import 'shop_provider.dart';

/// Alert counts for dashboard: overdue customers + low-stock variants.
class AlertCounts {
  final int overdueCustomers;
  final int lowStockVariants;
  const AlertCounts({this.overdueCustomers = 0, this.lowStockVariants = 0});
  int get total => overdueCustomers + lowStockVariants;
}

final alertCountsProvider = Provider<AsyncValue<AlertCounts>>((ref) {
  final shopsAsync = ref.watch(shopsProvider);
  final variantsAsync = ref.watch(allVariantsProvider);

  if (shopsAsync is AsyncLoading || variantsAsync is AsyncLoading) {
    return const AsyncLoading();
  }

  final shops = shopsAsync.valueOrNull ?? const <ShopModel>[];
  final variants = variantsAsync.valueOrNull ?? const <ProductVariantModel>[];

  // Shops with outstanding balance > 0 considered "overdue"
  final overdueCount = shops.where((s) => s.balance > 0).length;
  // Variants with stock < 10 pairs considered low-stock
  final lowStock = variants.where((v) => v.quantityAvailable < 10).length;

  return AsyncData(AlertCounts(
    overdueCustomers: overdueCount,
    lowStockVariants: lowStock,
  ));
});
