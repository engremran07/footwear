import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../models/transaction_model.dart';
import 'auth_provider.dart';

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

final shopTransactionsProvider = StreamProvider.autoDispose
    .family<List<TransactionModel>, String>((ref, shopId) {
      final normalizedShopId = shopId.trim();
      if (normalizedShopId.isEmpty) {
        return Stream.value(const <TransactionModel>[]);
      }
      // shop_id is the sole identifier. Query by shop_id only.
      return FirebaseFirestore.instance
          .collection(Collections.transactions)
          .where('shop_id', isEqualTo: normalizedShopId)
          .orderBy('created_at', descending: true)
          .limit(_shopTransactionsLiveLimit)
          .snapshots()
          .map(
            (snap) => snap.docs
                .where((d) => d.data()['deleted'] != true)
                .map((d) => TransactionModel.fromJson(d.data(), d.id))
                .toList(),
          );
    });

final allTransactionsProvider =
    StreamProvider.autoDispose<List<TransactionModel>>((ref) {
      // Admin-only unfiltered query: guard to prevent PERMISSION_DENIED.
      final user = ref.watch(authUserProvider).value;
      if (user == null || !user.isAdmin) return const Stream.empty();
      return FirebaseFirestore.instance
          .collection(Collections.transactions)
          .orderBy('created_at', descending: true)
          .limit(200)
          .snapshots()
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
      final user = ref.watch(authUserProvider).value;
      if (user == null) return Stream.value(const <TransactionModel>[]);

      final collection = FirebaseFirestore.instance.collection(
        Collections.transactions,
      );

      if (user.isAdmin) {
        return collection
            .orderBy('created_at', descending: true)
            .limit(_shopsAnalyticsTransactionsLimit)
            .snapshots()
            .map(
              (snap) => snap.docs
                  .where((d) => d.data()['deleted'] != true)
                  .map((d) => TransactionModel.fromJson(d.data(), d.id))
                  .toList(),
            );
      }

      final routeId = (user.assignedRouteId ?? '').trim();
      if (!user.isSeller || routeId.isEmpty) {
        return Stream.value(const <TransactionModel>[]);
      }

      return collection
          .where('route_id', isEqualTo: routeId)
          .orderBy('created_at', descending: true)
          .limit(_shopsAnalyticsTransactionsLimit)
          .snapshots()
          .map(
            (snap) => snap.docs
                .where((d) => d.data()['deleted'] != true)
                .map((d) => TransactionModel.fromJson(d.data(), d.id))
                .toList(),
          );
    });

final pendingEditRequestsProvider =
    StreamProvider.autoDispose<List<TransactionModel>>((ref) {
      final user = ref.watch(authUserProvider).value;
      if (user == null || !user.isAdmin) {
        return Stream.value(const <TransactionModel>[]);
      }
      return FirebaseFirestore.instance
          .collection(Collections.transactions)
          .where('edit_request_pending', isEqualTo: true)
          .orderBy('created_at', descending: true)
          .limit(50)
          .snapshots()
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
      return FirebaseFirestore.instance
          .collection(Collections.transactions)
          .where('created_by', isEqualTo: sellerId)
          .orderBy('created_at', descending: true)
          .limit(200)
          .snapshots()
          .map(
            (snap) => snap.docs
                .where((d) => d.data()['deleted'] != true)
                .map((d) => TransactionModel.fromJson(d.data(), d.id))
                .toList(),
          );
    });

final shopTransactionsExportProvider = FutureProvider.autoDispose
    .family<List<TransactionModel>, String>((ref, shopId) async {
      final normalizedShopId = shopId.trim();
      if (normalizedShopId.isEmpty) return const <TransactionModel>[];
      // shop_id is sole source of truth; no dual query needed.
      // No orderBy here — results are sorted client-side; omitting it avoids
      // the composite index requirement for the ascending direction.
      final snap = await FirebaseFirestore.instance
          .collection(Collections.transactions)
          .where('shop_id', isEqualTo: normalizedShopId)
          .get();

      return snap.docs
          .where((d) => d.data()['deleted'] != true)
          .map((d) => TransactionModel.fromJson(d.data(), d.id))
          .toList();
    });

/// All transactions for a specific route — used by multi-shop PDF export.
final routeTransactionsExportProvider = FutureProvider.autoDispose
    .family<List<TransactionModel>, String>((ref, routeId) async {
      final normalizedId = routeId.trim();
      if (normalizedId.isEmpty) return const <TransactionModel>[];
      final snap = await FirebaseFirestore.instance
          .collection(Collections.transactions)
          .where('route_id', isEqualTo: normalizedId)
          .get();
      return snap.docs
          .where((d) => d.data()['deleted'] != true)
          .map((d) => TransactionModel.fromJson(d.data(), d.id))
          .toList();
    });

/// All transactions across all routes — admin-only bulk export.
final allTransactionsExportProvider =
    FutureProvider.autoDispose<List<TransactionModel>>((ref) async {
      final snap = await FirebaseFirestore.instance
          .collection(Collections.transactions)
          .get();
      return snap.docs
          .where((d) => d.data()['deleted'] != true)
          .map((d) => TransactionModel.fromJson(d.data(), d.id))
          .toList();
    });

class TransactionNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

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
    batch.update(db.collection(Collections.transactions).doc(txId), {
      'amount': newAmount,
      'type': newType,
      'description': ?description,
      'sale_type': ?saleType,
      'created_at': ?transactionDate,
      ...extraTxFields,
      'updated_at': Timestamp.now(),
    });

    if (shopId != null && shopId.isNotEmpty) {
      // Treat return/payment/write_off as balance-reducing amounts by default.
      final oldDelta = oldType == 'cash_out' ? oldAmount : -oldAmount;
      final newDelta = newType == 'cash_out' ? newAmount : -newAmount;
      final netChange = -oldDelta + newDelta;
      if (netChange != 0) {
        batch.update(db.collection(Collections.customers).doc(shopId), {
          'balance': FieldValue.increment(netChange),
          'updated_at': Timestamp.now(),
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

    await batch.commit();
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
    });

    // Deduct from seller_inventory docs
    for (final entry in sellerInventoryDeductions.entries) {
      if (entry.value > 0) {
        batch
            .update(db.collection(Collections.sellerInventory).doc(entry.key), {
              'quantity_available': FieldValue.increment(-entry.value),
              'updated_at': Timestamp.now(),
            });
      }
    }

    await batch.commit();
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
      });
    }

    await batch.commit();
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

    final txRef = db.collection(Collections.transactions).doc();
    batch.set(txRef, {
      'shop_id': shopId,
      'shop_name': shopName,
      'route_id': routeId,
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

    await batch.commit();
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
    await batch.commit();
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

    final settingsDoc = await db
        .collection(Collections.settings)
        .doc('global')
        .get();
    final requireApproval =
        (settingsDoc
                .data()?['require_admin_approval_for_seller_transaction_edits']
            as bool?) ??
        false;

    if (requireApproval) {
      await txRef.update({
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
      });
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
    await batch.commit();
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

    final db = FirebaseFirestore.instance;
    final txRef = db.collection(Collections.transactions).doc(txId);
    final txDoc = await txRef.get();
    if (!txDoc.exists) throw StateError('Transaction not found');
    final data = txDoc.data()!;

    final pending = data['edit_request_pending'] as bool? ?? false;
    if (!pending) return;

    if (!approved) {
      await txRef.update({
        'edit_request_pending': false,
        'edit_request_status': 'rejected',
        'edit_request_reviewed_by': reviewerId.trim(),
        'edit_request_reviewed_at': Timestamp.now(),
        'updated_at': Timestamp.now(),
      });
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
    await batch.commit();
  }
}

final transactionNotifierProvider =
    AsyncNotifierProvider<TransactionNotifier, void>(TransactionNotifier.new);
