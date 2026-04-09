import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../models/shop_model.dart';
import 'auth_provider.dart';

// =============================================================================
// ShopProvider — all reads and writes for retail shops.
//
// DATA LAYER:
//   Shops are stored in Firestore collection 'customers' (legacy name).
//   Use Collections.shops alias in new code — both resolve to 'customers'.
//
// PROVIDERS:
//   shopsProvider                      → admin: all active shops
//   shopsByRouteProvider(routeId)      → seller/admin: shops on a specific route
//   shopDetailProvider(id)             → single shop live stream
//   outstandingShopsProvider           → admin: shops with balance > 0
//   outstandingShopsByRouteProvider    → seller: outstanding shops on their route
//
// NOTIFIER METHODS:
//   create()         → new shop (seller + admin)
//   updateShop()     → edit name/address/etc (admin + seller in own route)
//   markAsBadDebt()  → admin only: zero balance, flag write-off in transactions
//   deactivate()     → admin only: soft-delete (active=false)
// =============================================================================

final shopsProvider = StreamProvider.autoDispose<List<ShopModel>>((ref) {
  // Admin-only unfiltered query: guard to prevent PERMISSION_DENIED
  // during auth transitions when seller credentials are active.
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null || !user.isAdmin) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection(Collections.customers)
      .where('active', isEqualTo: true)
      .orderBy('name')
      .limit(500)
      .snapshots()
      .map(
        (snap) =>
            snap.docs.map((d) => ShopModel.fromJson(d.data(), d.id)).toList(),
      );
});

final shopsByRouteProvider = StreamProvider.autoDispose
    .family<List<ShopModel>, String>((ref, routeId) {
      return FirebaseFirestore.instance
          .collection(Collections.customers)
          .where('route_id', isEqualTo: routeId)
          .where('active', isEqualTo: true)
          .orderBy('name')
          .limit(200)
          .snapshots()
          .map(
            (snap) => snap.docs
                .map((d) => ShopModel.fromJson(d.data(), d.id))
                .toList(),
          );
    });

final shopDetailProvider = StreamProvider.autoDispose
    .family<ShopModel?, String>((ref, id) {
      final user = ref.watch(authUserProvider).valueOrNull;
      if (user == null) return const Stream.empty();
      if (user.isAdmin) {
        return FirebaseFirestore.instance
            .collection(Collections.customers)
            .doc(id)
            .snapshots()
            .map(
              (doc) =>
                  doc.exists ? ShopModel.fromJson(doc.data()!, doc.id) : null,
            );
      }
      if (!user.isSeller || user.assignedRouteId == null) {
        return const Stream.empty();
      }
      return FirebaseFirestore.instance
          .collection(Collections.customers)
          .where(FieldPath.documentId, isEqualTo: id)
          .where('route_id', isEqualTo: user.assignedRouteId)
          .limit(1)
          .snapshots()
          .map(
            (snap) {
              if (snap.docs.isEmpty) return null;
              final doc = snap.docs.first;
              return ShopModel.fromJson(doc.data(), doc.id);
            },
          );
    });

final outstandingShopsProvider = StreamProvider.autoDispose<List<ShopModel>>((
  ref,
) {
  // Admin-only unfiltered query: guard to prevent PERMISSION_DENIED.
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null || !user.isAdmin) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection(Collections.customers)
      .where('active', isEqualTo: true)
      .where('balance', isGreaterThan: 0)
      .orderBy('balance', descending: true)
      .limit(200)
      .snapshots()
      .map(
        (snap) =>
            snap.docs.map((d) => ShopModel.fromJson(d.data(), d.id)).toList(),
      );
});

final outstandingShopsByRouteProvider = StreamProvider.autoDispose
    .family<List<ShopModel>, String>((ref, routeId) {
      return FirebaseFirestore.instance
          .collection(Collections.customers)
          .where('route_id', isEqualTo: routeId)
          .where('active', isEqualTo: true)
          .where('balance', isGreaterThan: 0)
          .orderBy('balance', descending: true)
          .limit(200)
          .snapshots()
          .map(
            (snap) => snap.docs
                .map((d) => ShopModel.fromJson(d.data(), d.id))
                .toList(),
          );
    });

class ShopNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> create(Map<String, dynamic> data) async {
    final db = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) throw StateError('Not authenticated');
    // Create customer/shop first (sellers + admins have permission)
    await db.collection(Collections.customers).add({
      ...data,
      if (!data.containsKey('created_by')) 'created_by': uid,
      'balance': 0.0,
      'active': true,
      'created_at': Timestamp.now(),
      'updated_at': Timestamp.now(),
    });
    // Try to increment route total_shops (may fail for sellers â€” non-critical)
    try {
      final routeId = data['route_id'] as String;
      await db.collection(Collections.routes).doc(routeId).update({
        'total_shops': FieldValue.increment(1),
      });
    } catch (_) {}
  }

  Future<void> updateShop(String id, Map<String, dynamic> data) async {
    await FirebaseFirestore.instance
        .collection(Collections.customers)
        .doc(id)
        .update({...data, 'updated_at': Timestamp.now()});
  }

  /// Admin-only: marks a shop as bad debt, writes off outstanding balance.
  Future<void> markAsBadDebt(String shopId) async {
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
    final shopDoc = await db
        .collection(Collections.customers)
        .doc(shopId)
        .get();
    final balance = (shopDoc.data()?['balance'] as num?)?.toDouble() ?? 0;
    if (balance <= 0) throw StateError('No outstanding balance to write off');

    final batch = db.batch();

    // Mark shop as bad debt
    batch.update(db.collection(Collections.customers).doc(shopId), {
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
      'shop_id': shopId,
      'shop_name': shopDoc.data()?['name'] ?? '',
      'route_id': shopDoc.data()?['route_id'] ?? '',
      'customer_id': shopId,
      'customer_name': shopDoc.data()?['name'] ?? '',
      'amount': balance,
      'description': 'Bad debt write-off',
      'items': <Map<String, dynamic>>[],
      'created_by': authUser.uid,
      'created_at': Timestamp.now(),
      'deleted': false,
    });

    await batch.commit();
  }

  Future<void> deactivate(String id, String routeId) async {
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
      throw StateError('Only admin can delete shops');
    }

    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    batch.update(db.collection(Collections.customers).doc(id), {
      'active': false,
      'updated_at': Timestamp.now(),
    });
    if (routeId.trim().isNotEmpty) {
      batch.update(db.collection(Collections.routes).doc(routeId), {
        'total_shops': FieldValue.increment(-1),
      });
    }
    await batch.commit();
  }
}

final shopNotifierProvider = AsyncNotifierProvider<ShopNotifier, void>(
  ShopNotifier.new,
);
