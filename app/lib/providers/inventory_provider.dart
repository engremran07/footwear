import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../models/inventory_batch_model.dart';
import '../models/inventory_item_model.dart';

final inventoryBatchesProvider =
    StreamProvider<List<InventoryBatchModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.inventoryBatches)
      .orderBy('created_at', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => InventoryBatchModel.fromJson(d.data(), d.id))
          .toList());
});

final inventoryBatchDetailProvider =
    StreamProvider.family<InventoryBatchModel?, String>((ref, id) {
  return FirebaseFirestore.instance
      .collection(Collections.inventoryBatches)
      .doc(id)
      .snapshots()
      .map((doc) => doc.exists
          ? InventoryBatchModel.fromJson(doc.data()!, doc.id)
          : null);
});

final inventoryItemsByBatchProvider =
    StreamProvider.family<List<InventoryItemModel>, String>((ref, batchId) {
  return FirebaseFirestore.instance
      .collection(Collections.inventoryItems)
      .where('inventory_batch_id', isEqualTo: batchId)
      .orderBy('created_at', descending: false)
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => InventoryItemModel.fromJson(d.data(), d.id))
          .toList());
});

class InventoryBatchNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> create(Map<String, dynamic> data) async {
    state = const AsyncLoading();
    try {
      await FirebaseFirestore.instance
          .collection(Collections.inventoryBatches)
          .add({
        ...data,
        'qty_passed': 0,
        'qty_rejected': 0,
        'cost_per_pair': 0.0,
        'status': 'draft',
        'source': 'production',
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
      await FirebaseFirestore.instance
          .collection(Collections.inventoryBatches)
          .doc(id)
          .update({'status': status, 'updated_at': Timestamp.now()});
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
          .collection(Collections.inventoryBatches)
          .doc(id)
          .update({...data, 'updated_at': Timestamp.now()});
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final inventoryBatchNotifierProvider =
    AsyncNotifierProvider<InventoryBatchNotifier, void>(
        InventoryBatchNotifier.new);

/// Inventory items assigned to a specific seller (vehicle inventory)
final sellerInventoryProvider =
    StreamProvider.family<List<InventoryItemModel>, String>((ref, sellerId) {
  return FirebaseFirestore.instance
      .collection(Collections.inventoryItems)
      .where('seller_id', isEqualTo: sellerId)
      .where('status', isEqualTo: 'assigned_to_seller')
      .orderBy('created_at', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => InventoryItemModel.fromJson(d.data(), d.id))
          .toList());
});

/// Warehouse inventory (available, no seller assigned)
final warehouseInventoryProvider =
    StreamProvider<List<InventoryItemModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.inventoryItems)
      .where('status', isEqualTo: 'available')
      .orderBy('created_at', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => InventoryItemModel.fromJson(d.data(), d.id))
          .toList());
});
