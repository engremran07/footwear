import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../models/transaction_model.dart';
import 'auth_provider.dart';

final shopTransactionsProvider = StreamProvider.autoDispose
    .family<List<TransactionModel>, String>((ref, shopId) {
  return FirebaseFirestore.instance
      .collection(Collections.transactions)
      .where('shop_id', isEqualTo: shopId)
      .where('deleted', isEqualTo: false)
      .orderBy('created_at', descending: true)
      .limit(100)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => TransactionModel.fromJson(d.data(), d.id))
          .toList());
});

final allTransactionsProvider =
    StreamProvider.autoDispose<List<TransactionModel>>((ref) {
  // Admin-only unfiltered query: guard to prevent PERMISSION_DENIED.
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null || !user.isAdmin) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection(Collections.transactions)
      .where('deleted', isEqualTo: false)
      .orderBy('created_at', descending: true)
      .limit(200)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => TransactionModel.fromJson(d.data(), d.id))
          .toList());
});

/// Seller-scoped: transactions created by this seller.
final sellerTransactionsProvider = StreamProvider.autoDispose
    .family<List<TransactionModel>, String>((ref, sellerId) {
  return FirebaseFirestore.instance
      .collection(Collections.transactions)
      .where('created_by', isEqualTo: sellerId)
      .where('deleted', isEqualTo: false)
      .orderBy('created_at', descending: true)
      .limit(200)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => TransactionModel.fromJson(d.data(), d.id))
          .toList());
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
  }) async {
    final normalizedCreatedBy = createdBy.trim();
    if (normalizedCreatedBy.isEmpty) {
      throw ArgumentError('createdBy must not be empty');
    }
    // Validate type is in allowed set to prevent arbitrary transaction types
    const allowedTypes = {
      'cash_out', 'cash_in', 'return', 'payment', 'write_off'
    };
    if (!allowedTypes.contains(type)) {
      throw ArgumentError(
        'Invalid transaction type "$type". Allowed: ${allowedTypes.join(', ')}',
      );
    }
    if (amount <= 0) {
      throw ArgumentError('Transaction amount must be greater than 0');
    }
    // shopId and routeId are optional for admin-only customer-level transactions;
    // balance update logic already guards on isNotEmpty below.

    final db = FirebaseFirestore.instance;
    final batch = db.batch();

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
    });

    // Update shop balance: cash_out adds, cash_in subtracts
    if (shopId.isNotEmpty) {
      final balanceDelta = type == 'cash_out' ? amount : -amount;
      batch.update(db.collection(Collections.customers).doc(shopId), {
        'balance': FieldValue.increment(balanceDelta),
        'updated_at': Timestamp.now(),
      });
    }

    // Update customer balance — only when customerId differs from shopId
    // (prevents duplicate batch writes to the same document).
    if (customerId != null && customerId.isNotEmpty && customerId != shopId) {
      final balanceDelta = type == 'cash_out' ? amount : -amount;
      batch.update(db.collection(Collections.customers).doc(customerId), {
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

  /// Creates a seller-side sale transaction.
  /// Deducts stock from [sellerInventoryDeductions] (map of sellerInventoryDocIdâ†’qty)
  /// in the same atomic batch as the transaction + customer balance update.
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
    Timestamp? transactionDate,
  }) async {
    final normalizedCreatedBy = createdBy.trim();
    if (normalizedCreatedBy.isEmpty) {
      throw ArgumentError('createdBy must not be empty');
    }
    if (customerId.trim().isEmpty) {
      throw ArgumentError('customerId must not be empty');
    }

    final db = FirebaseFirestore.instance;
    final batch = db.batch();

    final txRef = db.collection(Collections.transactions).doc();
    batch.set(txRef, {
      'shop_id': '',
      'shop_name': '',
      'route_id': routeId,
      'customer_id': customerId,
      'customer_name': customerName,
      'type': 'cash_out',
      'sale_type': saleType ?? 'cash',
      'amount': amount,
      'description': description,
      'items': items.map((e) => e.toJson()).toList(),
      'created_by': normalizedCreatedBy,
      'created_at': transactionDate ?? Timestamp.now(),
      'deleted': false, // DI-01: required for isNotEqualTo filter
    });

    // Customer owes more
    batch.update(db.collection(Collections.customers).doc(customerId), {
      'balance': FieldValue.increment(amount),
      'updated_at': Timestamp.now(),
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

    await batch.commit();
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
        batch.update(
          db.collection(Collections.sellerInventory).doc(entry.key),
          {
            'quantity_available': FieldValue.increment(entry.value),
            'updated_at': Timestamp.now(),
          },
        );
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
