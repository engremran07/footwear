import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../models/customer_model.dart';

final customersProvider = StreamProvider<List<CustomerModel>>((ref) {
  ref.keepAlive();
  return FirebaseFirestore.instance
      .collection(Collections.customers)
      .where('active', isEqualTo: true)
      .orderBy('name')
      .limit(500)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => CustomerModel.fromJson(d.data(), d.id))
          .toList());
});

final customerDetailProvider =
    StreamProvider.family<CustomerModel?, String>((ref, id) {
  return FirebaseFirestore.instance
      .collection(Collections.customers)
      .doc(id)
      .snapshots()
      .map((doc) =>
          doc.exists ? CustomerModel.fromJson(doc.data()!, doc.id) : null);
});

final outstandingCustomersProvider = StreamProvider<List<CustomerModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.customers)
      .where('active', isEqualTo: true)
      .where('balance', isGreaterThan: 0)
      .orderBy('balance', descending: true)
      .limit(100)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => CustomerModel.fromJson(d.data(), d.id))
          .toList());
});

final customerTransactionsProvider =
    StreamProvider.family<List<dynamic>, String>((ref, customerId) {
  return FirebaseFirestore.instance
      .collection(Collections.transactions)
      .where('customer_id', isEqualTo: customerId)
      .orderBy('created_at', descending: true)
      .limit(100)
      .snapshots()
      .map((snap) => snap.docs.map((d) {
            final data = d.data();
            data['id'] = d.id;
            return data;
          }).toList());
});

class CustomerNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> create(Map<String, dynamic> data) async {
    final db = FirebaseFirestore.instance;
    await db.collection(Collections.customers).add({
      ...data,
      'balance': 0.0,
      'active': true,
      'created_at': Timestamp.now(),
      'updated_at': Timestamp.now(),
    });
  }

  Future<void> updateCustomer(String id, Map<String, dynamic> data) async {
    final db = FirebaseFirestore.instance;
    await db.collection(Collections.customers).doc(id).update({
      ...data,
      'updated_at': Timestamp.now(),
    });
  }

  Future<void> deactivate(String id) async {
    final db = FirebaseFirestore.instance;
    await db.collection(Collections.customers).doc(id).update({
      'active': false,
      'updated_at': Timestamp.now(),
    });
  }
}

final customerNotifierProvider =
    AsyncNotifierProvider<CustomerNotifier, void>(CustomerNotifier.new);
