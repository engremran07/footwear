import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../models/order_model.dart';
import '../models/cash_transaction_model.dart';
import '../models/customer_model.dart';

Timestamp _startOfToday() {
  final now = DateTime.now();
  return Timestamp.fromDate(DateTime(now.year, now.month, now.day));
}

/// All orders created today — real-time stream.
final todaysOrdersProvider = StreamProvider<List<OrderModel>>((ref) {
  final start = _startOfToday();
  return FirebaseFirestore.instance
      .collection(Collections.orders)
      .where('created_at', isGreaterThanOrEqualTo: start)
      .orderBy('created_at', descending: true)
      .limit(200)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => OrderModel.fromJson(d.data(), d.id)).toList());
});

/// Today's cash-in transactions — real-time stream.
final todaysCashInProvider = StreamProvider<List<CashTransactionModel>>((ref) {
  final start = _startOfToday();
  return FirebaseFirestore.instance
      .collection(Collections.cashTransactions)
      .where('type', isEqualTo: 'cash_in')
      .where('created_at', isGreaterThanOrEqualTo: start)
      .orderBy('created_at', descending: true)
      .limit(200)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => CashTransactionModel.fromJson(d.data(), d.id))
          .toList());
});

/// Today's cash-out transactions — real-time stream.
final todaysCashOutProvider = StreamProvider<List<CashTransactionModel>>((ref) {
  final start = _startOfToday();
  return FirebaseFirestore.instance
      .collection(Collections.cashTransactions)
      .where('type', isEqualTo: 'cash_out')
      .where('created_at', isGreaterThanOrEqualTo: start)
      .orderBy('created_at', descending: true)
      .limit(200)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => CashTransactionModel.fromJson(d.data(), d.id))
          .toList());
});

/// Top 10 customers by outstanding credit (balance desc).
final topCreditCustomersProvider = StreamProvider<List<CustomerModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.customers)
      .orderBy('balance', descending: true)
      .limit(10)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => CustomerModel.fromJson(d.data(), d.id))
          .toList());
});

/// UID → display name lookup map — built from users collection.
final userNameMapProvider = StreamProvider<Map<String, String>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.users)
      .limit(100)
      .snapshots()
      .map((snap) {
    final map = <String, String>{};
    for (final doc in snap.docs) {
      map[doc.id] = (doc.data()['display_name'] as String?) ?? doc.id;
    }
    return map;
  });
});
