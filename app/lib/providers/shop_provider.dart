import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../models/shop_model.dart';
import 'auth_provider.dart';

final shopsProvider = StreamProvider<List<ShopModel>>((ref) {
  // Admin-only unfiltered query: guard to prevent PERMISSION_DENIED
  // during auth transitions when seller credentials are active.
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null || !user.isAdmin) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection(Collections.customers)
      .where('active', isEqualTo: true)
      .orderBy('name')
      .limit(500)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => ShopModel.fromJson(d.data(), d.id)).toList());
});

final shopsByRouteProvider =
    StreamProvider.family<List<ShopModel>, String>((ref, routeId) {
  return FirebaseFirestore.instance
      .collection(Collections.customers)
      .where('route_id', isEqualTo: routeId)
      .where('active', isEqualTo: true)
      .orderBy('name')
      .limit(200)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => ShopModel.fromJson(d.data(), d.id)).toList());
});

final shopDetailProvider = StreamProvider.family<ShopModel?, String>((ref, id) {
  return FirebaseFirestore.instance
      .collection(Collections.customers)
      .doc(id)
      .snapshots()
      .map(
          (doc) => doc.exists ? ShopModel.fromJson(doc.data()!, doc.id) : null);
});

final outstandingShopsProvider = StreamProvider<List<ShopModel>>((ref) {
  // Admin-only unfiltered query: guard to prevent PERMISSION_DENIED.
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null || !user.isAdmin) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection(Collections.customers)
      .where('active', isEqualTo: true)
      .where('balance', isGreaterThan: 0)
      .orderBy('balance', descending: true)
      .limit(200)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => ShopModel.fromJson(d.data(), d.id)).toList());
});

final outstandingShopsByRouteProvider =
    StreamProvider.family<List<ShopModel>, String>((ref, routeId) {
  return FirebaseFirestore.instance
      .collection(Collections.customers)
      .where('route_id', isEqualTo: routeId)
      .where('active', isEqualTo: true)
      .where('balance', isGreaterThan: 0)
      .orderBy('balance', descending: true)
      .limit(200)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => ShopModel.fromJson(d.data(), d.id)).toList());
});

class ShopNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> create(Map<String, dynamic> data) async {
    final db = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) throw StateError('Not authenticated');
    // Create customer/shop first (sellers + admins have permission)
    await db.collection(Collections.customers).add({
      ...data,
      if (!data.containsKey('created_by')) 'created_by': uid,
      'balance': 0.0,
      'active': true,
      'created_at': Timestamp.now(),
      'updated_at': Timestamp.now(),
    });
    // Try to increment route total_shops (may fail for sellers — non-critical)
    try {
      final routeId = data['route_id'] as String;
      await db.collection(Collections.routes).doc(routeId).update({
        'total_shops': FieldValue.increment(1),
      });
    } catch (_) {}
  }

  Future<void> updateShop(String id, Map<String, dynamic> data) async {
    await FirebaseFirestore.instance
        .collection(Collections.customers)
        .doc(id)
        .update({...data, 'updated_at': Timestamp.now()});
  }

  Future<void> deactivate(String id, String routeId) async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      throw StateError('Not authenticated');
    }
    final me = await FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(authUser.uid)
        .get();
    final role = (me.data()?['role'] as String? ?? '').trim().toLowerCase();
    if (role != 'admin' && role != 'manager') {
      throw StateError('Only admin can delete shops');
    }

    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    batch.update(db.collection(Collections.customers).doc(id), {
      'active': false,
      'updated_at': Timestamp.now(),
    });
    if (routeId.trim().isNotEmpty) {
      batch.update(db.collection(Collections.routes).doc(routeId), {
        'total_shops': FieldValue.increment(-1),
      });
    }
    await batch.commit();
  }
}

final shopNotifierProvider =
    AsyncNotifierProvider<ShopNotifier, void>(ShopNotifier.new);
