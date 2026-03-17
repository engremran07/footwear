import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../models/qc_record_model.dart';
import '../models/waste_record_model.dart';
import '../models/inventory_batch_model.dart';

final qcPendingBatchesProvider =
    StreamProvider<List<InventoryBatchModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.inventoryBatches)
      .where('status', isEqualTo: 'qc_pending')
      .orderBy('created_at', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => InventoryBatchModel.fromJson(d.data(), d.id))
          .toList());
});

final qcRecordsProvider =
    StreamProvider.family<List<QcRecordModel>, String>((ref, batchId) {
  return FirebaseFirestore.instance
      .collection(Collections.qcRecords)
      .where('batch_id', isEqualTo: batchId)
      .orderBy('created_at', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => QcRecordModel.fromJson(d.data(), d.id))
          .toList());
});

final wasteRecordsProvider = StreamProvider<List<WasteRecordModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.wasteRecords)
      .orderBy('created_at', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => WasteRecordModel.fromJson(d.data(), d.id))
          .toList());
});

class QcNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> submitQcRecord(Map<String, dynamic> data) async {
    state = const AsyncLoading();
    try {
      await FirebaseFirestore.instance.collection(Collections.qcRecords).add({
        ...data,
        'created_at': Timestamp.now(),
      });
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> markDisposed(String wasteId) async {
    state = const AsyncLoading();
    try {
      await FirebaseFirestore.instance
          .collection(Collections.wasteRecords)
          .doc(wasteId)
          .update({
        'disposed': true,
        'disposed_at': Timestamp.now(),
      });
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final qcNotifierProvider =
    AsyncNotifierProvider<QcNotifier, void>(QcNotifier.new);
