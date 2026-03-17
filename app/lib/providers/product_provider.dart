import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../models/product_model.dart';

final productsProvider = StreamProvider<List<ProductModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.products)
      .where('active', isEqualTo: true)
      .orderBy('created_at', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => ProductModel.fromJson(d.data(), d.id)).toList());
});

final allProductsProvider = StreamProvider<List<ProductModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.products)
      .orderBy('created_at', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => ProductModel.fromJson(d.data(), d.id)).toList());
});

final productDetailProvider =
    StreamProvider.family<ProductModel?, String>((ref, id) {
  return FirebaseFirestore.instance
      .collection(Collections.products)
      .doc(id)
      .snapshots()
      .map((doc) =>
          doc.exists ? ProductModel.fromJson(doc.data()!, doc.id) : null);
});

class ProductNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<String> uploadImage(String fileId, Uint8List bytes) async {
    state = const AsyncLoading();
    try {
      final ref = FirebaseStorage.instance.ref('products/$fileId.jpg');
      await ref.putData(bytes);
      final url = await ref.getDownloadURL();
      state = const AsyncData(null);
      return url;
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> create(Map<String, dynamic> data) async {
    state = const AsyncLoading();
    try {
      await FirebaseFirestore.instance.collection(Collections.products).add({
        ...data,
        'stock_count': 0,
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
          .collection(Collections.products)
          .doc(id)
          .update({
        ...data,
        'updated_at': Timestamp.now(),
      });
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
          .collection(Collections.products)
          .doc(id)
          .update({'active': false, 'updated_at': Timestamp.now()});
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final productNotifierProvider =
    AsyncNotifierProvider<ProductNotifier, void>(ProductNotifier.new);
