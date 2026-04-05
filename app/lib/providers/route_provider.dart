import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../models/route_model.dart';
import 'auth_provider.dart';

final routesProvider = StreamProvider.autoDispose<List<RouteModel>>((ref) {
  // Admin-only unfiltered query: guard so non-admin credentials never
  // subscribe, avoiding PERMISSION_DENIED during auth transitions.
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null || !user.isAdmin) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection(Collections.routes)
      .where('active', isEqualTo: true)
      .orderBy('route_number')
      .limit(200)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => RouteModel.fromJson(d.data(), d.id)).toList());
});

final routeDetailProvider =
    StreamProvider.autoDispose.family<RouteModel?, String>((ref, id) {
  return FirebaseFirestore.instance
      .collection(Collections.routes)
      .doc(id)
      .snapshots()
      .map((doc) =>
          doc.exists ? RouteModel.fromJson(doc.data()!, doc.id) : null);
});

final routesBySellerProvider =
    StreamProvider.autoDispose.family<List<RouteModel>, String>((ref, sellerId) {
  return FirebaseFirestore.instance
      .collection(Collections.routes)
      .where('assigned_seller_id', isEqualTo: sellerId)
      .where('active', isEqualTo: true)
      .orderBy('route_number')
      .limit(100)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => RouteModel.fromJson(d.data(), d.id)).toList());
});

class RouteNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

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

  Future<void> _clearPreviousRouteForSeller(
    WriteBatch batch,
    FirebaseFirestore db,
    String sellerId,
    String keepRouteId,
  ) async {
    final assignedRoutes = await db
        .collection(Collections.routes)
        .where('assigned_seller_id', isEqualTo: sellerId)
        .limit(20)
        .get();

    for (final routeDoc in assignedRoutes.docs) {
      if (routeDoc.id == keepRouteId) continue;
      batch.update(routeDoc.reference, {
        'assigned_seller_id': null,
        'assigned_seller_name': null,
        'updated_at': Timestamp.now(),
      });
    }
  }

  Future<void> create(Map<String, dynamic> data) async {
    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    final routeRef = db.collection(Collections.routes).doc();
    final assignedSellerId = data['assigned_seller_id'] as String?;
    final routeName = data['name'] as String? ?? '';
    final routeNumber = ((data['route_number'] as int?) ?? 0) > 0
        ? (data['route_number'] as int)
        : await _nextRouteNumber(db);

    batch.set(routeRef, {
      ...data,
      'route_number': routeNumber,
      'total_shops': 0,
      'active': true,
      'created_at': Timestamp.now(),
      'updated_at': Timestamp.now(),
    });

    if (assignedSellerId != null && assignedSellerId.isNotEmpty) {
      await _clearPreviousRouteForSeller(
          batch, db, assignedSellerId, routeRef.id);
      batch.update(db.collection(Collections.users).doc(assignedSellerId), {
        'assigned_route_id': routeRef.id,
        'assigned_route_name': routeName,
        'updated_at': Timestamp.now(),
      });
    }

    await batch.commit();
  }

  Future<void> updateRoute(String id, Map<String, dynamic> data) async {
    final db = FirebaseFirestore.instance;
    final routeRef = db.collection(Collections.routes).doc(id);
    final currentRoute = await routeRef.get();
    final batch = db.batch();

    final oldSellerId = currentRoute.data()?['assigned_seller_id'] as String?;
    final newSellerId = data['assigned_seller_id'] as String?;
    final routeName = data['name'] as String? ??
        currentRoute.data()?['name'] as String? ??
        '';

    batch.update(routeRef, {...data, 'updated_at': Timestamp.now()});

    if (oldSellerId != null &&
        oldSellerId.isNotEmpty &&
        oldSellerId != newSellerId) {
      batch.update(db.collection(Collections.users).doc(oldSellerId), {
        'assigned_route_id': null,
        'assigned_route_name': null,
        'updated_at': Timestamp.now(),
      });
    }

    if (newSellerId != null && newSellerId.isNotEmpty) {
      await _clearPreviousRouteForSeller(batch, db, newSellerId, id);
      batch.update(db.collection(Collections.users).doc(newSellerId), {
        'assigned_route_id': id,
        'assigned_route_name': routeName,
        'updated_at': Timestamp.now(),
      });
    }

    await batch.commit();
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

    await db
        .collection(Collections.routes)
        .doc(id)
        .update({'active': false, 'updated_at': Timestamp.now()});
  }
}

final routeNotifierProvider =
    AsyncNotifierProvider<RouteNotifier, void>(RouteNotifier.new);
