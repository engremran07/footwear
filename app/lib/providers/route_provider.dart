import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../models/route_model.dart';
import 'auth_provider.dart';

final routesProvider = StreamProvider.autoDispose<List<RouteModel>>((ref) {
  // Admin-only unfiltered query: guard so non-admin credentials never
  // subscribe, avoiding PERMISSION_DENIED during auth transitions.
  final user = ref.watch(authUserProvider).value;
  if (user == null || !user.isAdmin) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection(Collections.routes)
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
      final user = ref.watch(authUserProvider).value;
      if (user == null) return const Stream.empty();
      if (user.isAdmin) {
        return FirebaseFirestore.instance
            .collection(Collections.routes)
            .doc(id)
            .snapshots()
            .map(
              (doc) =>
                  doc.exists ? RouteModel.fromJson(doc.data()!, doc.id) : null,
            );
      }
      if (!user.isSeller) return const Stream.empty();
      // Multi-seller: read doc by ID, verify membership client-side.
      return FirebaseFirestore.instance
          .collection(Collections.routes)
          .doc(id)
          .snapshots()
          .map((doc) {
            if (!doc.exists) return null;
            final route = RouteModel.fromJson(doc.data()!, doc.id);
            // Check both new array and legacy scalar for un-migrated docs.
            if (route.assignedSellerIds.contains(user.id)) return route;
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
      final (isAdmin, uid) = ref.watch(
        authUserProvider.select((s) {
          final u = s.value;
          return (u?.isAdmin ?? false, u?.id ?? '');
        }),
      );
      if (uid.isEmpty) return const Stream.empty();
      if (!isAdmin && uid != sellerId) return const Stream.empty();
      return FirebaseFirestore.instance
          .collection(Collections.routes)
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
    final role = (me.data()?['role'] as String? ?? '').trim().toLowerCase();
    if (role != 'admin' && role != 'manager') return;

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
        ...data,
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
        ...data,
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
    final role = (me.data()?['role'] as String? ?? '').trim().toLowerCase();
    if (role != 'admin' && role != 'manager') {
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
