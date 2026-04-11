import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
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

  /// Verifies the current user is admin before allowing flush operations.
  UserModel _requireAdmin() {
    final user = ref.read(authUserProvider).valueOrNull;
    if (user == null || !user.isAdmin) {
      throw ArgumentError('Only admin can perform database flush operations');
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
  /// Returns the number of deleted documents.
  Future<int> _deleteCollection(String collectionPath) async {
    int deleted = 0;
    while (true) {
      final snap =
          await _db.collection(collectionPath).limit(400).get();
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
  Future<int> _deleteWhere(
    String collectionPath,
    String field,
    String value,
  ) async {
    int deleted = 0;
    while (true) {
      final snap = await _db
          .collection(collectionPath)
          .where(field, isEqualTo: value)
          .limit(400)
          .get();
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

  /// Flush financial data: invoices, transactions, inventory_transactions.
  /// Resets invoice counter and all shop balances.
  Future<FlushResult> flushFinancialData() async {
    _requireAdmin();
    state = const AsyncLoading();
    return AsyncValue.guard(() async {
      int deleted = 0;
      int reset = 0;

      // Delete invoices
      deleted += await _deleteCollection(Collections.invoices);
      // Delete transactions
      deleted += await _deleteCollection(Collections.transactions);
      // Delete inventory transactions
      deleted += await _deleteCollection(Collections.inventoryTransactions);

      // Reset invoice counter
      await _db.collection(Collections.settings).doc('global').set(
        {'last_invoice_number': 0, 'updated_at': Timestamp.now()},
        SetOptions(merge: true),
      );
      reset++;

      // Reset all shop balances
      final shops = await _db.collection(Collections.shops).get();
      for (var i = 0; i < shops.docs.length; i += 400) {
        final batch = _db.batch();
        final end =
            (i + 400 > shops.docs.length) ? shops.docs.length : i + 400;
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
    }).then((v) {
      state = v;
      return v.value!;
    });
  }

  /// Flush inventory: seller_inventory docs + reset warehouse stock to 0.
  Future<FlushResult> flushInventory() async {
    _requireAdmin();
    state = const AsyncLoading();
    return AsyncValue.guard(() async {
      int deleted = 0;
      int reset = 0;

      // Delete all seller inventory
      deleted += await _deleteCollection(Collections.sellerInventory);

      // Reset warehouse stock (product_variants.quantity_available → 0)
      final variants = await _db
          .collection(Collections.productVariants)
          .get();
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
    }).then((v) {
      state = v;
      return v.value!;
    });
  }

  /// Flush shops: delete all shop/customer docs + reset route total_shops.
  Future<FlushResult> flushShops() async {
    _requireAdmin();
    state = const AsyncLoading();
    return AsyncValue.guard(() async {
      int deleted = 0;
      int reset = 0;

      deleted += await _deleteCollection(Collections.shops);

      // Reset route total_shops counters
      final routes = await _db.collection(Collections.routes).get();
      for (var i = 0; i < routes.docs.length; i += 400) {
        final batch = _db.batch();
        final end = (i + 400 > routes.docs.length)
            ? routes.docs.length
            : i + 400;
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
    }).then((v) {
      state = v;
      return v.value!;
    });
  }

  /// Flush routes: delete all route docs + clear user assigned_route_id.
  Future<FlushResult> flushRoutes() async {
    _requireAdmin();
    state = const AsyncLoading();
    return AsyncValue.guard(() async {
      int deleted = 0;
      int reset = 0;

      deleted += await _deleteCollection(Collections.routes);

      // Clear assigned_route_id on all users
      final users = await _db.collection(Collections.users).get();
      for (var i = 0; i < users.docs.length; i += 400) {
        final batch = _db.batch();
        final end =
            (i + 400 > users.docs.length) ? users.docs.length : i + 400;
        for (var j = i; j < end; j++) {
          batch.update(users.docs[j].reference, {
            'assigned_route_id': null,
            'assigned_route_name': null,
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
    }).then((v) {
      state = v;
      return v.value!;
    });
  }

  /// Flush products: delete products + product_variants.
  Future<FlushResult> flushProducts() async {
    _requireAdmin();
    state = const AsyncLoading();
    return AsyncValue.guard(() async {
      int deleted = 0;
      deleted += await _deleteCollection(Collections.products);
      deleted += await _deleteCollection(Collections.productVariants);

      return FlushResult(
        deletedCount: deleted,
        resetCount: 0,
        operation: 'products',
      );
    }).then((v) {
      state = v;
      return v.value!;
    });
  }

  /// Flush users: delete all user docs EXCEPT the specified admin.
  /// Does NOT delete Firebase Auth accounts (no Admin SDK available).
  Future<FlushResult> flushUsers(String keepAdminId) async {
    _requireAdmin();
    if (keepAdminId.isEmpty) {
      throw ArgumentError('keepAdminId must not be empty');
    }
    state = const AsyncLoading();
    return AsyncValue.guard(() async {
      int deleted = 0;
      while (true) {
        final snap = await _db
            .collection(Collections.users)
            .limit(400)
            .get();
        final toDelete =
            snap.docs.where((d) => d.id != keepAdminId).toList();
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
    }).then((v) {
      state = v;
      return v.value!;
    });
  }

  /// Flush a specific user's data: their seller_inventory, transactions,
  /// and inventory_transactions (by created_by / seller_id).
  Future<FlushResult> flushPerUser(String userId) async {
    _requireAdmin();
    if (userId.isEmpty) {
      throw ArgumentError('userId must not be empty');
    }
    state = const AsyncLoading();
    return AsyncValue.guard(() async {
      int deleted = 0;

      // Delete user's seller inventory
      deleted += await _deleteWhere(
        Collections.sellerInventory,
        'seller_id',
        userId,
      );

      // Delete user's transactions
      deleted += await _deleteWhere(
        Collections.transactions,
        'created_by',
        userId,
      );

      // Delete user's inventory transactions
      deleted += await _deleteWhere(
        Collections.inventoryTransactions,
        'created_by',
        userId,
      );

      return FlushResult(
        deletedCount: deleted,
        resetCount: 0,
        operation: 'per_user',
      );
    }).then((v) {
      state = v;
      return v.value!;
    });
  }

  /// Reset settings to defaults (logo removed, counters zeroed).
  Future<FlushResult> resetSettings() async {
    _requireAdmin();
    state = const AsyncLoading();
    return AsyncValue.guard(() async {
      await _db.collection(Collections.settings).doc('global').set({
        'company_name': 'My Business',
        'currency': 'SAR',
        'pairs_per_carton': 12,
        'last_invoice_number': 0,
        'logo_base64': null,
        'logo_url': null,
        'require_admin_approval_for_seller_transaction_edits': false,
        'updated_at': Timestamp.now(),
      });
      return FlushResult(
        deletedCount: 0,
        resetCount: 1,
        operation: 'settings',
      );
    }).then((v) {
      state = v;
      return v.value!;
    });
  }

  /// Full database reset — orchestrates all flushes in dependency order.
  Future<FlushResult> flushAll({
    required String keepAdminId,
    required bool includeUsers,
  }) async {
    _requireAdmin();
    state = const AsyncLoading();
    return AsyncValue.guard(() async {
      int totalDeleted = 0;
      int totalReset = 0;

      // 1. Financial data first (depends on shops existing for balance reset)
      final fin = await flushFinancialData();
      totalDeleted += fin.deletedCount;
      totalReset += fin.resetCount;

      // 2. Inventory
      final inv = await flushInventory();
      totalDeleted += inv.deletedCount;
      totalReset += inv.resetCount;

      // 3. Shops (after financial — balance resets already done)
      final shp = await flushShops();
      totalDeleted += shp.deletedCount;
      totalReset += shp.resetCount;

      // 4. Routes (after shops — counter resets already done)
      final rte = await flushRoutes();
      totalDeleted += rte.deletedCount;
      totalReset += rte.resetCount;

      // 5. Products
      final prd = await flushProducts();
      totalDeleted += prd.deletedCount;
      totalReset += prd.resetCount;

      // 6. Settings
      final stg = await resetSettings();
      totalDeleted += stg.deletedCount;
      totalReset += stg.resetCount;

      // 7. Users (optional)
      if (includeUsers) {
        final usr = await flushUsers(keepAdminId);
        totalDeleted += usr.deletedCount;
        totalReset += usr.resetCount;
      }

      return FlushResult(
        deletedCount: totalDeleted,
        resetCount: totalReset,
        operation: 'full_reset',
      );
    }).then((v) {
      state = v;
      return v.value!;
    });
  }
}

final databaseFlushProvider =
    AsyncNotifierProvider<DatabaseFlushNotifier, void>(
  DatabaseFlushNotifier.new,
);
