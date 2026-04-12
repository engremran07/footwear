import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../models/product_model.dart';
import '../models/product_variant_model.dart';

final productsProvider = StreamProvider.autoDispose<List<ProductModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.products)
      .where('active', isEqualTo: true)
      .orderBy('name')
      .limit(200)
      .snapshots()
      .map(
        (snap) => snap.docs
            .map((d) => ProductModel.fromJson(d.data(), d.id))
            .toList(),
      );
});

final productDetailProvider = StreamProvider.autoDispose
    .family<ProductModel?, String>((ref, id) {
      return FirebaseFirestore.instance
          .collection(Collections.products)
          .doc(id)
          .snapshots()
          .map(
            (doc) =>
                doc.exists ? ProductModel.fromJson(doc.data()!, doc.id) : null,
          );
    });

final productVariantsProvider = StreamProvider.autoDispose
    .family<List<ProductVariantModel>, String>((ref, productId) {
      return FirebaseFirestore.instance
          .collection(Collections.productVariants)
          .where('product_id', isEqualTo: productId)
          .where('active', isEqualTo: true)
          .orderBy('variant_name')
          .limit(100)
          .snapshots()
          .map(
            (snap) => snap.docs
                .map((d) => ProductVariantModel.fromJson(d.data(), d.id))
                .toList(),
          );
    });

final allVariantsProvider =
    StreamProvider.autoDispose<List<ProductVariantModel>>((ref) {
      return FirebaseFirestore.instance
          .collection(Collections.productVariants)
          .where('active', isEqualTo: true)
          .orderBy('variant_name')
          .limit(500)
          .snapshots()
          .map(
            (snap) => snap.docs
                .map((d) => ProductVariantModel.fromJson(d.data(), d.id))
                .toList(),
          );
    });

class ProductNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> _requireAdmin() async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) throw StateError('Not authenticated');
    final me = await FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(authUser.uid)
        .get();
    final role = (me.data()?['role'] as String? ?? '').trim().toLowerCase();
    if (role != 'admin' && role != 'manager') {
      throw StateError('Only admin can manage products');
    }
  }

  Future<String> createProduct(Map<String, dynamic> data) async {
    await _requireAdmin();
    // enforce HTTPS for product image URLs
    final imageUrl = data['image_url'] as String? ?? '';
    if (imageUrl.isNotEmpty && !imageUrl.startsWith('https://')) {
      throw ArgumentError('Product image_url must use HTTPS (got: $imageUrl)');
    }
    final db = FirebaseFirestore.instance;
    final doc = await db.collection(Collections.products).add({
      ...data,
      'active': true,
      'created_at': Timestamp.now(),
      'updated_at': Timestamp.now(),
    });
    return doc.id;
  }

  Future<void> updateProduct(String id, Map<String, dynamic> data) async {
    await _requireAdmin();
    // enforce HTTPS for product image URLs on update
    final imageUrl = data['image_url'] as String? ?? '';
    if (imageUrl.isNotEmpty && !imageUrl.startsWith('https://')) {
      throw ArgumentError('Product image_url must use HTTPS (got: $imageUrl)');
    }
    await FirebaseFirestore.instance
        .collection(Collections.products)
        .doc(id)
        .update({...data, 'updated_at': Timestamp.now()});
  }

  Future<void> deleteProduct(String id) async {
    await _requireAdmin();
    await FirebaseFirestore.instance
        .collection(Collections.products)
        .doc(id)
        .update({'active': false, 'updated_at': Timestamp.now()});
  }

  Future<void> createVariant(Map<String, dynamic> data) async {
    await _requireAdmin();
    await FirebaseFirestore.instance
        .collection(Collections.productVariants)
        .add({
          ...data,
          'active': true,
          'created_at': Timestamp.now(),
          'updated_at': Timestamp.now(),
        });
  }

  Future<void> updateVariant(String id, Map<String, dynamic> data) async {
    await _requireAdmin();
    await FirebaseFirestore.instance
        .collection(Collections.productVariants)
        .doc(id)
        .update({...data, 'updated_at': Timestamp.now()});
  }

  Future<void> deleteVariant(String id) async {
    await _requireAdmin();
    await FirebaseFirestore.instance
        .collection(Collections.productVariants)
        .doc(id)
        .update({'active': false, 'updated_at': Timestamp.now()});
  }

  Future<void> adjustStock(String variantId, int delta) async {
    await _requireAdmin();
    if (variantId.trim().isEmpty) {
      throw ArgumentError('variantId must not be empty');
    }
    if (delta == 0) return;

    final db = FirebaseFirestore.instance;
    final now = Timestamp.now();
    final adminId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (adminId.trim().isEmpty) {
      throw StateError('Not authenticated');
    }

    await db.runTransaction<void>((txn) async {
      final variantRef = db
          .collection(Collections.productVariants)
          .doc(variantId);
      final variantSnap = await txn.get(variantRef);
      if (!variantSnap.exists) {
        throw ArgumentError('Variant not found: $variantId');
      }

      final currentQty =
          (variantSnap.data()?['quantity_available'] as num?)?.toInt() ?? 0;
      final nextQty = currentQty + delta;
      if (nextQty < 0) {
        throw ArgumentError('Stock cannot be negative');
      }

      txn.update(variantRef, {
        'quantity_available': nextQty,
        'updated_at': now,
      });

      final auditRef = db.collection(Collections.inventoryTransactions).doc();
      txn.set(auditRef, {
        'type': 'stock_adjustment',
        'seller_id': '',
        'seller_name': 'warehouse',
        'product_id': (variantSnap.data()?['product_id'] as String?) ?? '',
        'variant_id': variantId,
        'variant_name': (variantSnap.data()?['variant_name'] as String?) ?? '',
        'quantity': delta.abs(),
        'direction': delta >= 0 ? 'in' : 'out',
        'notes': 'manual_adjustment',
        'created_by': adminId,
        'created_at': now,
      });
    });
  }

  Future<void> batchAdjustStock(Map<String, int> updates) async {
    if (updates.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    final collRef = FirebaseFirestore.instance.collection(
      Collections.productVariants,
    );

    for (final entry in updates.entries) {
      batch.update(collRef.doc(entry.key), {
        'quantity_available': FieldValue.increment(entry.value),
        'updated_at': Timestamp.now(),
      });
    }

    await batch.commit();
  }

  /// Transfers stock from warehouse to a seller.
  /// Atomically decrements (variant.quantity_available) and logs a
  /// stock_transfer record in the transactions collection.
  Future<void> transferToSeller({
    required String variantId,
    required String variantName,
    required String productId,
    required String sellerId,
    required String sellerName,
    required int quantity,
    required String adminId,
  }) async {
    await _requireAdmin();
    final normalizedAdminId = adminId.trim();
    final normalizedSellerId = sellerId.trim();
    if (normalizedAdminId.isEmpty) {
      throw ArgumentError('adminId must not be empty');
    }
    if (normalizedSellerId.isEmpty) {
      throw ArgumentError('sellerId must not be empty');
    }
    if (quantity <= 0) {
      throw ArgumentError('quantity must be positive');
    }
    final db = FirebaseFirestore.instance;
    final now = Timestamp.now();

    await db.runTransaction<void>((txn) async {
      final variantRef = db
          .collection(Collections.productVariants)
          .doc(variantId);
      final variantSnap = await txn.get(variantRef);
      if (!variantSnap.exists) {
        throw ArgumentError('Variant not found: $variantId');
      }

      final currentQty =
          (variantSnap.data()?['quantity_available'] as num?)?.toInt() ?? 0;
      if (currentQty < quantity) {
        throw ArgumentError('Not enough warehouse stock for transfer');
      }

      txn.update(variantRef, {
        'quantity_available': currentQty - quantity,
        'updated_at': now,
      });

      final sellerInventoryRef = db
          .collection(Collections.sellerInventory)
          .doc('${normalizedSellerId}_$variantId');
      final sellerSnap = await txn.get(sellerInventoryRef);
      final sellerCurrent =
          (sellerSnap.data()?['quantity_available'] as num?)?.toInt() ?? 0;
      txn.set(sellerInventoryRef, {
        'seller_id': normalizedSellerId,
        'seller_name': sellerName,
        'product_id': productId,
        'variant_id': variantId,
        'variant_name': variantName,
        'quantity_available': sellerCurrent + quantity,
        'active': true,
        'created_at': sellerSnap.exists
            ? (sellerSnap.data()?['created_at'] ?? now)
            : now,
        'updated_at': now,
      }, SetOptions(merge: true));

      // Audit log — write to inventory_transactions (matches allInventoryTransactionsProvider query)
      final auditRef = db.collection(Collections.inventoryTransactions).doc();
      txn.set(auditRef, {
        'type': 'transfer_out',
        'seller_id': normalizedSellerId,
        'seller_name': sellerName,
        'product_id': productId,
        'variant_id': variantId,
        'variant_name': variantName,
        'quantity': quantity,
        'notes': null,
        'created_by': normalizedAdminId,
        'created_at': now,
      });
    });
  }
}

final productNotifierProvider = AsyncNotifierProvider<ProductNotifier, void>(
  ProductNotifier.new,
);
