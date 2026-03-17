import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../models/supplier_model.dart';
import '../models/purchase_order_model.dart';

final suppliersProvider = StreamProvider<List<SupplierModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.suppliers)
      .where('active', isEqualTo: true)
      .orderBy('name')
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => SupplierModel.fromJson(d.data(), d.id))
          .toList());
});

final supplierDetailProvider =
    StreamProvider.family<SupplierModel?, String>((ref, id) {
  return FirebaseFirestore.instance
      .collection(Collections.suppliers)
      .doc(id)
      .snapshots()
      .map((doc) =>
          doc.exists ? SupplierModel.fromJson(doc.data()!, doc.id) : null);
});

final purchaseOrdersProvider = StreamProvider<List<PurchaseOrderModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.purchaseOrders)
      .orderBy('created_at', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => PurchaseOrderModel.fromJson(d.data(), d.id))
          .toList());
});

final purchaseOrderDetailProvider =
    StreamProvider.family<PurchaseOrderModel?, String>((ref, id) {
  return FirebaseFirestore.instance
      .collection(Collections.purchaseOrders)
      .doc(id)
      .snapshots()
      .map((doc) =>
          doc.exists ? PurchaseOrderModel.fromJson(doc.data()!, doc.id) : null);
});

class SupplierNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> create(Map<String, dynamic> data) async {
    state = const AsyncLoading();
    try {
      await FirebaseFirestore.instance.collection(Collections.suppliers).add({
        ...data,
        'total_purchased': 0.0,
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
          .collection(Collections.suppliers)
          .doc(id)
          .update({...data, 'updated_at': Timestamp.now()});
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final supplierNotifierProvider =
    AsyncNotifierProvider<SupplierNotifier, void>(SupplierNotifier.new);

class PurchaseOrderNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> create(Map<String, dynamic> data, String createdBy) async {
    state = const AsyncLoading();
    try {
      await FirebaseFirestore.instance
          .collection(Collections.purchaseOrders)
          .add({
        ...data,
        'status': 'draft',
        'created_by': createdBy,
        'created_at': Timestamp.now(),
        'updated_at': Timestamp.now(),
      });
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> updateStatus(String id, String status) async {
    state = const AsyncLoading();
    try {
      final update = <String, dynamic>{
        'status': status,
        'updated_at': Timestamp.now(),
      };
      if (status == 'received') {
        update['received_at'] = Timestamp.now();
      }
      await FirebaseFirestore.instance
          .collection(Collections.purchaseOrders)
          .doc(id)
          .update(update);
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
          .collection(Collections.purchaseOrders)
          .doc(id)
          .update({...data, 'updated_at': Timestamp.now()});
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final purchaseOrderNotifierProvider =
    AsyncNotifierProvider<PurchaseOrderNotifier, void>(
        PurchaseOrderNotifier.new);
