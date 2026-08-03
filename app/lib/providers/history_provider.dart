import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/collections.dart';
import '../core/utils/tenant_scope.dart';
import '../models/transaction_model.dart';
import 'auth_provider.dart';

const _kHistoryDays = 7;
const _kHistoryLimit = 100;

/// Live 7-day transaction feed, role-aware.
///
/// Admin → all transactions ordered by [created_at] DESC.
/// Seller → route-scoped via `route_id whereIn assignedRouteIds`.
///
/// Index coverage:
///   Admin:  single-field `created_at` (auto-indexed by Firestore).
///   Seller: composite `route_id ASC + created_at DESC` (exists in firestore.indexes.json).
final recentTransactionsProvider =
    StreamProvider.autoDispose<List<TransactionModel>>((ref) {
      final (isAdmin, isSeller, routeKey) = ref.watch(
        authUserProvider.select((s) {
          final u = s.value;
          if (u == null) return (false, false, '');
          if (u.isAdmin) return (true, false, '');
          if (!u.isSeller || u.assignedRouteIds.isEmpty) {
            return (false, false, '');
          }
          final sorted = List<String>.from(u.assignedRouteIds)..sort();
          return (false, true, sorted.join(','));
        }),
      );

      if (!isAdmin && (!isSeller || routeKey.isEmpty)) {
        return const Stream.empty();
      }

      final cutoff = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(days: _kHistoryDays)),
      );

      final tenantId = ref.watch(
        authUserProvider.select(
          (s) => TenantScope.normalize(s.value?.tenantId),
        ),
      );
      final collection = TenantScope.applyToQuery(
        FirebaseFirestore.instance.collection(Collections.transactions),
        tenantId: tenantId,
      );

      if (isAdmin) {
        return collection
            .orderBy('created_at', descending: true)
            .where('created_at', isGreaterThanOrEqualTo: cutoff)
            .limit(_kHistoryLimit)
            .snapshots()
            .map(
              (snap) => snap.docs
                  .where((d) => d.data()['deleted'] != true)
                  .map((d) => TransactionModel.fromJson(d.data(), d.id))
                  .toList(),
            );
      }

      // Seller: route-scoped
      final routeIds = routeKey.split(',');
      return collection
          .where('route_id', whereIn: routeIds)
          .orderBy('created_at', descending: true)
          .where('created_at', isGreaterThanOrEqualTo: cutoff)
          .limit(_kHistoryLimit)
          .snapshots()
          .map(
            (snap) => snap.docs
                .where((d) => d.data()['deleted'] != true)
                .map((d) => TransactionModel.fromJson(d.data(), d.id))
                .toList(),
          );
    });
