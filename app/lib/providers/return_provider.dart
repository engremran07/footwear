import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/order_return_model.dart';
import '../core/constants/collections.dart';

/// Delivered orders for return form picker.
final deliveredOrdersProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.orders)
      .where('status', isEqualTo: 'delivered')
      .orderBy('created_at', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
});

/// Dispatched order items for a specific order (used by return form).
final dispatchedOrderItemsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
        (ref, orderId) async {
  final snap = await FirebaseFirestore.instance
      .collection(Collections.orderItems)
      .where('order_id', isEqualTo: orderId)
      .where('status', isEqualTo: 'dispatched')
      .get();
  return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
});

/// All returns ordered by newest first, limit 50.
final returnsProvider = StreamProvider<List<OrderReturnModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.orderReturns)
      .orderBy('created_at', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs
          .map((doc) => OrderReturnModel.fromJson(doc.data(), doc.id))
          .toList());
});

/// Returns filtered by status tab.
final returnsByStatusProvider =
    StreamProvider.family<List<OrderReturnModel>, String>((ref, status) {
  return FirebaseFirestore.instance
      .collection(Collections.orderReturns)
      .where('status', isEqualTo: status)
      .orderBy('created_at', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs
          .map((doc) => OrderReturnModel.fromJson(doc.data(), doc.id))
          .toList());
});

/// Returns for a specific order.
final orderReturnsProvider =
    StreamProvider.family<List<OrderReturnModel>, String>((ref, orderId) {
  return FirebaseFirestore.instance
      .collection(Collections.orderReturns)
      .where('order_id', isEqualTo: orderId)
      .orderBy('created_at', descending: true)
      .snapshots()
      .map((snap) => snap.docs
          .map((doc) => OrderReturnModel.fromJson(doc.data(), doc.id))
          .toList());
});

/// Single return document stream.
final returnDetailProvider =
    StreamProvider.family<OrderReturnModel?, String>((ref, returnId) {
  return FirebaseFirestore.instance
      .collection(Collections.orderReturns)
      .doc(returnId)
      .snapshots()
      .map((snap) => snap.exists
          ? OrderReturnModel.fromJson(snap.data()!, snap.id)
          : null);
});

class ReturnNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> create(Map<String, dynamic> data) async {
    state = const AsyncLoading();
    try {
      final db = FirebaseFirestore.instance;
      await db.collection(Collections.orderReturns).add({
        ...data,
        'status': 'pending',
        'created_at': Timestamp.now(),
        'updated_at': Timestamp.now(),
      });
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> approve(String returnId, String approvedBy) async {
    state = const AsyncLoading();
    try {
      final db = FirebaseFirestore.instance;
      await db.collection(Collections.orderReturns).doc(returnId).update({
        'status': 'approved',
        'approved_by': approvedBy,
        'approved_at': Timestamp.now(),
        'updated_at': Timestamp.now(),
      });
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> reject(String returnId, String rejectedBy,
      {String? notes}) async {
    state = const AsyncLoading();
    try {
      final db = FirebaseFirestore.instance;
      await db.collection(Collections.orderReturns).doc(returnId).update({
        'status': 'rejected',
        'approved_by': rejectedBy,
        'notes': notes,
        'updated_at': Timestamp.now(),
      });
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  /// Mark as completed — cash refund has been physically confirmed by manager.
  /// Adjusts customer's outstanding balance by deducting the refund amount.
  /// After this, the document is immutable.
  Future<void> complete(String returnId) async {
    state = const AsyncLoading();
    try {
      final db = FirebaseFirestore.instance;
      // Read the return doc to get refund amount and customer ID
      final returnDoc =
          await db.collection(Collections.orderReturns).doc(returnId).get();
      if (!returnDoc.exists) throw Exception('Return not found');
      final data = returnDoc.data()!;
      final customerId = data['customer_id'] as String?;
      final refundAmount = (data['refund_amount'] as num?)?.toDouble() ?? 0.0;

      final batch = db.batch();
      batch.update(db.collection(Collections.orderReturns).doc(returnId), {
        'status': 'completed',
        'updated_at': Timestamp.now(),
      });
      // Deduct refund amount from customer's outstanding balance
      if (customerId != null && refundAmount > 0) {
        batch.update(db.collection(Collections.customers).doc(customerId), {
          'balance': FieldValue.increment(-refundAmount),
          'updated_at': Timestamp.now(),
        });
      }
      await batch.commit();
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final returnNotifierProvider =
    AsyncNotifierProvider<ReturnNotifier, void>(ReturnNotifier.new);
