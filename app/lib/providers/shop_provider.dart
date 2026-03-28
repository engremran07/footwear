import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../models/shop_model.dart';

final shopsProvider = StreamProvider<List<ShopModel>>((ref) {
  ref.keepAlive();
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

class ShopNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> create(Map<String, dynamic> data) async {
    final db = FirebaseFirestore.instance;
    // Create customer/shop first (sellers + admins have permission)
    await db.collection(Collections.customers).add({
      ...data,
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
    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    batch.update(db.collection(Collections.customers).doc(id), {
      'active': false,
      'updated_at': Timestamp.now(),
    });
    batch.update(db.collection(Collections.routes).doc(routeId), {
      'total_shops': FieldValue.increment(-1),
    });
    await batch.commit();
  }
}

final shopNotifierProvider =
    AsyncNotifierProvider<ShopNotifier, void>(ShopNotifier.new);
