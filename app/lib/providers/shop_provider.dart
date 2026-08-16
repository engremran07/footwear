import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../core/utils/role_utils.dart';
import '../core/utils/tenant_scope.dart';
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
  // Use select() so this provider only rebuilds when the admin flag changes,
  // not on every user-doc heartbeat / field update.
  final isAdmin = ref.watch(
    authUserProvider.select((s) => s.value?.isAdmin ?? false),
  );
  final tenantId = ref.watch(
    authUserProvider.select((s) => TenantScope.normalize(s.value?.tenantId)),
  );
  if (!isAdmin) return const Stream.empty();
  final query = TenantScope.applyToQuery(
    FirebaseFirestore.instance.collection(Collections.customers),
    tenantId: tenantId,
  );
  return query
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
      final tenantId = ref.watch(
        authUserProvider.select(
          (s) => TenantScope.normalize(s.value?.tenantId),
        ),
      );
      final query = TenantScope.applyToQuery(
        FirebaseFirestore.instance.collection(Collections.customers),
        tenantId: tenantId,
      );
      return query
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

/// Seller multi-route: merges shops from all assigned routes into one list.
final sellerAllShopsProvider = StreamProvider.autoDispose<List<ShopModel>>((
  ref,
) {
  // Use select() with a string key (not List<String>) so Riverpod's == check
  // correctly identifies no-change on heartbeat writes to last_active.
  // List<String> uses reference equality — new object every Firestore snapshot
  // would always be "changed", restarting the stream and causing shimmer.
  ref.keepAlive();
  final tenantId = ref.watch(
    authUserProvider.select((s) => TenantScope.normalize(s.value?.tenantId)),
  );
  final routeKey = ref.watch(
    authUserProvider.select((s) {
      final u = s.value;
      if (u == null || !u.isSeller || u.assignedRouteIds.isEmpty) return '';
      final sorted = List<String>.from(u.assignedRouteIds)..sort();
      return sorted.join(',');
    }),
  );
  if (routeKey.isEmpty) return const Stream.empty();
  final routeIds = routeKey.split(',');
  // Firestore whereIn supports up to 30 values — ample for route count.
  final query = TenantScope.applyToQuery(
    FirebaseFirestore.instance.collection(Collections.customers),
    tenantId: tenantId,
  );
  return query
      .where('route_id', whereIn: routeIds)
      .where('active', isEqualTo: true)
      .orderBy('name')
      .limit(500)
      .snapshots()
      .map(
        (snap) =>
            snap.docs.map((d) => ShopModel.fromJson(d.data(), d.id)).toList(),
      );
});

final shopDetailProvider = StreamProvider.autoDispose.family<ShopModel?, String>(
  (ref, id) {
    // Use select() with a string key (not List<String>) to avoid restarting
    // the stream on every heartbeat. List == uses reference equality which
    // would always be "changed" on each new UserModel snapshot.
    final (isAdmin, isSeller, routeKey) = ref.watch(
      authUserProvider.select((s) {
        final u = s.value;
        if (u == null) return (false, false, '');
        if (u.isAdmin) return (true, false, '');
        if (!u.isSeller) return (false, false, '');
        final sorted = List<String>.from(u.assignedRouteIds)..sort();
        return (false, true, sorted.join(','));
      }),
    );
    final tenantId = ref.watch(
      authUserProvider.select((s) => TenantScope.normalize(s.value?.tenantId)),
    );
    final routeIds = routeKey.isEmpty ? <String>[] : routeKey.split(',');
    if (!isAdmin && !isSeller) return const Stream.empty();
    if (isAdmin) {
      return FirebaseFirestore.instance
          .collection(Collections.customers)
          .doc(id)
          .snapshots()
          .map((doc) {
            if (!doc.exists) return null;
            if (!TenantScope.matchesTenant(doc.data(), tenantId)) return null;
            return ShopModel.fromJson(doc.data()!, doc.id);
          });
    }
    if (!isSeller || routeIds.isEmpty) {
      return const Stream.empty();
    }
    // Direct doc read — Firestore rules enforce route membership.
    // A collection query with whereIn caused an auth loading race that
    // produced "Details" in the breadcrumb instead of the shop name.
    return FirebaseFirestore.instance
        .collection(Collections.customers)
        .doc(id)
        .snapshots()
        .map((doc) {
          if (!doc.exists) return null;
          if (!TenantScope.matchesTenant(doc.data(), tenantId)) return null;
          final shop = ShopModel.fromJson(doc.data()!, doc.id);
          // Client-side guard: hide shops outside the seller's assigned routes.
          if (!routeIds.contains(shop.routeId)) return null;
          return shop;
        });
  },
);

final outstandingShopsProvider = StreamProvider.autoDispose<List<ShopModel>>((
  ref,
) {
  // Admin-only unfiltered query: guard to prevent PERMISSION_DENIED.
  final isAdmin = ref.watch(
    authUserProvider.select((s) => s.value?.isAdmin ?? false),
  );
  final tenantId = ref.watch(
    authUserProvider.select((s) => TenantScope.normalize(s.value?.tenantId)),
  );
  if (!isAdmin) return const Stream.empty();
  final query = TenantScope.applyToQuery(
    FirebaseFirestore.instance.collection(Collections.customers),
    tenantId: tenantId,
  );
  return query
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
      final tenantId = ref.watch(
        authUserProvider.select(
          (s) => TenantScope.normalize(s.value?.tenantId),
        ),
      );
      final query = TenantScope.applyToQuery(
        FirebaseFirestore.instance.collection(Collections.customers),
        tenantId: tenantId,
      );
      return query
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
    final tenantId =
        TenantScope.normalize(ref.read(authUserProvider).value?.tenantId) ??
        TenantScope.globalTenantId;
    // Pre-generate doc ID so retries on network failure are idempotent
    // (using add() can create a duplicate if the first write succeeds but
    // the ACK is lost and the SDK retries the request).
    final shopRef = db.collection(Collections.customers).doc();
    await shopRef.set({
      ...TenantScope.applyToData(data, tenantId: tenantId),
      // Always overwrite created_by with the verified Firebase Auth uid.
      // Screens may pass an empty string if authUserProvider hasn't resolved
      // yet; using the Auth uid directly is the authoritative source.
      'created_by': uid,
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
    const allowedFields = <String>{
      'name',
      'route_id',
      'route_number',
      'phone',
      'address',
      'area',
      'city',
      'contact_name',
      'category',
      'notes',
      'latitude',
      'longitude',
    };
    final filteredData = <String, dynamic>{
      for (final entry in data.entries)
        if (allowedFields.contains(entry.key)) entry.key: entry.value,
    };

    if (filteredData.isEmpty) {
      throw ArgumentError('No writable shop fields were provided');
    }

    await FirebaseFirestore.instance
        .collection(Collections.customers)
        .doc(id)
        .update({...filteredData, 'updated_at': Timestamp.now()});
  }

  /// Admin-only: marks a shop as bad debt, writes off outstanding balance.
  Future<void> markAsBadDebt(String shopId) async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) throw StateError('Not authenticated');
    final me = await FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(authUser.uid)
        .get();
    final role = (me.data()?['role'] as String? ?? '').trim();
    if (!isPrivilegedRoleName(role)) {
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
      'last_transaction_at': Timestamp.now(),
      'last_transaction_type': 'write_off',
      'last_transaction_amount': balance,
    });

    // Create write_off transaction
    final txRef = db.collection(Collections.transactions).doc();
    batch.set(txRef, {
      'type': 'write_off',
      'shop_id': shopId,
      'shop_name': shopDoc.data()?['name'] ?? '',
      'route_id': shopDoc.data()?['route_id'] ?? '',
      'amount': balance,
      'description': 'Bad debt write-off',
      'items': <Map<String, dynamic>>[],
      'created_by': authUser.uid,
      'created_at': Timestamp.now(),
      'deleted': false,
    });

    await batch.commit();
  }

  /// Admin-only: recovers a bad-debt shop, restoring its written-off balance.
  Future<void> recoverBadDebt(String shopId) async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) throw StateError('Not authenticated');
    final me = await FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(authUser.uid)
        .get();
    final role = (me.data()?['role'] as String? ?? '').trim();
    if (!isPrivilegedRoleName(role)) {
      throw StateError('Only admin can recover bad debt');
    }

    final db = FirebaseFirestore.instance;
    final shopDoc = await db
        .collection(Collections.customers)
        .doc(shopId)
        .get();
    final isBadDebt = shopDoc.data()?['bad_debt'] as bool? ?? false;
    if (!isBadDebt) throw StateError('Shop is not marked as bad debt');
    final amount =
        (shopDoc.data()?['bad_debt_amount'] as num?)?.toDouble() ?? 0;

    final batch = db.batch();

    // Restore shop: un-flag bad debt, restore balance
    batch.update(db.collection(Collections.customers).doc(shopId), {
      'bad_debt': false,
      'bad_debt_amount': 0,
      'bad_debt_date': null,
      'balance': amount,
      'updated_at': Timestamp.now(),
      'last_transaction_at': Timestamp.now(),
      'last_transaction_type': 'cash_out',
      'last_transaction_amount': amount,
    });

    // Create recovery transaction to record the reversal
    final txRef = db.collection(Collections.transactions).doc();
    batch.set(txRef, {
      'type': 'cash_out',
      'shop_id': shopId,
      'shop_name': shopDoc.data()?['name'] ?? '',
      'route_id': shopDoc.data()?['route_id'] ?? '',
      'amount': amount,
      'description': 'Bad debt recovered — balance restored',
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
    final role = (me.data()?['role'] as String? ?? '').trim();
    if (!isPrivilegedRoleName(role)) {
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
