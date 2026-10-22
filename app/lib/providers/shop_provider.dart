import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../core/utils/firestore_pagination.dart';
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
  return query.where('active', isEqualTo: true).limit(500).snapshots().map((
    snap,
  ) {
    final shops = snap.docs
        .map((d) => ShopModel.fromJson(d.data(), d.id))
        .toList();
    shops.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return shops;
  });
});

final shopsByRouteProvider = StreamProvider.autoDispose
    .family<List<ShopModel>, String>((ref, routeId) {
      final profileReady = ref.watch(
        authUserProvider.select((s) => s.hasValue && s.value != null),
      );
      if (!profileReady) return const Stream.empty();
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
          .limit(200)
          .snapshots()
          .map((snap) {
            final shops = snap.docs
                .map((d) => ShopModel.fromJson(d.data(), d.id))
                .toList();
            shops.sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
            return shops;
          });
    });

/// Complete role-scoped shop dataset for explicit report/export actions.
/// Live UI providers remain windowed; this query cursor-pages to exhaustion.
final shopsExportProvider = FutureProvider<List<ShopModel>>((ref) async {
  final user = await ref.read(authUserProvider.future);
  if (user == null || !user.active) return const <ShopModel>[];
  final tenantId = TenantScope.normalize(user.tenantId);
  if (tenantId == null) return const <ShopModel>[];

  final baseQuery = TenantScope.applyToQuery(
    FirebaseFirestore.instance.collection(Collections.shops),
    tenantId: tenantId,
  );
  final queryParts = <Query<Map<String, dynamic>>>[];
  if (user.isAdmin) {
    queryParts.add(baseQuery.where('active', isEqualTo: true));
  } else if (user.isSeller) {
    final routeIds = user.assignedRouteIds.toSet().toList();
    for (var offset = 0; offset < routeIds.length; offset += 30) {
      final end = (offset + 30).clamp(0, routeIds.length);
      queryParts.add(
        baseQuery
            .where('route_id', whereIn: routeIds.sublist(offset, end))
            .where('active', isEqualTo: true),
      );
    }
  } else {
    return const <ShopModel>[];
  }

  final documentsById = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
  for (final query in queryParts) {
    for (final document in await fetchAllQueryDocuments(query)) {
      documentsById[document.id] = document;
    }
  }
  final shops = documentsById.values
      .map((document) => ShopModel.fromJson(document.data(), document.id))
      .toList();
  shops.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return shops;
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
      .limit(500)
      .snapshots()
      .map((snap) {
        final shops = snap.docs
            .map((d) => ShopModel.fromJson(d.data(), d.id))
            .toList();
        shops.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        return shops;
      });
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
      .limit(200)
      .snapshots()
      .map((snap) {
        final shops = snap.docs
            .map((d) => ShopModel.fromJson(d.data(), d.id))
            .toList();
        shops.sort((a, b) => b.balance.compareTo(a.balance));
        return shops;
      });
});

final outstandingShopsByRouteProvider = StreamProvider.autoDispose
    .family<List<ShopModel>, String>((ref, routeId) {
      final profileReady = ref.watch(
        authUserProvider.select((s) => s.hasValue && s.value != null),
      );
      if (!profileReady) return const Stream.empty();
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
          .limit(200)
          .snapshots()
          .map((snap) {
            final shops = snap.docs
                .map((d) => ShopModel.fromJson(d.data(), d.id))
                .toList();
            shops.sort((a, b) => b.balance.compareTo(a.balance));
            return shops;
          });
    });

class ShopNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> create(Map<String, dynamic> data) async {
    final db = FirebaseFirestore.instance;
    final currentUser = await ref.read(authUserProvider.future);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty ||
        currentUser == null ||
        !currentUser.active ||
        currentUser.id != uid) {
      throw StateError('An active user profile is required');
    }
    if (!currentUser.isAdmin && !currentUser.isSeller) {
      throw StateError('Only admins and assigned sellers can create shops');
    }
    final tenantId = TenantScope.requireTenant(currentUser.tenantId);
    final routeId = (data['route_id'] as String? ?? '').trim();
    final name = (data['name'] as String? ?? '').trim();
    if (routeId.isEmpty) throw ArgumentError('routeId must not be empty');
    if (name.isEmpty) throw ArgumentError('name must not be empty');
    if (currentUser.isSeller &&
        !currentUser.assignedRouteIds.contains(routeId)) {
      throw StateError('Sellers can only create shops on assigned routes');
    }

    final shopRef = db.collection(Collections.customers).doc();
    final routeRef = db.collection(Collections.routes).doc(routeId);
    await db.runTransaction<void>((transaction) async {
      final routeSnapshot = await transaction.get(routeRef);
      final routeData = routeSnapshot.data();
      if (routeData == null ||
          !TenantScope.matchesTenant(routeData, tenantId) ||
          routeData['active'] != true) {
        throw StateError('Selected route is unavailable');
      }

      final totalShops = (routeData['total_shops'] as num?)?.toInt() ?? 0;
      final now = Timestamp.now();
      transaction.set(shopRef, {
        ...TenantScope.applyToData(data, tenantId: tenantId),
        'name': name,
        'route_id': routeId,
        'route_number':
            (routeData['route_number'] as num?)?.toInt() ??
            (data['route_number'] as num?)?.toInt() ??
            0,
        'created_by': uid,
        'balance': 0.0,
        'active': true,
        'created_at': now,
        'updated_at': now,
      });
      transaction.update(routeRef, {
        'total_shops': totalShops + 1,
        'last_shop_created_id': shopRef.id,
        'updated_at': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> updateShop(String id, Map<String, dynamic> data) async {
    final currentUser = await ref.read(authUserProvider.future);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty ||
        currentUser == null ||
        !currentUser.active ||
        currentUser.id != uid) {
      throw StateError('An active user profile is required');
    }
    if (!currentUser.isAdmin && !currentUser.isSeller) {
      throw StateError('Only admins and sellers can update shops');
    }
    final tenantId = TenantScope.requireTenant(currentUser.tenantId);
    const adminFields = <String>{
      'name',
      'route_id',
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
    const sellerFields = <String>{
      'name',
      'phone',
      'address',
      'area',
      'city',
      'contact_name',
      'notes',
      'latitude',
      'longitude',
    };
    final allowedFields = currentUser.isAdmin ? adminFields : sellerFields;
    final filteredData = <String, dynamic>{
      for (final entry in data.entries)
        if (allowedFields.contains(entry.key)) entry.key: entry.value,
    };

    final requestedRouteId = (data['route_id'] as String? ?? '').trim();
    if (currentUser.isSeller &&
        requestedRouteId.isNotEmpty &&
        !currentUser.assignedRouteIds.contains(requestedRouteId)) {
      throw StateError('Sellers can only manage shops on assigned routes');
    }
    if (filteredData.isEmpty && requestedRouteId.isEmpty) {
      throw ArgumentError('No writable shop fields were provided');
    }

    final db = FirebaseFirestore.instance;
    final shopRef = db.collection(Collections.customers).doc(id);
    await db.runTransaction<void>((transaction) async {
      final shopSnapshot = await transaction.get(shopRef);
      final shop = shopSnapshot.data();
      if (shop == null || !TenantScope.matchesTenant(shop, tenantId)) {
        throw StateError('Shop is unavailable in this workspace');
      }
      final currentRouteId = (shop['route_id'] as String? ?? '').trim();
      if (currentUser.isSeller &&
          (currentRouteId.isEmpty ||
              !currentUser.assignedRouteIds.contains(currentRouteId))) {
        throw StateError('Sellers can only manage shops on assigned routes');
      }

      final targetRouteId = currentUser.isAdmin && requestedRouteId.isNotEmpty
          ? requestedRouteId
          : currentRouteId;
      final routeChanged = targetRouteId != currentRouteId;
      DocumentSnapshot<Map<String, dynamic>>? oldRouteSnapshot;
      DocumentSnapshot<Map<String, dynamic>>? newRouteSnapshot;
      DocumentReference<Map<String, dynamic>>? oldRouteRef;
      DocumentReference<Map<String, dynamic>>? newRouteRef;

      if (routeChanged) {
        oldRouteRef = db.collection(Collections.routes).doc(currentRouteId);
        newRouteRef = db.collection(Collections.routes).doc(targetRouteId);
        oldRouteSnapshot = await transaction.get(oldRouteRef);
        newRouteSnapshot = await transaction.get(newRouteRef);
        final oldRoute = oldRouteSnapshot.data();
        final newRoute = newRouteSnapshot.data();
        if (oldRoute == null ||
            !TenantScope.matchesTenant(oldRoute, tenantId) ||
            newRoute == null ||
            !TenantScope.matchesTenant(newRoute, tenantId) ||
            newRoute['active'] != true) {
          throw StateError('Selected route is unavailable');
        }
      } else if (requestedRouteId.isNotEmpty &&
          requestedRouteId != currentRouteId) {
        throw StateError('Sellers cannot reassign shops to another route');
      }

      final update = <String, dynamic>{
        ...filteredData,
        'updated_at': Timestamp.now(),
      };
      if (currentUser.isAdmin && requestedRouteId.isNotEmpty) {
        update['route_id'] = targetRouteId;
      }
      if (routeChanged) {
        update['route_number'] =
            (newRouteSnapshot!.data()?['route_number'] as num?)?.toInt() ?? 0;
        final oldCount =
            (oldRouteSnapshot!.data()?['total_shops'] as num?)?.toInt() ?? 0;
        final newCount =
            (newRouteSnapshot.data()?['total_shops'] as num?)?.toInt() ?? 0;
        transaction.update(oldRouteRef!, {
          'total_shops': (oldCount - 1).clamp(0, 1 << 31),
          'updated_at': Timestamp.now(),
        });
        transaction.update(newRouteRef!, {
          'total_shops': newCount + 1,
          'updated_at': Timestamp.now(),
        });
      }
      transaction.update(shopRef, update);
    });
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
    final tenantId = TenantScope.requireTenant(
      (await ref.read(authUserProvider.future))?.tenantId,
    );
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
      'tenant_id': tenantId,
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
    final tenantId = TenantScope.requireTenant(
      (await ref.read(authUserProvider.future))?.tenantId,
    );
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
      'tenant_id': tenantId,
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
    final currentUser = await ref.read(authUserProvider.future);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty ||
        currentUser == null ||
        !currentUser.active ||
        currentUser.id != uid) {
      throw StateError('An active user profile is required');
    }
    if (!currentUser.isAdmin) {
      throw StateError('Only admin can delete shops');
    }

    final db = FirebaseFirestore.instance;
    final tenantId = TenantScope.requireTenant(currentUser.tenantId);
    final shopRef = db.collection(Collections.customers).doc(id);
    await db.runTransaction<void>((transaction) async {
      final shopSnapshot = await transaction.get(shopRef);
      final shop = shopSnapshot.data();
      if (shop == null || !TenantScope.matchesTenant(shop, tenantId)) {
        throw StateError('Shop is unavailable in this workspace');
      }
      if (shop['active'] != true) {
        throw StateError('Shop is already inactive');
      }
      final linkedRouteId = (shop['route_id'] as String? ?? '').trim();
      if (routeId.trim().isNotEmpty && routeId.trim() != linkedRouteId) {
        throw StateError('Shop route changed; refresh and try again');
      }

      DocumentReference<Map<String, dynamic>>? routeRef;
      DocumentSnapshot<Map<String, dynamic>>? routeSnapshot;
      if (linkedRouteId.isNotEmpty) {
        routeRef = db.collection(Collections.routes).doc(linkedRouteId);
        routeSnapshot = await transaction.get(routeRef);
        final route = routeSnapshot.data();
        if (route == null || !TenantScope.matchesTenant(route, tenantId)) {
          throw StateError('Shop route is unavailable in this workspace');
        }
      }

      transaction.update(shopRef, {
        'active': false,
        'updated_at': Timestamp.now(),
      });
      if (routeRef != null) {
        final totalShops =
            (routeSnapshot!.data()?['total_shops'] as num?)?.toInt() ?? 0;
        transaction.update(routeRef, {
          'total_shops': (totalShops - 1).clamp(0, 1 << 31),
          'updated_at': Timestamp.now(),
        });
      }
    });
  }
}

final shopNotifierProvider = AsyncNotifierProvider<ShopNotifier, void>(
  ShopNotifier.new,
);
