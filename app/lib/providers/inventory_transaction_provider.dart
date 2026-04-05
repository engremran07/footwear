import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../models/inventory_transaction_model.dart';

/// All inventory transactions (admin â€” transfer history).
final allInventoryTransactionsProvider =
    StreamProvider<List<InventoryTransactionModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.inventoryTransactions)
      .orderBy('created_at', descending: true)
      .limit(200)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => InventoryTransactionModel.fromJson(d.data(), d.id))
          .toList());
});

/// Inventory transactions for a single seller.
final sellerInventoryTransactionsProvider =
    StreamProvider.autoDispose.family<List<InventoryTransactionModel>, String>(
        (ref, sellerId) {
  return FirebaseFirestore.instance
      .collection(Collections.inventoryTransactions)
      .where('seller_id', isEqualTo: sellerId)
      .orderBy('created_at', descending: true)
      .limit(100)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => InventoryTransactionModel.fromJson(d.data(), d.id))
          .toList());
});
