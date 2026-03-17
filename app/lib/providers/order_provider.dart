import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../models/order_model.dart';
import '../models/order_item_model.dart';

final ordersProvider = StreamProvider<List<OrderModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.orders)
      .orderBy('created_at', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => OrderModel.fromJson(d.data(), d.id)).toList());
});

final activeOrdersCountProvider = StreamProvider<int>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.orders)
      .where('status', whereIn: ['pending', 'processing'])
      .snapshots()
      .map((snap) => snap.docs.length);
});

final orderDetailProvider =
    StreamProvider.family<OrderModel?, String>((ref, id) {
  return FirebaseFirestore.instance
      .collection(Collections.orders)
      .doc(id)
      .snapshots()
      .map((doc) =>
          doc.exists ? OrderModel.fromJson(doc.data()!, doc.id) : null);
});

final orderItemsProvider =
    StreamProvider.family<List<OrderItemModel>, String>((ref, orderId) {
  return FirebaseFirestore.instance
      .collection(Collections.orderItems)
      .where('order_id', isEqualTo: orderId)
      .orderBy('created_at', descending: false)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => OrderItemModel.fromJson(d.data(), d.id))
          .toList());
});

class OrderNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<String> createOrder(
      Map<String, dynamic> orderData, List<Map<String, dynamic>> items) async {
    state = const AsyncLoading();
    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();

      final orderRef = db.collection(Collections.orders).doc();
      final now = Timestamp.now();

      batch.set(orderRef, {
        ...orderData,
        'status': 'pending',
        'created_at': now,
        'updated_at': now,
      });

      for (final item in items) {
        final itemRef = db.collection(Collections.orderItems).doc();
        batch.set(itemRef, {
          ...item,
          'order_id': orderRef.id,
          'status': 'pending',
          'created_at': now,
          'updated_at': now,
        });
      }

      await batch.commit();
      state = const AsyncData(null);
      return orderRef.id;
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> updateStatus(String id, String status) async {
    state = const AsyncLoading();
    try {
      await FirebaseFirestore.instance
          .collection(Collections.orders)
          .doc(id)
          .update({'status': status, 'updated_at': Timestamp.now()});
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> cancel(String id) async {
    await updateStatus(id, 'cancelled');
  }
}

final orderNotifierProvider =
    AsyncNotifierProvider<OrderNotifier, void>(OrderNotifier.new);
