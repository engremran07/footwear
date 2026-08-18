import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../core/utils/tenant_scope.dart';
import '../models/user_model.dart';
import 'auth_provider.dart';

/// Result of a flush operation — reports affected document count.
class FlushResult {
  final int deletedCount;
  final int resetCount;
  final String operation;
  FlushResult({
    required this.deletedCount,
    required this.resetCount,
    required this.operation,
  });
  int get totalAffected => deletedCount + resetCount;
}

class DatabaseFlushNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Verifies the current user is super_admin (only role allowed to perform unrestricted flush).
  /// P0-1 FIX: Only super_admin can flush data (not tenant_admin or regular admin).
  UserModel _requireSuperAdmin() {
    final user = ref.read(authUserProvider).value;
    if (user == null || !user.isSuperAdmin) {
      throw ArgumentError(
        'Only super_admin can perform database flush operations',
      );
    }
    return user;
  }

  /// Re-authenticates the current user with their password.
  /// Returns true if successful.
  Future<bool> reauthenticate(String password) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return false;
    try {
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);
      return true;
    } on FirebaseAuthException {
      return false;
    }
  }

  /// Deletes all documents in a collection using batched writes (max 400/batch).
  /// If tenantId is provided, only deletes docs matching that tenant_id.
  /// P0-1 FIX: Add tenant filtering to prevent cross-tenant deletion.
  /// Returns the number of deleted documents.
  Future<int> _deleteCollection(
    String collectionPath, {
    String? tenantId,
  }) async {
    int deleted = 0;
    while (true) {
      Query query = _db.collection(collectionPath).limit(400);
      if (tenantId != null) {
        query = query.where('tenant_id', isEqualTo: tenantId);
      }
      final snap = await query.get();
      if (snap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      deleted += snap.docs.length;
    }
    return deleted;
  }

  /// Deletes documents in a collection where a field matches a value.
  /// If tenantId is provided, also filters by tenant_id.
  /// P0-1 FIX: Add tenant filtering to prevent cross-tenant deletion.
  Future<int> _deleteWhere(
    String collectionPath,
    String field,
    String value, {
    String? tenantId,
  }) async {
    int deleted = 0;
    while (true) {
      Query query = _db
          .collection(collectionPath)
          .where(field, isEqualTo: value)
          .limit(400);
      if (tenantId != null) {
        query = query.where('tenant_id', isEqualTo: tenantId);
      }
      final snap = await query.get();
      if (snap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      deleted += snap.docs.length;
    }
    return deleted;
  }

  /// Returns the document count for a collection.
  Future<int> getCollectionCount(String collectionPath) async {
    final snap = await _db.collection(collectionPath).count().get();
    return snap.count ?? 0;
  }

  // ─── Private Implementation Methods (no state management) ─────────────────
  //
  // These contain the business logic without touching [state].
  // Public methods wrap them with state management.
  // [flushAll] calls these directly to avoid state flickering.

  Future<FlushResult> _implFlushFinancialData({String? tenantId}) async {
    int deleted = 0;
    int reset = 0;

    // P0-1 FIX: Add tenantId filtering to all delete operations
    deleted += await _deleteCollection(
      Collections.invoices,
      tenantId: tenantId,
    );
    deleted += await _deleteCollection(
      Collections.transactions,
      tenantId: tenantId,
    );
    deleted += await _deleteCollection(
      Collections.inventoryTransactions,
      tenantId: tenantId,
    );

    // Reset invoice counter (merge — only updates this field)
    // For tenant scope: use the tenantId as the doc ID
    final settingsDocId = tenantId ?? TenantScope.globalTenantId;
    await _db.collection(Collections.settings).doc(settingsDocId).set({
      'last_invoice_number': 0,
      'updated_at': Timestamp.now(),
    }, SetOptions(merge: true));
    reset++;

    // Reset all shop balances to 0 (tenant-scoped if tenantId provided)
    Query shopsQuery = _db.collection(Collections.shops);
    if (tenantId != null) {
      shopsQuery = shopsQuery.where('tenant_id', isEqualTo: tenantId);
    }
    final shops = await shopsQuery.get();
    for (var i = 0; i < shops.docs.length; i += 400) {
      final batch = _db.batch();
      final end = (i + 400 > shops.docs.length) ? shops.docs.length : i + 400;
      for (var j = i; j < end; j++) {
        batch.update(shops.docs[j].reference, {
          'balance': 0.0,
          'bad_debt': false,
          'bad_debt_amount': 0.0,
          'updated_at': Timestamp.now(),
        });
      }
      await batch.commit();
      reset += end - i;
    }

    return FlushResult(
      deletedCount: deleted,
      resetCount: reset,
      operation: 'financial_data',
    );
  }

  Future<FlushResult> _implFlushInventory({String? tenantId}) async {
    int deleted = 0;
    int reset = 0;

    // P0-1 FIX: Add tenantId filtering
    deleted += await _deleteCollection(
      Collections.sellerInventory,
      tenantId: tenantId,
    );

    // Reset warehouse stock (product_variants.quantity_available → 0)
    Query variantsQuery = _db.collection(Collections.productVariants);
    if (tenantId != null) {
      variantsQuery = variantsQuery.where('tenant_id', isEqualTo: tenantId);
    }
    final variants = await variantsQuery.get();
    for (var i = 0; i < variants.docs.length; i += 400) {
      final batch = _db.batch();
      final end = (i + 400 > variants.docs.length)
          ? variants.docs.length
          : i + 400;
      for (var j = i; j < end; j++) {
        batch.update(variants.docs[j].reference, {
          'quantity_available': 0,
          'updated_at': Timestamp.now(),
        });
      }
      await batch.commit();
      reset += end - i;
    }

    return FlushResult(
      deletedCount: deleted,
      resetCount: reset,
      operation: 'inventory',
    );
  }

  Future<FlushResult> _implFlushShops({String? tenantId}) async {
    int deleted = 0;
    int reset = 0;

    // P0-1 FIX: Add tenantId filtering
    deleted += await _deleteCollection(Collections.shops, tenantId: tenantId);

    // Reset route total_shops counters (tenant-scoped)
    Query routesQuery = _db.collection(Collections.routes);
    if (tenantId != null) {
      routesQuery = routesQuery.where('tenant_id', isEqualTo: tenantId);
    }
    final routes = await routesQuery.get();
    for (var i = 0; i < routes.docs.length; i += 400) {
      final batch = _db.batch();
      final end = (i + 400 > routes.docs.length) ? routes.docs.length : i + 400;
      for (var j = i; j < end; j++) {
        batch.update(routes.docs[j].reference, {
          'total_shops': 0,
          'updated_at': Timestamp.now(),
        });
      }
      await batch.commit();
      reset += end - i;
    }

    return FlushResult(
      deletedCount: deleted,
      resetCount: reset,
      operation: 'shops',
    );
  }

  Future<FlushResult> _implFlushRoutes({String? tenantId}) async {
    int deleted = 0;
    int reset = 0;

    // P0-1 FIX: Add tenantId filtering
    deleted += await _deleteCollection(Collections.routes, tenantId: tenantId);

    // Clear assigned route arrays on all users (tenant-scoped)
    Query usersQuery = _db.collection(Collections.users);
    if (tenantId != null) {
      usersQuery = usersQuery.where('tenant_id', isEqualTo: tenantId);
    }
    final users = await usersQuery.get();
    for (var i = 0; i < users.docs.length; i += 400) {
      final batch = _db.batch();
      final end = (i + 400 > users.docs.length) ? users.docs.length : i + 400;
      for (var j = i; j < end; j++) {
        batch.update(users.docs[j].reference, {
          'assigned_route_ids': [],
          'assigned_route_names': [],
          'updated_at': Timestamp.now(),
        });
      }
      await batch.commit();
      reset += end - i;
    }

    return FlushResult(
      deletedCount: deleted,
      resetCount: reset,
      operation: 'routes',
    );
  }

  Future<FlushResult> _implFlushProducts({String? tenantId}) async {
    int deleted = 0;
    // P0-1 FIX: Add tenantId filtering
    deleted += await _deleteCollection(
      Collections.products,
      tenantId: tenantId,
    );
    deleted += await _deleteCollection(
      Collections.productVariants,
      tenantId: tenantId,
    );
    return FlushResult(
      deletedCount: deleted,
      resetCount: 0,
      operation: 'products',
    );
  }

  Future<FlushResult> _implFlushUsers(
    String keepAdminId, {
    String? tenantId,
  }) async {
    int deleted = 0;
    while (true) {
      Query<Map<String, dynamic>> query = _db
          .collection(Collections.users)
          .limit(400);
      if (tenantId != null) {
        query = query.where('tenant_id', isEqualTo: tenantId);
      }
      final snap = await query.get();
      final toDelete = snap.docs.where((d) => d.id != keepAdminId).toList();
      if (toDelete.isEmpty) break;
      final batch = _db.batch();
      for (final doc in toDelete) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      deleted += toDelete.length;
      if (snap.docs.length < 400) break;
    }
    return FlushResult(
      deletedCount: deleted,
      resetCount: 0,
      operation: 'users',
    );
  }

  /// Private impl for per-user flush.
  ///
  /// Deletes seller_inventory, invoices, transactions, and
  /// inventory_transactions for [userId]. Also resets [shop.balance] to 0
  /// for every shop that had transactions created by this user — since those
  /// balances are no longer backed by any transaction docs.
  Future<FlushResult> _implFlushPerUser(
    String userId, {
    String? tenantId,
  }) async {
    int deleted = 0;
    int reset = 0;

    // ── Step 1: Collect affected shop IDs BEFORE deleting transactions ──────
    // We need them to reset shop balances after deletion.
    final Set<String> affectedShopIds = {};
    DocumentSnapshot<Map<String, dynamic>>? lastDoc;
    bool hasMore = true;
    while (hasMore) {
      Query<Map<String, dynamic>> q = _db
          .collection(Collections.transactions)
          .where('created_by', isEqualTo: userId)
          .limit(400);
      if (tenantId != null) {
        q = q.where('tenant_id', isEqualTo: tenantId);
      }
      final snap = lastDoc != null
          ? await q.startAfterDocument(lastDoc).get()
          : await q.get();
      for (final d in snap.docs) {
        final sid = d.data()['shop_id'];
        if (sid is String && sid.isNotEmpty) affectedShopIds.add(sid);
      }
      hasMore = snap.docs.length == 400;
      if (snap.docs.isNotEmpty) lastDoc = snap.docs.last;
    }

    // ── Step 2: Delete all of this user's data ───────────────────────────────
    deleted += await _deleteWhere(
      Collections.sellerInventory,
      'seller_id',
      userId,
      tenantId: tenantId,
    );
    // Invoices created by this user (missing in original — bug fix)
    deleted += await _deleteWhere(
      Collections.invoices,
      'created_by',
      userId,
      tenantId: tenantId,
    );
    deleted += await _deleteWhere(
      Collections.transactions,
      'created_by',
      userId,
      tenantId: tenantId,
    );
    deleted += await _deleteWhere(
      Collections.inventoryTransactions,
      'created_by',
      userId,
      tenantId: tenantId,
    );

    // ── Step 3: Reset balance on affected shops ──────────────────────────────
    // Deleting the user's transactions leaves shops with stale balances.
    // Reset to 0 — the admin accepts this consequence of a partial data flush.
    final shopIdList = affectedShopIds.toList();
    for (var i = 0; i < shopIdList.length; i += 400) {
      final batch = _db.batch();
      final end = (i + 400 > shopIdList.length) ? shopIdList.length : i + 400;
      for (var j = i; j < end; j++) {
        batch.update(_db.collection(Collections.shops).doc(shopIdList[j]), {
          'balance': 0.0,
          'updated_at': Timestamp.now(),
        });
      }
      await batch.commit();
      reset += end - i;
    }

    return FlushResult(
      deletedCount: deleted,
      resetCount: reset,
      operation: 'per_user',
    );
  }

  Future<FlushResult> _implResetSettings({String? tenantId}) async {
    await _db
        .collection(Collections.settings)
        .doc(tenantId ?? TenantScope.globalTenantId)
        .set({
          'company_name': 'My Business',
          'currency': 'SAR',
          'pairs_per_carton': 12,
          'last_invoice_number': 0,
          'logo_base64': null,
          'logo_url': null,
          'require_admin_approval_for_seller_transaction_edits': false,
          'updated_at': Timestamp.now(),
        });
    return FlushResult(deletedCount: 0, resetCount: 1, operation: 'settings');
  }

  // ─── _stateGuard helper ────────────────────────────────────────────────────

  /// Runs [fn] under [AsyncValue.guard], writes state, and returns the result.
  /// Single pattern used by all public flush methods.
  Future<FlushResult> _stateGuard(Future<FlushResult> Function() fn) {
    return AsyncValue.guard(fn).then((v) {
      state = v;
      return v.when(
        data: (r) => r,
        loading: () => throw StateError('Unexpected loading state after guard'),
        error: Error.throwWithStackTrace,
      );
    });
  }

  // ─── Public API ────────────────────────────────────────────────────────────

  /// Flush financial data: invoices, transactions, inventory_transactions.
  /// Resets invoice counter and all shop balances.
  /// P0-1 FIX: Only super_admin can flush (not tenant_admin)
  Future<FlushResult> flushFinancialData({String? tenantId}) async {
    _requireSuperAdmin();
    state = const AsyncLoading();
    return _stateGuard(() => _implFlushFinancialData(tenantId: tenantId));
  }

  /// Flush inventory: seller_inventory docs + reset warehouse stock to 0.
  /// P0-1 FIX: Only super_admin can flush (not tenant_admin)
  Future<FlushResult> flushInventory({String? tenantId}) async {
    _requireSuperAdmin();
    state = const AsyncLoading();
    return _stateGuard(() => _implFlushInventory(tenantId: tenantId));
  }

  /// Flush shops: delete all shop/customer docs + reset route total_shops.
  /// P0-1 FIX: Only super_admin can flush (not tenant_admin)
  Future<FlushResult> flushShops({String? tenantId}) async {
    _requireSuperAdmin();
    state = const AsyncLoading();
    return _stateGuard(() => _implFlushShops(tenantId: tenantId));
  }

  /// Flush routes: delete all route docs + clear user assigned_route_id.
  /// P0-1 FIX: Only super_admin can flush (not tenant_admin)
  Future<FlushResult> flushRoutes({String? tenantId}) async {
    _requireSuperAdmin();
    state = const AsyncLoading();
    return _stateGuard(() => _implFlushRoutes(tenantId: tenantId));
  }

  /// Flush products: delete products + product_variants.
  /// P0-1 FIX: Only super_admin can flush (not tenant_admin)
  Future<FlushResult> flushProducts({String? tenantId}) async {
    _requireSuperAdmin();
    state = const AsyncLoading();
    return _stateGuard(() => _implFlushProducts(tenantId: tenantId));
  }

  /// Flush users: delete all user docs EXCEPT the specified admin.
  /// Does NOT delete Firebase Auth accounts (no Admin SDK available).
  /// P0-1 FIX: Only super_admin can flush users (not tenant_admin)
  Future<FlushResult> flushUsers(String keepAdminId, {String? tenantId}) async {
    _requireSuperAdmin();
    if (keepAdminId.isEmpty) {
      throw ArgumentError('keepAdminId must not be empty');
    }
    state = const AsyncLoading();
    return _stateGuard(() => _implFlushUsers(keepAdminId, tenantId: tenantId));
  }

  /// Flush a specific user's data: seller_inventory, invoices, transactions,
  /// and inventory_transactions (by created_by / seller_id).
  /// Also resets shop balances to 0 for all shops backed by this user's
  /// transactions — financial integrity after transaction deletion.
  /// P0-1 FIX: Only super_admin can flush users (not tenant_admin)
  Future<FlushResult> flushPerUser(String userId, {String? tenantId}) async {
    _requireSuperAdmin();
    if (userId.isEmpty) {
      throw ArgumentError('userId must not be empty');
    }
    state = const AsyncLoading();
    return _stateGuard(() => _implFlushPerUser(userId, tenantId: tenantId));
  }

  /// Reset settings to defaults (logo removed, counters zeroed).
  /// P0-1 FIX: Only super_admin can reset (not tenant_admin)
  Future<FlushResult> resetSettings({String? tenantId}) async {
    _requireSuperAdmin();
    state = const AsyncLoading();
    return _stateGuard(() => _implResetSettings(tenantId: tenantId));
  }

  /// Full database reset — orchestrates all flushes in dependency order.
  ///
  /// Calls private [_impl*] methods directly so that state is managed here
  /// exclusively — no flickering from sub-method state writes.
  /// P0-1 FIX: Only super_admin can flush all (not tenant_admin)
  Future<FlushResult> flushAll({
    required String keepAdminId,
    required bool includeUsers,
    String? tenantId,
  }) async {
    _requireSuperAdmin();
    state = const AsyncLoading();
    return _stateGuard(() async {
      int totalDeleted = 0;
      int totalReset = 0;

      // 1. Financial data first (depends on shops existing for balance reset)
      final fin = await _implFlushFinancialData(tenantId: tenantId);
      totalDeleted += fin.deletedCount;
      totalReset += fin.resetCount;

      // 2. Inventory
      final inv = await _implFlushInventory(tenantId: tenantId);
      totalDeleted += inv.deletedCount;
      totalReset += inv.resetCount;

      // 3. Shops (after financial — balances already reset)
      final shp = await _implFlushShops(tenantId: tenantId);
      totalDeleted += shp.deletedCount;
      totalReset += shp.resetCount;

      // 4. Routes (after shops — counter resets already done)
      final rte = await _implFlushRoutes(tenantId: tenantId);
      totalDeleted += rte.deletedCount;
      totalReset += rte.resetCount;

      // 5. Products
      final prd = await _implFlushProducts(tenantId: tenantId);
      totalDeleted += prd.deletedCount;
      totalReset += prd.resetCount;

      // 6. Settings
      final stg = await _implResetSettings(tenantId: tenantId);
      totalDeleted += stg.deletedCount;
      totalReset += stg.resetCount;

      // 7. Users (optional)
      if (includeUsers) {
        final usr = await _implFlushUsers(keepAdminId, tenantId: tenantId);
        totalDeleted += usr.deletedCount;
        totalReset += usr.resetCount;
      }

      return FlushResult(
        deletedCount: totalDeleted,
        resetCount: totalReset,
        operation: 'full_reset',
      );
    });
  }
}

final databaseFlushProvider =
    AsyncNotifierProvider<DatabaseFlushNotifier, void>(
      DatabaseFlushNotifier.new,
    );
