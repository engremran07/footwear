import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../models/worker_model.dart';
import '../models/worker_payment_model.dart';

final workersProvider = StreamProvider<List<WorkerModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.workers)
      .where('active', isEqualTo: true)
      .orderBy('name')
      .limit(50)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => WorkerModel.fromJson(d.data(), d.id)).toList());
});

final activeWorkersCountProvider = StreamProvider<int>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.workers)
      .where('active', isEqualTo: true)
      .snapshots()
      .map((snap) => snap.docs.length);
});

final workerDetailProvider =
    StreamProvider.family<WorkerModel?, String>((ref, id) {
  return FirebaseFirestore.instance
      .collection(Collections.workers)
      .doc(id)
      .snapshots()
      .map((doc) =>
          doc.exists ? WorkerModel.fromJson(doc.data()!, doc.id) : null);
});

final workerPaymentsProvider =
    StreamProvider.family<List<WorkerPaymentModel>, String>((ref, workerId) {
  return FirebaseFirestore.instance
      .collection(Collections.workerPayments)
      .where('worker_id', isEqualTo: workerId)
      .orderBy('created_at', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => WorkerPaymentModel.fromJson(d.data(), d.id))
          .toList());
});

final allWorkerPaymentsProvider =
    StreamProvider<List<WorkerPaymentModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.workerPayments)
      .orderBy('created_at', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => WorkerPaymentModel.fromJson(d.data(), d.id))
          .toList());
});

class WorkerNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> create(Map<String, dynamic> data) async {
    state = const AsyncLoading();
    try {
      await FirebaseFirestore.instance.collection(Collections.workers).add({
        ...data,
        'total_earned': 0.0,
        'pairs_produced': 0,
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
          .collection(Collections.workers)
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
          .collection(Collections.workers)
          .doc(id)
          .update({'active': false, 'updated_at': Timestamp.now()});
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> createPayment(Map<String, dynamic> data) async {
    state = const AsyncLoading();
    try {
      await FirebaseFirestore.instance
          .collection(Collections.workerPayments)
          .add({
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

  Future<void> approvePayment(String paymentId, String approvedBy) async {
    state = const AsyncLoading();
    try {
      await FirebaseFirestore.instance
          .collection(Collections.workerPayments)
          .doc(paymentId)
          .update({
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
}

final workerNotifierProvider =
    AsyncNotifierProvider<WorkerNotifier, void>(WorkerNotifier.new);
