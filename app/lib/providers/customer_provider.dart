import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../models/customer_model.dart';

final customersProvider = StreamProvider<List<CustomerModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.customers)
      .where('active', isEqualTo: true)
      .orderBy('name')
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => CustomerModel.fromJson(d.data(), d.id))
          .toList());
});

final customersByTypeProvider =
    StreamProvider.family<List<CustomerModel>, String>((ref, type) {
  return FirebaseFirestore.instance
      .collection(Collections.customers)
      .where('active', isEqualTo: true)
      .where('type', isEqualTo: type)
      .orderBy('name')
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => CustomerModel.fromJson(d.data(), d.id))
          .toList());
});

final customersBySellerProvider =
    StreamProvider.family<List<CustomerModel>, String>((ref, sellerId) {
  return FirebaseFirestore.instance
      .collection(Collections.customers)
      .where('seller_id', isEqualTo: sellerId)
      .where('active', isEqualTo: true)
      .orderBy('name')
      .limit(50)
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

class CustomerNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> create(Map<String, dynamic> data) async {
    state = const AsyncLoading();
    try {
      await FirebaseFirestore.instance.collection(Collections.customers).add({
        ...data,
        'balance': 0.0,
        'total_orders': 0,
        'active': true,
        'created_at': Timestamp.now(),
        'updated_at': Timestamp.now(),
      });
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> save(String id, Map<String, dynamic> data) async {
    state = const AsyncLoading();
    try {
      await FirebaseFirestore.instance
          .collection(Collections.customers)
          .doc(id)
          .update({...data, 'updated_at': Timestamp.now()});
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> deactivate(String id) async {
    state = const AsyncLoading();
    try {
      await FirebaseFirestore.instance
          .collection(Collections.customers)
          .doc(id)
          .update({'active': false, 'updated_at': Timestamp.now()});
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> assignSeller(
      String customerId, String? sellerId, String? sellerName) async {
    state = const AsyncLoading();
    try {
      await FirebaseFirestore.instance
          .collection(Collections.customers)
          .doc(customerId)
          .update({
        'seller_id': sellerId,
        'seller_name': sellerName,
        'updated_at': Timestamp.now(),
      });
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final customerNotifierProvider =
    AsyncNotifierProvider<CustomerNotifier, void>(CustomerNotifier.new);
