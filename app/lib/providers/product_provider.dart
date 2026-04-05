import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../models/product_model.dart';
import '../models/product_variant_model.dart';

final productsProvider =
    StreamProvider.autoDispose<List<ProductModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.products)
      .where('active', isEqualTo: true)
      .orderBy('name')
      .limit(200)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => ProductModel.fromJson(d.data(), d.id)).toList());
});

final productDetailProvider =
    StreamProvider.autoDispose.family<ProductModel?, String>((ref, id) {
  return FirebaseFirestore.instance
      .collection(Collections.products)
      .doc(id)
      .snapshots()
      .map((doc) =>
          doc.exists ? ProductModel.fromJson(doc.data()!, doc.id) : null);
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
      .map((snap) => snap.docs
          .map((d) => ProductVariantModel.fromJson(d.data(), d.id))
          .toList());
});

final allVariantsProvider =
    StreamProvider.autoDispose<List<ProductVariantModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.productVariants)
      .where('active', isEqualTo: true)
      .orderBy('variant_name')
      .limit(500)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => ProductVariantModel.fromJson(d.data(), d.id))
          .toList());
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
    await FirebaseFirestore.instance
        .collection(Collections.productVariants)
        .doc(id)
        .update({...data, 'updated_at': Timestamp.now()});
  }

  Future<void> deleteVariant(String id) async {
    await FirebaseFirestore.instance
        .collection(Collections.productVariants)
        .doc(id)
        .update({'active': false, 'updated_at': Timestamp.now()});
  }

  Future<void> adjustStock(String variantId, int delta) async {
    await FirebaseFirestore.instance
        .collection(Collections.productVariants)
        .doc(variantId)
        .update({
      'quantity_available': FieldValue.increment(delta),
      'updated_at': Timestamp.now(),
    });
  }

  Future<void> batchAdjustStock(Map<String, int> updates) async {
    if (updates.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    final collRef =
        FirebaseFirestore.instance.collection(Collections.productVariants);

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
    final normalizedAdminId = adminId.trim();
    if (normalizedAdminId.isEmpty) {
      throw ArgumentError('adminId must not be empty');
    }
    if (quantity <= 0) {
      throw ArgumentError('quantity must be positive');
    }

    final db = FirebaseFirestore.instance;
    final batch = db.batch();

    // Decrement warehouse stock
    batch.update(
      db.collection(Collections.productVariants).doc(variantId),
      {
        'quantity_available': FieldValue.increment(-quantity),
        'updated_at': Timestamp.now(),
      },
    );

    final sellerInventoryRef = db
        .collection(Collections.sellerInventory)
        .doc('${sellerId}_$variantId');
    batch.set(
      sellerInventoryRef,
      {
        'seller_id': sellerId,
        'seller_name': sellerName,
        'product_id': productId,
        'variant_id': variantId,
        'variant_name': variantName,
        'quantity_available': FieldValue.increment(quantity),
        'active': true,
        'created_at': Timestamp.now(),
        'updated_at': Timestamp.now(),
      },
      SetOptions(merge: true),
    );

    // Log transfer in transactions collection
    final txRef = db.collection(Collections.transactions).doc();
    batch.set(txRef, {
      'type': 'stock_transfer',
      'shop_id': '',
      'shop_name': '',
      'route_id': '',
      'seller_id': sellerId,
      'seller_name': sellerName,
      'product_id': productId,
      'variant_id': variantId,
      'variant_name': variantName,
      'quantity': quantity,
      'amount': 0.0,
      'description': 'Stock transfer to $sellerName',
      'items': <Map<String, dynamic>>[],
      'created_by': normalizedAdminId,
      'created_at': Timestamp.now(),
    });

    await batch.commit();
  }
}

final productNotifierProvider =
    AsyncNotifierProvider<ProductNotifier, void>(ProductNotifier.new);
