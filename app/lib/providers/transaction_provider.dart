import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../core/utils/tenant_scope.dart';
import '../models/transaction_model.dart';
import 'auth_provider.dart';

const _kExportQueryLimit = 2000;

// =============================================================================
// TransactionProvider — all shop ledger writes go through this notifier.
//
// ARCHITECTURE:
//   Shops are stored in the 'customers' Firestore collection (legacy name).
//   All balance updates reference Collections.customers / Collections.shops.
//
// TWO FINANCIAL PATHWAYS:
//   1. SALE WITH STOCK → InvoiceNotifier.createSaleInvoice() (in invoice_provider.dart)
//      - Atomically creates invoice + cash_out tx + optional cash_in tx + stock deduction
//      - cash_out tx has invoice_id field linking it back to the invoice
//   2. CASH COLLECTION (debt only, no new sale) → TransactionNotifier.create()
//      - type: 'cash_in', no items, no invoice created
//      - Reduces shop.balance atomically
//      - Called from ShopDetailScreen quick-cash panel
//
// BALANCE DELTA CONVENTION:
//   cash_out  → balance += amount  (shop owes more)
//   cash_in   → balance -= amount  (shop owes less)
//   return    → balance -= amount  (goods returned, owes less)
//   write_off → balance zeroed by ShopNotifier.markAsBadDebt() directly
//
// SOFT DELETE (DI-01): never hard-delete transactions; set deleted=true + reverse balance.
// =============================================================================

const _shopTransactionsLiveLimit = 150;
const _shopsAnalyticsTransactionsLimit = 500;

List<TransactionModel> sortTransactionsForExport(
  List<TransactionModel> transactions,
) {
  final sorted = List<TransactionModel>.from(transactions);
  sorted.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return sorted;
}

final shopTransactionsProvider = StreamProvider.autoDispose
    .family<List<TransactionModel>, String>((ref, shopId) {
      final normalizedShopId = shopId.trim();
      if (normalizedShopId.isEmpty) {
        return Stream.value(const <TransactionModel>[]);
      }
      final tenantId = ref.watch(
        authUserProvider.select(
          (s) => TenantScope.normalize(s.value?.tenantId),
        ),
      );
      final query = TenantScope.applyToQuery(
        FirebaseFirestore.instance.collection(Collections.transactions),
        tenantId: tenantId,
      );
      return query
          .where('shop_id', isEqualTo: normalizedShopId)
          .orderBy('created_at', descending: true)
          .limit(_shopTransactionsLiveLimit)
          .snapshots()
          .handleError((Object error, StackTrace stack) {
            if (error is FirebaseException &&
                error.code == 'failed-precondition') {
              return const <TransactionModel>[];
            }
            throw error;
          })
          .map(
            (snap) => snap.docs
                .where((d) => d.data()['deleted'] != true)
                .map((d) => TransactionModel.fromJson(d.data(), d.id))
                .toList(),
          );
    });

final shopTransactionsFallbackProvider = StreamProvider.autoDispose
    .family<List<TransactionModel>, String>((ref, shopId) {
      final normalizedShopId = shopId.trim();
      if (normalizedShopId.isEmpty) {
        return Stream.value(const <TransactionModel>[]);
      }

      final tenantId = ref.watch(
        authUserProvider.select(
          (s) => TenantScope.normalize(s.value?.tenantId),
        ),
      );
      final base = TenantScope.applyToQuery(
        FirebaseFirestore.instance.collection(Collections.transactions),
        tenantId: tenantId,
      );

      return base
          .where('shop_id', isEqualTo: normalizedShopId)
          .limit(_shopTransactionsLiveLimit)
          .snapshots()
          .handleError((Object error, StackTrace stack) {
            if (error is FirebaseException &&
                error.code == 'failed-precondition') {
              return const <TransactionModel>[];
            }
            throw error;
          })
          .map(
            (snap) =>
                snap.docs
                    .where((d) => d.data()['deleted'] != true)
                    .map((d) => TransactionModel.fromJson(d.data(), d.id))
                    .toList()
                  ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
          );
    });

final allTransactionsProvider =
    StreamProvider.autoDispose<List<TransactionModel>>((ref) {
      // Admin-only unfiltered query: guard to prevent PERMISSION_DENIED.
      // Use select() so heartbeat writes to last_active do NOT restart the stream.
      final isAdmin = ref.watch(
        authUserProvider.select((s) => s.value?.isAdmin ?? false),
      );
      final tenantId = ref.watch(
        authUserProvider.select(
          (s) => TenantScope.normalize(s.value?.tenantId),
        ),
      );
      if (!isAdmin) return const Stream.empty();
      final query = TenantScope.applyToQuery(
        FirebaseFirestore.instance.collection(Collections.transactions),
        tenantId: tenantId,
      );
      return query
          .orderBy('created_at', descending: true)
          .limit(200)
          .snapshots()
          .handleError((Object error, StackTrace stack) {
            if (error is FirebaseException &&
                error.code == 'failed-precondition') {
              return const <TransactionModel>[];
            }
            throw error;
          })
          .map(
            (snap) => snap.docs
                .where((d) => d.data()['deleted'] != true)
                .map((d) => TransactionModel.fromJson(d.data(), d.id))
                .toList(),
          );
    });

/// Shop analytics need actual ledger flow, not just current balances.
/// Admins see all transactions; sellers see all transactions on their route.
final shopsAnalyticsTransactionsProvider =
    StreamProvider.autoDispose<List<TransactionModel>>((ref) {
      ref.keepAlive();
      // Use select() with a string key (not List<String>) so Riverpod's ==
      // check correctly identifies no-change on heartbeat writes to last_active.
      // List<String> uses reference equality — a new UserModel snapshot always
      // produces a new List object, which would look like "changed" and restart
      // this Firestore stream every 5 minutes, causing analytics strip flicker.
      final (isAdmin, isSeller, routeKey) = ref.watch(
        authUserProvider.select((s) {
          final u = s.value;
          if (u == null) return (false, false, '');
          if (u.isAdmin) return (true, false, '');
          if (!u.isSeller || u.assignedRouteIds.isEmpty) {
            return (false, false, '');
          }
          final sorted = List<String>.from(u.assignedRouteIds)..sort();
          return (false, true, sorted.join(','));
        }),
      );
      if (!isAdmin && (!isSeller || routeKey.isEmpty)) {
        return Stream.value(const <TransactionModel>[]);
      }

      final tenantId = ref.watch(
        authUserProvider.select(
          (s) => TenantScope.normalize(s.value?.tenantId),
        ),
      );
      final collection = TenantScope.applyToQuery(
        FirebaseFirestore.instance.collection(Collections.transactions),
        tenantId: tenantId,
      );

      if (isAdmin) {
        return collection
            .orderBy('created_at', descending: true)
            .limit(_shopsAnalyticsTransactionsLimit)
            .snapshots()
            .handleError((Object error, StackTrace stack) {
              if (error is FirebaseException &&
                  error.code == 'failed-precondition') {
                return const <TransactionModel>[];
              }
              throw error;
            })
            .map(
              (snap) => snap.docs
                  .where((d) => d.data()['deleted'] != true)
                  .map((d) => TransactionModel.fromJson(d.data(), d.id))
                  .toList(),
            );
      }

      final routeIds = routeKey.split(',');
      return collection
          .where('route_id', whereIn: routeIds)
          .orderBy('created_at', descending: true)
          .limit(_shopsAnalyticsTransactionsLimit)
          .snapshots()
          .handleError((Object error, StackTrace stack) {
            if (error is FirebaseException &&
                error.code == 'failed-precondition') {
              return const <TransactionModel>[];
            }
            throw error;
          })
          .map(
            (snap) => snap.docs
                .where((d) => d.data()['deleted'] != true)
                .map((d) => TransactionModel.fromJson(d.data(), d.id))
                .toList(),
          );
    });

final pendingEditRequestsProvider =
    StreamProvider.autoDispose<List<TransactionModel>>((ref) {
      // Use select() so heartbeat writes to last_active do NOT restart the stream.
      final isAdmin = ref.watch(
        authUserProvider.select((s) => s.value?.isAdmin ?? false),
      );
      if (!isAdmin) {
        return Stream.value(const <TransactionModel>[]);
      }
      final tenantId = ref.watch(
        authUserProvider.select(
          (s) => TenantScope.normalize(s.value?.tenantId),
        ),
      );
      final query = TenantScope.applyToQuery(
        FirebaseFirestore.instance.collection(Collections.transactions),
        tenantId: tenantId,
      );
      return query
          .where('edit_request_pending', isEqualTo: true)
          .orderBy('created_at', descending: true)
          .limit(50)
          .snapshots()
          .handleError((Object error, StackTrace stack) {
            if (error is FirebaseException &&
                error.code == 'failed-precondition') {
              return const <TransactionModel>[];
            }
            throw error;
          })
          .map(
            (snap) => snap.docs
                .where((d) => d.data()['deleted'] != true)
                .map((d) => TransactionModel.fromJson(d.data(), d.id))
                .toList(),
          );
    });

/// Seller-scoped: transactions created by this seller.
final sellerTransactionsProvider = StreamProvider.autoDispose
    .family<List<TransactionModel>, String>((ref, sellerId) {
      final tenantId = ref.watch(
        authUserProvider.select(
          (s) => TenantScope.normalize(s.value?.tenantId),
        ),
      );
      final query = TenantScope.applyToQuery(
        FirebaseFirestore.instance.collection(Collections.transactions),
        tenantId: tenantId,
      );
      return query
          .where('created_by', isEqualTo: sellerId)
          .orderBy('created_at', descending: true)
          .limit(200)
          .snapshots()
          .handleError((Object error, StackTrace stack) {
            if (error is FirebaseException &&
                error.code == 'failed-precondition') {
              return const <TransactionModel>[];
            }
            throw error;
          })
          .map(
            (snap) => snap.docs
                .where((d) => d.data()['deleted'] != true)
                .map((d) => TransactionModel.fromJson(d.data(), d.id))
                .toList(),
          );
    });

/// One-shot shop transactions for export (PDF/Excel). NOT autoDispose:
/// callers use ref.read(provider.future) which doesn't subscribe, so
/// autoDispose would destroy the provider mid-Firestore-query → StateError.
/// Callers must ref.invalidate() before reading for fresh data.
final shopTransactionsExportProvider =
    FutureProvider.family<List<TransactionModel>, String>((ref, shopId) async {
      final normalizedShopId = shopId.trim();
      if (normalizedShopId.isEmpty) return const <TransactionModel>[];

      final tenantId = await ref
          .read(authUserProvider.future)
          .then((user) => TenantScope.normalize(user?.tenantId));
      final query = TenantScope.applyToQuery(
        FirebaseFirestore.instance.collection(Collections.transactions),
        tenantId: tenantId,
      );
      final snap = await query
          .where('shop_id', isEqualTo: normalizedShopId)
          .orderBy('created_at', descending: true)
          .limit(_kExportQueryLimit)
          .get();

      final txs = snap.docs
          .where((d) => d.data()['deleted'] != true)
          .map((d) => TransactionModel.fromJson(d.data(), d.id))
          .toList();

      return sortTransactionsForExport(txs);
    });

/// All transactions for a specific route — used by multi-shop PDF export.
/// NOT autoDispose: callers use ref.read(provider.future) which doesn't
/// subscribe — autoDispose would destroy the provider mid-query → StateError.
/// Callers must ref.invalidate() before reading for fresh data.
final routeTransactionsExportProvider =
    FutureProvider.family<List<TransactionModel>, String>((ref, routeId) async {
      final normalizedId = routeId.trim();
      if (normalizedId.isEmpty) return const <TransactionModel>[];
      // Use .future to await first auth emission instead of reading a
      // potentially-null .value while the StreamProvider is still loading.
      final user = await ref.read(authUserProvider.future);
      if (user == null) return const <TransactionModel>[];
      if (!user.isAdmin) {
        if (!user.isSeller || !user.assignedRouteIds.contains(normalizedId)) {
          return const <TransactionModel>[];
        }
      }
      final tenantId = TenantScope.normalize(user.tenantId);
      final query = TenantScope.applyToQuery(
        FirebaseFirestore.instance.collection(Collections.transactions),
        tenantId: tenantId,
      );
      final snap = await query
          .where('route_id', isEqualTo: normalizedId)
          .orderBy('created_at', descending: true)
          .limit(_kExportQueryLimit)
          .get();
      final txs = snap.docs
          .where((d) => d.data()['deleted'] != true)
          .map((d) => TransactionModel.fromJson(d.data(), d.id))
          .toList();
      return sortTransactionsForExport(txs);
    });

/// All transactions across all routes — admin-only bulk export.
/// NOT autoDispose: see routeTransactionsExportProvider comment.
final allTransactionsExportProvider = FutureProvider<List<TransactionModel>>((
  ref,
) async {
  // Use .future to await first auth emission instead of reading a
  // potentially-null .value while the StreamProvider is still loading.
  final user = await ref.read(authUserProvider.future);
  if (user == null || !user.isAdmin) return const <TransactionModel>[];
  final tenantId = TenantScope.normalize(user.tenantId);
  final query = TenantScope.applyToQuery(
    FirebaseFirestore.instance.collection(Collections.transactions),
    tenantId: tenantId,
  );
  final snap = await query
      .orderBy('created_at', descending: true)
      .limit(_kExportQueryLimit)
      .get();
  final txs = snap.docs
      .where((d) => d.data()['deleted'] != true)
      .map((d) => TransactionModel.fromJson(d.data(), d.id))
      .toList();
  return sortTransactionsForExport(txs);
});

/// One-shot transactions for a specific seller — used by seller report PDF.
/// NOT autoDispose: callers use ref.read(provider.future) which doesn't
/// subscribe — autoDispose would destroy the provider mid-query → StateError.
/// Callers must ref.invalidate() before reading to ensure fresh data.
final sellerTransactionsExportProvider =
    FutureProvider.family<List<TransactionModel>, String>((
      ref,
      sellerId,
    ) async {
      final normalizedId = sellerId.trim();
      if (normalizedId.isEmpty) return const <TransactionModel>[];
      final user = await ref.read(authUserProvider.future);
      if (user == null || !user.isAdmin) return const <TransactionModel>[];
      final tenantId = TenantScope.normalize(user.tenantId);
      final query = TenantScope.applyToQuery(
        FirebaseFirestore.instance.collection(Collections.transactions),
        tenantId: tenantId,
      );
      final snap = await query
          .where('created_by', isEqualTo: normalizedId)
          .orderBy('created_at', descending: true)
          .limit(_kExportQueryLimit)
          .get();
      final txs = snap.docs
          .where((d) => d.data()['deleted'] != true)
          .map((d) => TransactionModel.fromJson(d.data(), d.id))
          .toList();
      return sortTransactionsForExport(txs);
    });

class TransactionNotifier extends AsyncNotifier<void> {
  bool _writeInFlight = false;

  Future<void> _commit(WriteBatch batch) {
    return batch.commit().timeout(const Duration(seconds: 20));
  }

  Future<String> _currentTenantId() async {
    final user = await ref.read(authUserProvider.future);
    return TenantScope.normalize(user?.tenantId) ?? TenantScope.globalTenantId;
  }

  @override
  Future<void> build() async {}

  Future<void> _runWriteGuard(Future<void> Function() op) async {
    if (_writeInFlight) {
      return;
    }
    _writeInFlight = true;
    try {
      await op();
    } finally {
      _writeInFlight = false;
    }
  }

  void _stageTransactionUpdate({
    required WriteBatch batch,
    required FirebaseFirestore db,
    required String txId,
    required String? shopId,
    required double oldAmount,
    required String oldType,
    required double newAmount,
    required String newType,
    String? description,
    String? saleType,
    Timestamp? transactionDate,
    Map<String, dynamic> extraTxFields = const <String, dynamic>{},
  }) {
    final updatePayload = <String, dynamic>{
      'amount': newAmount,
      'type': newType,
      ...extraTxFields,
      'updated_at': Timestamp.now(),
    };
    if (description != null) updatePayload['description'] = description;
    if (saleType != null) updatePayload['sale_type'] = saleType;
    if (transactionDate != null) updatePayload['created_at'] = transactionDate;

    batch.update(
      db.collection(Collections.transactions).doc(txId),
      updatePayload,
    );

    if (shopId != null && shopId.isNotEmpty) {
      // Treat return/payment/write_off as balance-reducing amounts by default.
      final oldDelta = oldType == 'cash_out' ? oldAmount : -oldAmount;
      final newDelta = newType == 'cash_out' ? newAmount : -newAmount;
      final netChange = -oldDelta + newDelta;
      if (netChange != 0) {
        batch.update(db.collection(Collections.customers).doc(shopId), {
          'balance': FieldValue.increment(netChange),
          'updated_at': Timestamp.now(),
          'last_transaction_at': Timestamp.now(),
          'last_transaction_type': newType,
          'last_transaction_amount': newAmount,
        });
      }
    }
  }

  /// Creates a transaction and updates shop balance atomically.
  /// For cash_out with items, also deducts stock from variants.
  Future<void> create({
    required String shopId,
    required String shopName,
    required String routeId,
    required String type,
    required double amount,
    String? description,
    String? saleType,
    List<TransactionItem> items = const [],
    required String createdBy,
    Timestamp? transactionDate,
    String? idempotencyKey,
  }) async {
    await _runWriteGuard(() async {
      final normalizedCreatedBy = createdBy.trim();
      if (normalizedCreatedBy.isEmpty) {
        throw ArgumentError('createdBy must not be empty');
      }
      // Validate type is in allowed set to prevent arbitrary transaction types
      const allowedTypes = {
        'cash_out',
        'cash_in',
        'return',
        'payment',
        'write_off',
      };
      if (!allowedTypes.contains(type)) {
        throw ArgumentError(
          'Invalid transaction type "$type". Allowed: ${allowedTypes.join(', ')}',
        );
      }
      if (amount <= 0) {
        throw ArgumentError('Transaction amount must be greater than 0');
      }
      if (shopId.trim().isEmpty) {
        throw ArgumentError('shopId must not be empty');
      }
      if (routeId.trim().isEmpty) {
        throw ArgumentError('routeId must not be empty');
      }

      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      final tenantId = await _currentTenantId();
      final normalizedKey = idempotencyKey?.trim();
      if (normalizedKey != null && normalizedKey.isNotEmpty) {
        final existing = await db
            .collection(Collections.transactions)
            .where('idempotency_key', isEqualTo: normalizedKey)
            .limit(1)
            .get();
        if (existing.docs.isNotEmpty) {
          return;
        }
      }

      // Create transaction doc
      final txRef = db.collection(Collections.transactions).doc();
      batch.set(txRef, {
        'shop_id': shopId,
        'shop_name': shopName,
        'route_id': routeId,
        'tenant_id': tenantId,
        'type': type,
        'sale_type': saleType,
        'amount': amount,
        'description': description,
        'items': items.map((e) => e.toJson()).toList(),
        'created_by': normalizedCreatedBy,
        'created_at': transactionDate ?? Timestamp.now(),
        'deleted':
            false, // DI-01: required for isNotEqualTo filter in allTransactionsProvider
        if (normalizedKey != null && normalizedKey.isNotEmpty)
          'idempotency_key': normalizedKey,
      });

      // Update shop balance: cash_out adds, cash_in subtracts
      if (shopId.isNotEmpty) {
        final balanceDelta = type == 'cash_out' ? amount : -amount;
        batch.update(db.collection(Collections.customers).doc(shopId), {
          'balance': FieldValue.increment(balanceDelta),
          'updated_at': Timestamp.now(),
          'last_transaction_at': transactionDate ?? Timestamp.now(),
          'last_transaction_type': type,
          'last_transaction_amount': amount,
        });
      }

      // If cash_out with items, deduct stock from product_variants
      if (type == 'cash_out' && items.isNotEmpty) {
        for (final item in items) {
          batch.update(
            db.collection(Collections.productVariants).doc(item.variantId),
            {'quantity_available': FieldValue.increment(-item.qty)},
          );
        }
      }

      await _commit(batch);

      // Best-effort notification for admin feed (non-critical, fire-and-forget).
      // Only written when a seller creates the transaction — admin notifies themselves.
      // P1-10 FIX: Include tenant_id to prevent cross-tenant leakage.
      try {
        final appUser = ref.read(authUserProvider).value;
        if (appUser != null && appUser.isSeller) {
          await FirebaseFirestore.instance
              .collection(Collections.notifications)
              .doc()
              .set({
                'type': 'transaction',
                'shop_id': shopId,
                'shop_name': shopName,
                'route_id': routeId,
                'seller_id': normalizedCreatedBy,
                'seller_name': appUser.displayName,
                'amount': amount,
                'transaction_type': type,
                'ref_id': txRef.id,
                'target_role': 'admin',
                'read': false,
                'created_by': normalizedCreatedBy,
                'tenant_id': appUser.tenantId,
                'created_at': Timestamp.now(),
              });
        }
      } catch (_) {
        /* best-effort only — non-critical */
      }
    });
  }

  /// Restores seller-owned cash ledger entries for one currently assigned
  /// route. Existing transaction IDs are left untouched, and each imported
  /// entry updates the shop balance in the same Firestore transaction.
  Future<int> restoreSellerRouteTransactions({
    required String routeId,
    required List<Map<String, dynamic>> documents,
  }) async {
    final user = await ref.read(authUserProvider.future);
    if (user == null || !user.active || !user.isSeller) {
      throw StateError('Seller privileges required for route restore');
    }
    final normalizedRouteId = routeId.trim();
    if (normalizedRouteId.isEmpty ||
        !user.assignedRouteIds.contains(normalizedRouteId)) {
      throw StateError('Route access has been revoked');
    }
    final tenantId =
        TenantScope.normalize(user.tenantId) ?? TenantScope.globalTenantId;
    var restored = 0;

    await _runWriteGuard(() async {
      final db = FirebaseFirestore.instance;
      for (final raw in documents) {
        final txId = (raw['__id'] as String?)?.trim() ?? '';
        final rawRouteId = (raw['route_id'] as String?)?.trim() ?? '';
        final createdBy = (raw['created_by'] as String?)?.trim() ?? '';
        final shopId = (raw['shop_id'] as String?)?.trim() ?? '';
        final type = (raw['type'] as String?)?.trim() ?? '';
        final amount = (raw['amount'] as num?)?.toDouble() ?? 0;
        if (txId.isEmpty ||
            rawRouteId != normalizedRouteId ||
            createdBy != user.id ||
            shopId.isEmpty ||
            (type != TransactionModel.typeCashIn &&
                type != TransactionModel.typeCashOut) ||
            amount <= 0 ||
            !TenantScope.matchesTenant(raw, tenantId)) {
          continue;
        }

        final txRef = db.collection(Collections.transactions).doc(txId);
        final shopRef = db.collection(Collections.customers).doc(shopId);
        final imported = await db.runTransaction<bool>((transaction) async {
          final existing = await transaction.get(txRef);
          if (existing.exists) return false;
          final shop = await transaction.get(shopRef);
          final shopData = shop.data();
          if (!shop.exists ||
              shopData == null ||
              !TenantScope.matchesTenant(shopData, tenantId) ||
              shopData['route_id'] != normalizedRouteId) {
            return false;
          }
          final model = TransactionModel.fromJson(raw, txId);
          transaction.set(txRef, {
            ...model.toJson(),
            'tenant_id': tenantId,
            'deleted': false,
          });
          transaction.update(shopRef, {
            'balance': FieldValue.increment(model.balanceImpact),
            'updated_at': Timestamp.now(),
            'last_transaction_at': model.createdAt,
            'last_transaction_type': model.type,
            'last_transaction_amount': model.amount,
          });
          return true;
        });
        if (imported) restored++;
      }
    });
    return restored;
  }

  /// Creates a seller-side sale transaction WITHOUT going through invoicing.
  /// NOTE: Prefer InvoiceNotifier.createSaleInvoice() for all new sales that
  /// involve stock deduction from seller_inventory.
  Future<void> createSellerSale({
    required String routeId,
    required String shopId,
    required String shopName,
    required double amount,
    String? description,
    String? saleType,
    required List<TransactionItem> items,
    required Map<String, int> sellerInventoryDeductions,
    required String createdBy,
    String? idempotencyKey,
    Timestamp? transactionDate,
  }) async {
    await _runWriteGuard(() async {
      final normalizedCreatedBy = createdBy.trim();
      if (normalizedCreatedBy.isEmpty) {
        throw ArgumentError('createdBy must not be empty');
      }
      if (shopId.trim().isEmpty) {
        throw ArgumentError('shopId must not be empty');
      }
      if (amount <= 0) {
        throw ArgumentError('Transaction amount must be greater than 0');
      }

      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      final tenantId = await _currentTenantId();

      final normalizedKey = idempotencyKey?.trim();
      if (normalizedKey != null && normalizedKey.isNotEmpty) {
        final existing = await db
            .collection(Collections.transactions)
            .where('idempotency_key', isEqualTo: normalizedKey)
            .limit(1)
            .get();
        if (existing.docs.isNotEmpty) {
          return;
        }
      }

      final txRef = db.collection(Collections.transactions).doc();
      batch.set(txRef, {
        'shop_id': shopId,
        'shop_name': shopName,
        'route_id': routeId,
        'tenant_id': tenantId,
        'type': 'cash_out',
        'sale_type': saleType ?? 'cash',
        'amount': amount,
        'description': description,
        'items': items.map((e) => e.toJson()).toList(),
        'created_by': normalizedCreatedBy,
        'created_at': transactionDate ?? Timestamp.now(),
        'deleted': false, // DI-01: required for isNotEqualTo filter
        if (normalizedKey != null && normalizedKey.isNotEmpty)
          'idempotency_key': normalizedKey,
      });

      // Shop owes more
      batch.update(db.collection(Collections.customers).doc(shopId), {
        'balance': FieldValue.increment(amount),
        'updated_at': Timestamp.now(),
        'last_transaction_at': transactionDate ?? Timestamp.now(),
        'last_transaction_type': 'cash_out',
        'last_transaction_amount': amount,
      });

      // Deduct from seller_inventory docs
      for (final entry in sellerInventoryDeductions.entries) {
        if (entry.value > 0) {
          batch.update(
            db.collection(Collections.sellerInventory).doc(entry.key),
            {
              'quantity_available': FieldValue.increment(-entry.value),
              'updated_at': Timestamp.now(),
            },
          );
        }
      }

      await _commit(batch);

      // Best-effort notification for admin feed (non-critical, fire-and-forget).
      // P1-10 FIX: Include tenant_id to prevent cross-tenant leakage.
      try {
        final appUser = ref.read(authUserProvider).value;
        if (appUser != null && appUser.isSeller) {
          await FirebaseFirestore.instance
              .collection(Collections.notifications)
              .doc()
              .set({
                'type': 'transaction',
                'shop_id': shopId,
                'shop_name': shopName,
                'route_id': routeId,
                'seller_id': normalizedCreatedBy,
                'seller_name': appUser.displayName,
                'amount': amount,
                'transaction_type': 'cash_out',
                'ref_id': txRef.id,
                'target_role': 'admin',
                'read': false,
                'created_by': normalizedCreatedBy,
                'tenant_id': appUser.tenantId,
                'created_at': Timestamp.now(),
              });
        }
      } catch (_) {
        /* best-effort only — non-critical */
      }
    });
  }

  /// Seller-safe annotation: updates only the [description] field.
  /// Firestore rules restrict seller updates to ['description', 'updated_at'].
  /// Admins should use [updateTransaction] for financial field changes.
  Future<void> updateTransactionNote({
    required String txId,
    required String? description,
    String updatedBy = '',
  }) async {
    if (txId.trim().isEmpty) {
      throw ArgumentError('txId must not be empty');
    }
    await FirebaseFirestore.instance
        .collection(Collections.transactions)
        .doc(txId)
        .update({
          if (description != null && description.isNotEmpty)
            'description': description.trim()
          else
            'description': FieldValue.delete(),
          if (updatedBy.trim().isNotEmpty) 'updated_by': updatedBy.trim(),
          'updated_at': Timestamp.now(),
        });
  }

  /// Soft-deletes a transaction (sets deleted=true) and reverses its balance
  /// impact on the customer. Preserves audit trail.
  Future<void> deleteTransaction({
    required String txId,
    required String? shopId,
    required double amount,
    required String type,
    required String deletedBy,
  }) async {
    if (txId.trim().isEmpty) {
      throw ArgumentError('txId must not be empty');
    }

    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    final now = Timestamp.now();

    // Soft-delete: preserve audit trail, never hard-delete
    batch.update(db.collection(Collections.transactions).doc(txId), {
      'deleted': true,
      'deleted_at': now,
      'deleted_by': deletedBy.trim(),
      'updated_at': now,
    });

    if (shopId != null && shopId.isNotEmpty) {
      // Reverse: cash_out added to balance, so subtract; cash_in subtracted, so add
      final reversalDelta = type == 'cash_out' ? -amount : amount;
      batch.update(db.collection(Collections.customers).doc(shopId), {
        'balance': FieldValue.increment(reversalDelta),
        'updated_at': now,
        'last_transaction_at': now,
      });
    }

    await _commit(batch);
  }

  /// Creates a return transaction: reduces what the customer owes and optionally
  /// restores seller inventory stock. Treated like cash_in (balance goes down).
  Future<void> createReturn({
    required String shopId,
    required String shopName,
    required String routeId,
    required double amount,
    String? description,
    List<TransactionItem> items = const [],
    Map<String, int> sellerInventoryRestores = const {},
    required String createdBy,
  }) async {
    final normalizedCreatedBy = createdBy.trim();
    if (normalizedCreatedBy.isEmpty) {
      throw ArgumentError('createdBy must not be empty');
    }

    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    final tenantId = await _currentTenantId();

    final txRef = db.collection(Collections.transactions).doc();
    batch.set(txRef, {
      'shop_id': shopId,
      'shop_name': shopName,
      'route_id': routeId,
      'tenant_id': tenantId,
      'type': TransactionModel.typeReturn,
      'sale_type': 'return',
      'amount': amount,
      'description': description,
      'items': items.map((e) => e.toJson()).toList(),
      'created_by': normalizedCreatedBy,
      'created_at': Timestamp.now(),
      'deleted': false, // DI-01: required for isNotEqualTo filter
    });

    // Return reduces balance (customer owes less)
    if (shopId.isNotEmpty) {
      batch.update(db.collection(Collections.customers).doc(shopId), {
        'balance': FieldValue.increment(-amount),
        'updated_at': Timestamp.now(),
        'last_transaction_at': Timestamp.now(),
        'last_transaction_type': TransactionModel.typeReturn,
        'last_transaction_amount': amount,
      });
    }

    // Restore seller inventory stock for returned items
    for (final entry in sellerInventoryRestores.entries) {
      if (entry.value > 0) {
        batch
            .update(db.collection(Collections.sellerInventory).doc(entry.key), {
              'quantity_available': FieldValue.increment(entry.value),
              'updated_at': Timestamp.now(),
            });
      }
    }

    await _commit(batch);
  }

  /// Updates a transaction and adjusts customer balance for the change.
  Future<void> updateTransaction({
    required String txId,
    required String? shopId,
    required double oldAmount,
    required String oldType,
    required double newAmount,
    required String newType,
    String? description,
    String? saleType,
    Timestamp? transactionDate,
  }) async {
    await _runWriteGuard(() async {
      if (txId.trim().isEmpty) {
        throw ArgumentError('txId must not be empty');
      }
      if (newAmount <= 0) {
        throw ArgumentError('newAmount must be greater than 0');
      }
      const allowedTypes = {
        'cash_out',
        'cash_in',
        'return',
        'payment',
        'write_off',
      };
      if (!allowedTypes.contains(newType)) {
        throw ArgumentError(
          'Invalid transaction type "$newType". Allowed: ${allowedTypes.join(', ')}',
        );
      }

      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      _stageTransactionUpdate(
        batch: batch,
        db: db,
        txId: txId,
        shopId: shopId,
        oldAmount: oldAmount,
        oldType: oldType,
        newAmount: newAmount,
        newType: newType,
        description: description,
        saleType: saleType,
        transactionDate: transactionDate,
      );
      await _commit(batch);
    });
  }

  /// Seller edits cash_in/cash_out transactions.
  /// Returns true when applied immediately, false when submitted for approval.
  Future<bool> sellerEditTransaction({
    required String txId,
    required String sellerId,
    required double newAmount,
    required String newType,
    String? description,
    String? saleType,
    Timestamp? transactionDate,
  }) async {
    if (txId.trim().isEmpty) throw ArgumentError('txId must not be empty');
    if (sellerId.trim().isEmpty) {
      throw ArgumentError('sellerId must not be empty');
    }
    if (newAmount <= 0) {
      throw ArgumentError('newAmount must be greater than 0');
    }
    if (newType != 'cash_in' && newType != 'cash_out') {
      throw ArgumentError('Seller can edit only cash_in/cash_out transactions');
    }

    final db = FirebaseFirestore.instance;
    final txRef = db.collection(Collections.transactions).doc(txId);
    final txDoc = await txRef.get();
    if (!txDoc.exists) throw StateError('Transaction not found');
    final data = txDoc.data()!;

    final createdBy = (data['created_by'] as String?)?.trim() ?? '';
    if (createdBy != sellerId.trim()) {
      throw StateError('Seller can edit only own transactions');
    }

    final linkedInvoiceId = (data['invoice_id'] as String?)?.trim() ?? '';
    if (linkedInvoiceId.isNotEmpty) {
      throw StateError(
        'Cannot edit a transaction that is linked to invoice '
        '$linkedInvoiceId. Void the invoice to make corrections.',
      );
    }

    final alreadyPending = data['edit_request_pending'] as bool? ?? false;
    if (alreadyPending) {
      throw StateError(
        'An edit request is already pending for this transaction. '
        'Wait for admin review before submitting another.',
      );
    }

    final oldType = (data['type'] as String?) ?? 'cash_out';
    if (oldType != 'cash_in' && oldType != 'cash_out') {
      throw StateError('Only cash_in/cash_out transactions can be edited');
    }

    final currentUser = await ref.read(authUserProvider.future);
    final tenantId = TenantScope.normalize(currentUser?.tenantId);
    final settingsDoc = await db
        .collection(Collections.settings)
        .doc(tenantId ?? TenantScope.globalTenantId)
        .get();
    final requireApproval =
        (settingsDoc
                .data()?['require_admin_approval_for_seller_transaction_edits']
            as bool?) ??
        false;

    if (requireApproval) {
      await txRef
          .update({
            'edit_request_pending': true,
            'edit_request_status': 'pending',
            'edit_request_requested_by': sellerId.trim(),
            'edit_request_requested_at': Timestamp.now(),
            'edit_request_new_amount': newAmount,
            'edit_request_new_type': newType,
            'edit_request_new_description': description,
            'edit_request_new_sale_type': saleType,
            'edit_request_new_created_at': transactionDate,
            'updated_at': Timestamp.now(),
          })
          .timeout(const Duration(seconds: 20));
      return false;
    }

    final batch = db.batch();
    _stageTransactionUpdate(
      batch: batch,
      db: db,
      txId: txId,
      shopId: (data['shop_id'] as String?)?.trim(),
      oldAmount: (data['amount'] as num?)?.toDouble() ?? 0,
      oldType: oldType,
      newAmount: newAmount,
      newType: newType,
      description: description,
      saleType: saleType,
      transactionDate: transactionDate,
      extraTxFields: {
        'edit_request_pending': false,
        'edit_request_status': 'approved',
        'edit_request_reviewed_by': sellerId.trim(),
        'edit_request_reviewed_at': Timestamp.now(),
        'edit_request_new_amount': FieldValue.delete(),
        'edit_request_new_type': FieldValue.delete(),
        'edit_request_new_description': FieldValue.delete(),
        'edit_request_new_sale_type': FieldValue.delete(),
        'edit_request_new_created_at': FieldValue.delete(),
      },
    );
    await _commit(batch);
    return true;
  }

  /// Admin review for seller-submitted transaction edit requests.
  Future<void> reviewSellerEditRequest({
    required String txId,
    required bool approved,
    required String reviewerId,
  }) async {
    if (txId.trim().isEmpty) throw ArgumentError('txId must not be empty');
    if (reviewerId.trim().isEmpty) {
      throw ArgumentError('reviewerId must not be empty');
    }

    final reviewer = await ref.read(authUserProvider.future);
    if (reviewer == null || !reviewer.isAdmin) {
      throw StateError('Admin privileges required');
    }

    final db = FirebaseFirestore.instance;
    final txRef = db.collection(Collections.transactions).doc(txId);
    final txDoc = await txRef.get();
    if (!txDoc.exists) throw StateError('Transaction not found');
    final data = txDoc.data()!;

    final pending = data['edit_request_pending'] as bool? ?? false;
    if (!pending) return;

    if (!approved) {
      await txRef
          .update({
            'edit_request_pending': false,
            'edit_request_status': 'rejected',
            'edit_request_reviewed_by': reviewerId.trim(),
            'edit_request_reviewed_at': Timestamp.now(),
            'updated_at': Timestamp.now(),
          })
          .timeout(const Duration(seconds: 20));
      return;
    }

    final oldType = (data['type'] as String?) ?? 'cash_out';
    final newType = (data['edit_request_new_type'] as String?) ?? oldType;
    final oldAmount = (data['amount'] as num?)?.toDouble() ?? 0;
    final newAmount =
        (data['edit_request_new_amount'] as num?)?.toDouble() ?? oldAmount;

    final batch = db.batch();
    _stageTransactionUpdate(
      batch: batch,
      db: db,
      txId: txId,
      shopId: (data['shop_id'] as String?)?.trim(),
      oldAmount: oldAmount,
      oldType: oldType,
      newAmount: newAmount,
      newType: newType,
      description: data['edit_request_new_description'] as String?,
      saleType: data['edit_request_new_sale_type'] as String?,
      transactionDate: data['edit_request_new_created_at'] as Timestamp?,
      extraTxFields: {
        'edit_request_pending': false,
        'edit_request_status': 'approved',
        'edit_request_reviewed_by': reviewerId.trim(),
        'edit_request_reviewed_at': Timestamp.now(),
        'edit_request_new_amount': FieldValue.delete(),
        'edit_request_new_type': FieldValue.delete(),
        'edit_request_new_description': FieldValue.delete(),
        'edit_request_new_sale_type': FieldValue.delete(),
        'edit_request_new_created_at': FieldValue.delete(),
      },
    );
    await _commit(batch);
  }
}

final transactionNotifierProvider =
    AsyncNotifierProvider<TransactionNotifier, void>(TransactionNotifier.new);
