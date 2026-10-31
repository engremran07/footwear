import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/collections.dart';
import '../core/utils/permission_policy.dart';
import '../core/utils/role_names.dart';
import '../core/utils/tenant_scope.dart';
import '../models/transaction_model.dart';
import '../models/user_model.dart';
import 'auth_provider.dart';

const _kHistoryDays = 7;
const _kHistoryLimit = 100;

({String tenantId, String? routeKey})? historyQueryScopeFor(UserModel? user) {
  if (user == null || !user.active) return null;
  final tenantId = TenantScope.normalize(user.tenantId);
  if (tenantId == null) return null;
  if (!PermissionPolicy.can(user, AppCapability.viewHistory)) return null;

  if (user.isSeller) {
    final routeIds =
        user.assignedRouteIds
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (routeIds.isEmpty) return null;
    return (tenantId: tenantId, routeKey: routeIds.join(','));
  }

  return user.isAdmin || user.isSupervisor
      ? (tenantId: tenantId, routeKey: null)
      : null;
}

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
      final scope = ref.watch(
        authUserProvider.select((s) => historyQueryScopeFor(s.value)),
      );
      if (scope == null) return const Stream.empty();

      final cutoff = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(days: _kHistoryDays)),
      );

      final collection = TenantScope.applyToQuery(
        FirebaseFirestore.instance.collection(Collections.transactions),
        tenantId: scope.tenantId,
      );

      if (scope.routeKey == null) {
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
      final routeIds = scope.routeKey!.split(',');
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
