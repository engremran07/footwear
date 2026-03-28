import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';

/// Dashboard stats computed from Firestore aggregation queries.
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

final dashboardStatsCacheProvider =
    StateProvider<DashboardStats>((ref) => const DashboardStats());

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) async {
  ref.keepAlive();
  final db = FirebaseFirestore.instance;
  final cache = ref.read(dashboardStatsCacheProvider);

  Future<int> safeCount(
    Query<Map<String, dynamic>> query, {
    required int fallback,
  }) async {
    try {
      final agg = await query.count().get().timeout(const Duration(seconds: 8));
      return agg.count ?? 0;
    } on FirebaseException {
      return fallback;
    } on PlatformException {
      return fallback;
    } on TimeoutException {
      return fallback;
    } catch (e) {
      return fallback;
    }
  }

  Future<double> safeSum(
    Query<Map<String, dynamic>> query,
    String field, {
    required double fallback,
  }) async {
    try {
      final agg = await query
          .aggregate(sum(field))
          .get()
          .timeout(const Duration(seconds: 8));
      return (agg.getSum(field) ?? 0).toDouble();
    } on FirebaseException {
      return fallback;
    } on PlatformException {
      return fallback;
    } on TimeoutException {
      return fallback;
    } catch (e) {
      return fallback;
    }
  }

  final totalRoutes = await safeCount(
    db.collection(Collections.routes).where('active', isEqualTo: true),
    fallback: cache.totalRoutes,
  );
  final totalShops = await safeCount(
    db.collection(Collections.customers).where('active', isEqualTo: true),
    fallback: cache.totalShops,
  );
  final totalProducts = await safeCount(
    db.collection(Collections.products).where('active', isEqualTo: true),
    fallback: cache.totalProducts,
  );
  final totalVariants = await safeCount(
    db.collection(Collections.productVariants).where('active', isEqualTo: true),
    fallback: cache.totalVariants,
  );
  final totalOutstanding = await safeSum(
    db.collection(Collections.customers).where('active', isEqualTo: true),
    'balance',
    fallback: cache.totalOutstanding,
  );
  final totalStockPairs = await safeSum(
    db.collection(Collections.productVariants).where('active', isEqualTo: true),
    'quantity_available',
    fallback: cache.totalStockPairs.toDouble(),
  );

  final result = DashboardStats(
    totalRoutes: totalRoutes,
    totalShops: totalShops,
    totalProducts: totalProducts,
    totalVariants: totalVariants,
    totalOutstanding: totalOutstanding,
    totalStockPairs: totalStockPairs.toInt(),
  );

  ref.read(dashboardStatsCacheProvider.notifier).state = result;
  return result;
});
