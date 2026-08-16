import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../core/utils/role_utils.dart';
import '../core/utils/tenant_scope.dart';
import '../models/route_model.dart';
import 'auth_provider.dart';

final routesProvider = StreamProvider.autoDispose<List<RouteModel>>((ref) {
  ref.keepAlive();
  // Admin-only unfiltered query: guard so non-admin credentials never
  // subscribe, avoiding PERMISSION_DENIED during auth transitions.
  // Use select() so heartbeat writes to last_active do NOT restart the stream.
  final isAdmin = ref.watch(
    authUserProvider.select((s) => s.value?.isAdmin ?? false),
  );
  final tenantId = ref.watch(
    authUserProvider.select((s) => TenantScope.normalize(s.value?.tenantId)),
  );
  if (!isAdmin) return const Stream.empty();
  final query = TenantScope.applyToQuery(
    FirebaseFirestore.instance.collection(Collections.routes),
    tenantId: tenantId,
  );
  return query
      .where('active', isEqualTo: true)
      .orderBy('route_number')
      .limit(200)
      .snapshots()
      .map(
        (snap) =>
            snap.docs.map((d) => RouteModel.fromJson(d.data(), d.id)).toList(),
      );
});

final routeDetailProvider = StreamProvider.autoDispose
    .family<RouteModel?, String>((ref, id) {
      // Use select() with a stable key so heartbeat writes to last_active
      // do NOT restart the Firestore stream.
      final (isAdmin, isSeller, userId) = ref.watch(
        authUserProvider.select((s) {
          final u = s.value;
          if (u == null) return (false, false, '');
          return (u.isAdmin, u.isSeller, u.id);
        }),
      );
      final tenantId = ref.watch(
        authUserProvider.select(
          (s) => TenantScope.normalize(s.value?.tenantId),
        ),
      );
      if (!isAdmin && !isSeller) return const Stream.empty();
      if (isAdmin) {
        return FirebaseFirestore.instance
            .collection(Collections.routes)
            .doc(id)
            .snapshots()
            .map((doc) {
              if (!doc.exists) return null;
              if (!TenantScope.matchesTenant(doc.data(), tenantId)) return null;
              return RouteModel.fromJson(doc.data()!, doc.id);
            });
      }
      if (!isSeller || userId.isEmpty) return const Stream.empty();
      // Multi-seller: read doc by ID, verify membership client-side.
      return FirebaseFirestore.instance
          .collection(Collections.routes)
          .doc(id)
          .snapshots()
          .map((doc) {
            if (!doc.exists) return null;
            if (!TenantScope.matchesTenant(doc.data(), tenantId)) return null;
            final route = RouteModel.fromJson(doc.data()!, doc.id);
            // Check both new array and legacy scalar for un-migrated docs.
            if (route.assignedSellerIds.contains(userId)) return route;
            return null;
          });
    });

/// Resolves the currency symbol for a given route ID.
/// Watches [routeDetailProvider] so it stays live and updates reactively.
/// Falls back to 'SAR' while the route is loading or when routeId is empty.
final routeCurrencyProvider = Provider.autoDispose.family<String, String>((
  ref,
  routeId,
) {
  if (routeId.isEmpty) return 'SAR';
  return ref.watch(routeDetailProvider(routeId)).value?.currency ?? 'SAR';
});

final routesBySellerProvider = StreamProvider.autoDispose
    .family<List<RouteModel>, String>((ref, sellerId) {
      ref.keepAlive();
      if (sellerId.isEmpty) return const Stream.empty();
      // Auth guard: only subscribe once Firebase has confirmed a valid user.
      // Without this the subscription fires before the auth token is ready,
      // causing an immediate PERMISSION_DENIED → AsyncError(hasValue: false)
      // → shimmer loop that repeats until Firestore's internal retry succeeds.
      final isAuthReady = ref.watch(
        authUserProvider.select((s) => s.value != null),
      );
      if (!isAuthReady) return const Stream.empty();
      final tenantId = ref.watch(
        authUserProvider.select(
          (s) => TenantScope.normalize(s.value?.tenantId),
        ),
      );
      final query = TenantScope.applyToQuery(
        FirebaseFirestore.instance.collection(Collections.routes),
        tenantId: tenantId,
      );
      return query
          .where('assigned_seller_ids', arrayContains: sellerId)
          .where('active', isEqualTo: true)
          .orderBy('route_number')
          .limit(100)
          .snapshots()
          .map(
            (snap) => snap.docs
                .map((d) => RouteModel.fromJson(d.data(), d.id))
                .toList(),
          );
    });

class RouteNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Reconciles each route's `total_shops` against active shops in Firestore.
  /// Safe to run after partial DB flushes so route counters self-heal.
  Future<void> reconcileRouteShopCounters() async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) return;

    final db = FirebaseFirestore.instance;
    final me = await db.collection(Collections.users).doc(authUser.uid).get();
    final role = (me.data()?['role'] as String? ?? '').trim();
    if (!isPrivilegedRoleName(role)) return;

    final routesSnap = await db
        .collection(Collections.routes)
        .where('active', isEqualTo: true)
        .limit(500)
        .get();
    if (routesSnap.docs.isEmpty) return;

    final shopsSnap = await db
        .collection(Collections.customers)
        .where('active', isEqualTo: true)
        .limit(2000)
        .get();

    final countsByRoute = <String, int>{};
    for (final shop in shopsSnap.docs) {
      final routeId = (shop.data()['route_id'] as String?)?.trim() ?? '';
      if (routeId.isEmpty) continue;
      countsByRoute[routeId] = (countsByRoute[routeId] ?? 0) + 1;
    }

    final batch = db.batch();
    var changed = 0;
    for (final route in routesSnap.docs) {
      final currentTotal = (route.data()['total_shops'] as int?) ?? 0;
      final computedTotal = countsByRoute[route.id] ?? 0;
      if (currentTotal != computedTotal) {
        changed += 1;
        batch.update(route.reference, {
          'total_shops': computedTotal,
          'updated_at': Timestamp.now(),
        });
      }
    }

    if (changed > 0) {
      await batch.commit();
    }
  }

  Future<int> _nextRouteNumber(FirebaseFirestore db) async {
    final snap = await db
        .collection(Collections.routes)
        .orderBy('route_number', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return 1;
    final currentMax = snap.docs.first.data()['route_number'] as int? ?? 0;
    return currentMax + 1;
  }

  Future<void> create(Map<String, dynamic> data) async {
    final db = FirebaseFirestore.instance;
    final currentUser = ref.read(authUserProvider).value;
    final tenantId = TenantScope.normalize(currentUser?.tenantId) ??
        TenantScope.globalTenantId;
    final routeRef = db.collection(Collections.routes).doc();
    final routeName = data['name'] as String? ?? '';
    final currency = data['currency'] as String? ?? 'SAR';
    final sellerIds =
        (data['assigned_seller_ids'] as List<dynamic>?)
            ?.cast<String>()
            .where((s) => s.trim().isNotEmpty)
            .toList() ??
        const <String>[];
    final sellerNames =
        (data['assigned_seller_names'] as List<dynamic>?)
            ?.cast<String>()
            .toList() ??
        const <String>[];
    final routeNumber = ((data['route_number'] as int?) ?? 0) > 0
        ? (data['route_number'] as int)
        : await _nextRouteNumber(db);

    await db.runTransaction<void>((txn) async {
      // Verify all sellers exist.
      final sellerRefs = <DocumentReference<Map<String, dynamic>>>[];
      for (final sid in sellerIds) {
        final ref = db.collection(Collections.users).doc(sid);
        final snap = await txn.get(ref);
        if (!snap.exists) throw StateError('Seller not found');
        sellerRefs.add(ref);
      }

      final now = Timestamp.now();
      txn.set(routeRef, {
        ...TenantScope.applyToData(data, tenantId: tenantId),
        'assigned_seller_ids': sellerIds,
        'assigned_seller_names': sellerNames,
        'currency': currency,
        'route_number': routeNumber,
        'total_shops': 0,
        'active': true,
        'created_at': now,
        'updated_at': now,
      });

      // Add this route to each seller's assigned_route_ids array.
      for (var i = 0; i < sellerRefs.length; i++) {
        txn.update(sellerRefs[i], {
          'assigned_route_ids': FieldValue.arrayUnion([routeRef.id]),
          'assigned_route_names': FieldValue.arrayUnion([routeName]),
          'updated_at': now,
        });
      }
    });
  }

  Future<void> updateRoute(String id, Map<String, dynamic> data) async {
    final db = FirebaseFirestore.instance;
    final routeRef = db.collection(Collections.routes).doc(id);
    await db.runTransaction<void>((txn) async {
      final currentRoute = await txn.get(routeRef);
      if (!currentRoute.exists) {
        throw StateError('Route not found');
      }

      final routeName =
          data['name'] as String? ??
          currentRoute.data()?['name'] as String? ??
          '';
      final tenantId = TenantScope.normalize(
            ref.read(authUserProvider).value?.tenantId,
          ) ??
          TenantScope.globalTenantId;
      final currency =
          data['currency'] as String? ??
          currentRoute.data()?['currency'] as String? ??
          'SAR';

      // Old seller IDs from current route doc.
      final oldRaw =
          currentRoute.data()?['assigned_seller_ids'] as List<dynamic>?;
      final oldSellerIds = oldRaw != null
          ? oldRaw.cast<String>().toSet()
          : <String>{};

      // New seller IDs from form data.
      final newSellerIds =
          (data['assigned_seller_ids'] as List<dynamic>?)
              ?.cast<String>()
              .where((s) => s.trim().isNotEmpty)
              .toSet() ??
          <String>{};
      final newSellerNames =
          (data['assigned_seller_names'] as List<dynamic>?)
              ?.cast<String>()
              .toList() ??
          const <String>[];

      final removed = oldSellerIds.difference(newSellerIds);
      final added = newSellerIds.difference(oldSellerIds);

      // Verify all new sellers exist.
      for (final sid in added) {
        final ref = db.collection(Collections.users).doc(sid);
        final snap = await txn.get(ref);
        if (!snap.exists) throw StateError('Seller not found');
      }

      final now = Timestamp.now();
      txn.update(routeRef, {
        ...TenantScope.applyToData(data, tenantId: tenantId),
        'assigned_seller_ids': newSellerIds.toList(),
        'assigned_seller_names': newSellerNames,
        'currency': currency,
        'updated_at': now,
      });

      // Remove this route from removed sellers.
      for (final sid in removed) {
        txn.update(db.collection(Collections.users).doc(sid), {
          'assigned_route_ids': FieldValue.arrayRemove([id]),
          'assigned_route_names': FieldValue.arrayRemove([routeName]),
          'updated_at': now,
        });
      }

      // Add this route to newly added sellers.
      for (final sid in added) {
        txn.update(db.collection(Collections.users).doc(sid), {
          'assigned_route_ids': FieldValue.arrayUnion([id]),
          'assigned_route_names': FieldValue.arrayUnion([routeName]),
          'updated_at': now,
        });
      }
    });
  }

  Future<void> delete(String id) async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      throw StateError('Not authenticated');
    }
    final db = FirebaseFirestore.instance;
    final me = await db.collection(Collections.users).doc(authUser.uid).get();
    final role = (me.data()?['role'] as String? ?? '').trim();
    if (!isPrivilegedRoleName(role)) {
      throw StateError('Only admin can delete routes');
    }

    // Check for assigned sellers
    final routeDoc = await db.collection(Collections.routes).doc(id).get();
    final assignedSellerIds =
        routeDoc.data()?['assigned_seller_ids'] as List<dynamic>?;
    if (assignedSellerIds != null && assignedSellerIds.isNotEmpty) {
      throw StateError('route_has_seller');
    }

    // Check for active shops/customers linked to this route
    final shopsSnap = await db
        .collection(Collections.customers)
        .where('route_id', isEqualTo: id)
        .where('active', isEqualTo: true)
        .limit(1)
        .get();
    if (shopsSnap.docs.isNotEmpty) {
      throw StateError('route_has_shops');
    }

    await db.collection(Collections.routes).doc(id).update({
      'active': false,
      'updated_at': Timestamp.now(),
    });
  }
}

final routeNotifierProvider = AsyncNotifierProvider<RouteNotifier, void>(
  RouteNotifier.new,
);
