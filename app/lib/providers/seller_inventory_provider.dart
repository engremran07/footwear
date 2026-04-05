import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../models/seller_inventory_model.dart';

final sellerInventoryProvider = StreamProvider.autoDispose
    .family<List<SellerInventoryModel>, String>((ref, sellerId) {
  return FirebaseFirestore.instance
      .collection(Collections.sellerInventory)
      .where('seller_id', isEqualTo: sellerId)
      .where('active', isEqualTo: true)
      .orderBy('variant_name')
      .limit(500)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => SellerInventoryModel.fromJson(d.data(), d.id))
          .toList());
});

final sellerInventoryTotalPairsProvider =
    Provider.family<AsyncValue<int>, String>((ref, sellerId) {
  final itemsAsync = ref.watch(sellerInventoryProvider(sellerId));
  return itemsAsync.whenData(
    (items) => items.fold<int>(0, (acc, item) => acc + item.quantityAvailable),
  );
});

/// Streams ALL active seller-inventory items (admin use for reports).
/// Limit is 100 to keep free-tier Firestore reads within budget.
final adminAllSellerInventoryProvider =
    StreamProvider.autoDispose<List<SellerInventoryModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.sellerInventory)
      .where('active', isEqualTo: true)
      .orderBy('variant_name')
      .limit(100)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => SellerInventoryModel.fromJson(d.data(), d.id))
          .toList());
});

class SellerInventoryNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Deducts [qty] pairs from a single seller_inventory document.
  Future<void> deductStock(String docId, int qty) async {
    if (docId.trim().isEmpty) throw ArgumentError('docId must not be empty');
    if (qty <= 0) throw ArgumentError('qty must be greater than 0');
    await FirebaseFirestore.instance
        .collection(Collections.sellerInventory)
        .doc(docId)
        .update({
      'quantity_available': FieldValue.increment(-qty),
      'updated_at': Timestamp.now(),
    });
  }

  /// Returns [qty] pairs of a seller inventory item back to the warehouse.
  /// Atomically:
  ///   1. Deducts from seller_inventory
  ///   2. Increments product_variants.quantity_available
  ///   3. Creates an audit record in inventory_transactions
  Future<void> returnToWarehouse({
    required String sellerInventoryDocId,
    required String variantId,
    required int qty,
    required String sellerId,
    required String sellerName,
    required String variantName,
    required String productId,
    required String createdBy,
    String? notes,
  }) async {
    if (sellerInventoryDocId.trim().isEmpty) {
      throw ArgumentError('sellerInventoryDocId must not be empty');
    }
    if (variantId.trim().isEmpty) {
      throw ArgumentError('variantId must not be empty');
    }
    if (qty <= 0) throw ArgumentError('qty must be greater than 0');

    final db = FirebaseFirestore.instance;
    final batch = db.batch();

    // Deduct from seller inventory
    batch.update(
      db.collection(Collections.sellerInventory).doc(sellerInventoryDocId),
      {
        'quantity_available': FieldValue.increment(-qty),
        'updated_at': Timestamp.now(),
      },
    );

    // Increment warehouse stock (Firestore rules allow seller to *increase* quantity_available)
    batch.update(
      db.collection(Collections.productVariants).doc(variantId),
      {
        'quantity_available': FieldValue.increment(qty),
        'updated_at': Timestamp.now(),
      },
    );

    // Audit log in inventory_transactions
    final auditRef = db.collection(Collections.inventoryTransactions).doc();
    batch.set(auditRef, {
      'type': 'return_to_warehouse',
      'seller_id': sellerId,
      'seller_name': sellerName,
      'variant_id': variantId,
      'variant_name': variantName,
      'product_id': productId,
      'quantity': qty,
      'notes': notes,
      'created_by': createdBy,
      'created_at': Timestamp.now(),
    });

    await batch.commit();
  }
}

final sellerInventoryNotifierProvider =
    AsyncNotifierProvider<SellerInventoryNotifier, void>(
        SellerInventoryNotifier.new);
