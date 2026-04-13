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
      return FirebaseFirestore.instance
          .collection(Collections.routes)
          .where(FieldPath.documentId, isEqualTo: id)
          .where('assigned_seller_id', isEqualTo: user.id)
          .limit(1)
          .snapshots()
          .map((snap) {
            if (snap.docs.isEmpty) return null;
            final doc = snap.docs.first;
            return RouteModel.fromJson(doc.data(), doc.id);
          });
    });

final routesBySellerProvider = StreamProvider.autoDispose
    .family<List<RouteModel>, String>((ref, sellerId) {
      final user = ref.watch(authUserProvider).value;
      if (user == null) return const Stream.empty();
      if (!user.isAdmin && user.id != sellerId) return const Stream.empty();
      return FirebaseFirestore.instance
          .collection(Collections.routes)
          .where('assigned_seller_id', isEqualTo: sellerId)
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
    final assignedSellerId =
        (data['assigned_seller_id'] as String?)?.trim().isNotEmpty == true
        ? (data['assigned_seller_id'] as String).trim()
        : null;
    final routeName = data['name'] as String? ?? '';
    final assignedSellerName =
        (data['assigned_seller_name'] as String?)?.trim().isNotEmpty == true
        ? (data['assigned_seller_name'] as String).trim()
        : null;
    final routeNumber = ((data['route_number'] as int?) ?? 0) > 0
        ? (data['route_number'] as int)
        : await _nextRouteNumber(db);

    await db.runTransaction<void>((txn) async {
      DocumentReference<Map<String, dynamic>>? sellerRef;
      DocumentReference<Map<String, dynamic>>? previousRouteRef;
      DocumentSnapshot<Map<String, dynamic>>? previousRouteSnap;

      if (assignedSellerId != null) {
        sellerRef = db.collection(Collections.users).doc(assignedSellerId);
        final sellerSnap = await txn.get(sellerRef);
        if (!sellerSnap.exists) {
          throw StateError('Seller not found');
        }

        final previousRouteId =
            (sellerSnap.data()?['assigned_route_id'] as String?)?.trim();
        if (previousRouteId != null &&
            previousRouteId.isNotEmpty &&
            previousRouteId != routeRef.id) {
          previousRouteRef = db
              .collection(Collections.routes)
              .doc(previousRouteId);
          previousRouteSnap = await txn.get(previousRouteRef);
        }
      }

      final now = Timestamp.now();
      txn.set(routeRef, {
        ...data,
        'assigned_seller_id': assignedSellerId,
        'assigned_seller_name': assignedSellerId == null
            ? null
            : assignedSellerName,
        'route_number': routeNumber,
        'total_shops': 0,
        'active': true,
        'created_at': now,
        'updated_at': now,
      });

      if (previousRouteRef != null && previousRouteSnap?.exists == true) {
        txn.update(previousRouteRef, {
          'assigned_seller_id': null,
          'assigned_seller_name': null,
          'updated_at': now,
        });
      }

      if (sellerRef != null) {
        txn.update(sellerRef, {
          'assigned_route_id': routeRef.id,
          'assigned_route_name': routeName,
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

      final oldSellerId =
          (currentRoute.data()?['assigned_seller_id'] as String?)?.trim();
      final newSellerId =
          (data['assigned_seller_id'] as String?)?.trim().isNotEmpty == true
          ? (data['assigned_seller_id'] as String).trim()
          : null;
      final routeName =
          data['name'] as String? ??
          currentRoute.data()?['name'] as String? ??
          '';
      final assignedSellerName =
          (data['assigned_seller_name'] as String?)?.trim().isNotEmpty == true
          ? (data['assigned_seller_name'] as String).trim()
          : null;

      DocumentReference<Map<String, dynamic>>? newSellerRef;
      DocumentReference<Map<String, dynamic>>? previousRouteRef;
      DocumentSnapshot<Map<String, dynamic>>? previousRouteSnap;

      if (newSellerId != null) {
        newSellerRef = db.collection(Collections.users).doc(newSellerId);
        final newSellerSnap = await txn.get(newSellerRef);
        if (!newSellerSnap.exists) {
          throw StateError('Seller not found');
        }

        final previousRouteId =
            (newSellerSnap.data()?['assigned_route_id'] as String?)?.trim();
        if (previousRouteId != null &&
            previousRouteId.isNotEmpty &&
            previousRouteId != id) {
          previousRouteRef = db
              .collection(Collections.routes)
              .doc(previousRouteId);
          previousRouteSnap = await txn.get(previousRouteRef);
        }
      }

      final now = Timestamp.now();
      txn.update(routeRef, {
        ...data,
        'assigned_seller_id': newSellerId,
        'assigned_seller_name': newSellerId == null ? null : assignedSellerName,
        'updated_at': now,
      });

      if (oldSellerId != null &&
          oldSellerId.isNotEmpty &&
          oldSellerId != newSellerId) {
        txn.update(db.collection(Collections.users).doc(oldSellerId), {
          'assigned_route_id': null,
          'assigned_route_name': null,
          'updated_at': now,
        });
      }

      if (previousRouteRef != null && previousRouteSnap?.exists == true) {
        txn.update(previousRouteRef, {
          'assigned_seller_id': null,
          'assigned_seller_name': null,
          'updated_at': now,
        });
      }

      if (newSellerRef != null) {
        txn.update(newSellerRef, {
          'assigned_route_id': id,
          'assigned_route_name': routeName,
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

    // Check for assigned seller
    final routeDoc = await db.collection(Collections.routes).doc(id).get();
    final assignedSellerId = routeDoc.data()?['assigned_seller_id'] as String?;
    if (assignedSellerId != null && assignedSellerId.isNotEmpty) {
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
