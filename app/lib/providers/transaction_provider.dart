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

final shopTransactionsProvider = StreamProvider.autoDispose
    .family<List<TransactionModel>, String>((ref, shopId) {
      // Remove server-side deleted==false: old docs predate the field.
      // Filter client-side with !=true to include legacy docs.
      return FirebaseFirestore.instance
          .collection(Collections.transactions)
          .where('shop_id', isEqualTo: shopId)
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

final allTransactionsProvider =
    StreamProvider.autoDispose<List<TransactionModel>>((ref) {
      // Admin-only unfiltered query: guard to prevent PERMISSION_DENIED.
      final user = ref.watch(authUserProvider).valueOrNull;
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

class TransactionNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Creates a transaction and updates shop balance atomically.
  /// For cash_out with items, also deducts stock from variants.
  Future<void> create({
    required String shopId,
    required String shopName,
    required String routeId,
    required String type,
    required double amount,
    String? description,
    String? customerId,
    String? customerName,
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
    if (customerId != null && customerId.isNotEmpty && customerId != shopId) {
      throw ArgumentError('customerId must match shopId when provided');
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
      'customer_id': customerId,
      'customer_name': customerName,
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
  /// Used for legacy simple sales where no formal invoice is required.
  ///
  /// NOTE: Prefer InvoiceNotifier.createSaleInvoice() for all new sales that
  /// involve stock deduction from seller_inventory. This method exists for
  /// edge-case manual entries only.
  ///
  /// IMPORTANT: customerId here IS the shopId (shops = customers in Firestore).
  Future<void> createSellerSale({
    required String routeId,
    required String customerId,
    required String customerName,
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
    if (customerId.trim().isEmpty) {
      throw ArgumentError('customerId must not be empty');
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
      'shop_id': customerId, // customerId == shopId in our unified architecture
      'shop_name': customerName,
      'route_id': routeId,
      'customer_id':
          customerId, // legacy alias retained for index compatibility
      'customer_name': customerName,
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

    // Customer owes more
    batch.update(db.collection(Collections.customers).doc(customerId), {
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
    required String? customerId,
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

    if (customerId != null && customerId.isNotEmpty) {
      // Reverse: cash_out added to balance, so subtract; cash_in subtracted, so add
      final reversalDelta = type == 'cash_out' ? -amount : amount;
      batch.update(db.collection(Collections.customers).doc(customerId), {
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
      'customer_id': shopId,
      'customer_name': shopName,
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
    required String? customerId,
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

    batch.update(db.collection(Collections.transactions).doc(txId), {
      'amount': newAmount,
      'type': newType,
      if (description != null) 'description': description,
      if (saleType != null) 'sale_type': saleType,
      if (transactionDate != null) 'created_at': transactionDate,
      'updated_at': Timestamp.now(),
    });

    if (customerId != null && customerId.isNotEmpty) {
      // Reverse old delta, then apply new delta
      final oldDelta = oldType == 'cash_out' ? oldAmount : -oldAmount;
      final newDelta = newType == 'cash_out' ? newAmount : -newAmount;
      final netChange = -oldDelta + newDelta;
      if (netChange != 0) {
        batch.update(db.collection(Collections.customers).doc(customerId), {
          'balance': FieldValue.increment(netChange),
          'updated_at': Timestamp.now(),
        });
      }
    }

    await batch.commit();
  }
}

final transactionNotifierProvider =
    AsyncNotifierProvider<TransactionNotifier, void>(TransactionNotifier.new);
