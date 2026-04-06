import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../models/customer_model.dart';
import 'auth_provider.dart';

final customersProvider =
    StreamProvider.autoDispose<List<CustomerModel>>((ref) {
  // Admin-only: guard so non-admin credentials never subscribe,
  // avoiding PERMISSION_DENIED during auth transitions.
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null || !user.isAdmin) return const Stream.empty();
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
    StreamProvider.autoDispose.family<CustomerModel?, String>((ref, id) {
  return FirebaseFirestore.instance
      .collection(Collections.customers)
      .doc(id)
      .snapshots()
      .map((doc) =>
          doc.exists ? CustomerModel.fromJson(doc.data()!, doc.id) : null);
});

final customersByRouteProvider = StreamProvider.autoDispose
    .family<List<CustomerModel>, String>((ref, routeId) {
  return FirebaseFirestore.instance
      .collection(Collections.customers)
      .where('route_id', isEqualTo: routeId)
      .where('active', isEqualTo: true)
      .orderBy('name')
      .limit(500)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => CustomerModel.fromJson(d.data(), d.id))
          .toList());
});

final outstandingCustomersByRouteProvider = StreamProvider.autoDispose
    .family<List<CustomerModel>, String>((ref, routeId) {
  return FirebaseFirestore.instance
      .collection(Collections.customers)
      .where('route_id', isEqualTo: routeId)
      .where('active', isEqualTo: true)
      .where('balance', isGreaterThan: 0)
      .orderBy('balance', descending: true)
      .limit(100)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => CustomerModel.fromJson(d.data(), d.id))
          .toList());
});

final outstandingCustomersProvider =
    StreamProvider.autoDispose<List<CustomerModel>>((ref) {
  // Admin-only: guard so non-admin credentials never subscribe.
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null || !user.isAdmin) return const Stream.empty();
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
    StreamProvider.autoDispose.family<List<dynamic>, String>((ref, customerId) {
  return FirebaseFirestore.instance
      .collection(Collections.transactions)
      .where('customer_id', isEqualTo: customerId)
      .where('deleted', isEqualTo: false)
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
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) throw StateError('Not authenticated');
    await db.collection(Collections.customers).add({
      ...data,
      if (!data.containsKey('created_by')) 'created_by': uid,
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

  /// Admin-only: marks a customer as bad debt, writes off outstanding balance.
  Future<void> markAsBadDebt(String customerId) async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) throw StateError('Not authenticated');
    final me = await FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(authUser.uid)
        .get();
    final role = (me.data()?['role'] as String? ?? '').trim().toLowerCase();
    if (role != 'admin' && role != 'manager') {
      throw StateError('Only admin can mark bad debt');
    }

    final db = FirebaseFirestore.instance;
    final custDoc =
        await db.collection(Collections.customers).doc(customerId).get();
    final balance = (custDoc.data()?['balance'] as num?)?.toDouble() ?? 0;
    if (balance <= 0) throw StateError('No outstanding balance to write off');

    final batch = db.batch();

    // Mark customer as bad debt
    batch.update(db.collection(Collections.customers).doc(customerId), {
      'bad_debt': true,
      'bad_debt_amount': balance,
      'bad_debt_date': Timestamp.now(),
      'balance': 0.0,
      'updated_at': Timestamp.now(),
    });

    // Create write_off transaction
    final txRef = db.collection(Collections.transactions).doc();
    batch.set(txRef, {
      'type': 'write_off',
      'shop_id': '',
      'shop_name': '',
      'route_id': '',
      'customer_id': customerId,
      'customer_name': custDoc.data()?['name'] ?? '',
      'amount': balance,
      'description': 'Bad debt write-off',
      'items': <Map<String, dynamic>>[],
      'created_by': authUser.uid,
      'created_at': Timestamp.now(),
      'deleted': false,
    });

    await batch.commit();
  }

  Future<void> deactivate(String id) async {
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
      throw StateError('Only admin can delete customers');
    }

    final db = FirebaseFirestore.instance;
    await db.collection(Collections.customers).doc(id).update({
      'active': false,
      'updated_at': Timestamp.now(),
    });
  }
}

final customerNotifierProvider =
    AsyncNotifierProvider<CustomerNotifier, void>(CustomerNotifier.new);
