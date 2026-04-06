import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/collections.dart';
import '../models/invoice_model.dart';
import 'auth_provider.dart';

enum VoidRefundMode { cashRefund, creditBalance }

final invoicesByCustomerProvider = StreamProvider.autoDispose
    .family<List<InvoiceModel>, String>((ref, customerId) {
  return FirebaseFirestore.instance
      .collection(Collections.invoices)
      .where('customer_id', isEqualTo: customerId)
      .orderBy('created_at', descending: true)
      .limit(100)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => InvoiceModel.fromJson(d.data(), d.id)).toList());
});

final invoicesByShopProvider = StreamProvider.autoDispose
    .family<List<InvoiceModel>, String>((ref, shopId) {
  return FirebaseFirestore.instance
      .collection(Collections.invoices)
      .where('shop_id', isEqualTo: shopId)
      .orderBy('created_at', descending: true)
      .limit(100)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => InvoiceModel.fromJson(d.data(), d.id)).toList());
});

final allInvoicesProvider =
    StreamProvider.autoDispose<List<InvoiceModel>>((ref) {
  // Prefer roleAwareInvoicesProvider in screens; use this only for admin-only
  // bulk operations where you need ALL invoices regardless of role.
  return FirebaseFirestore.instance
      .collection(Collections.invoices)
      .orderBy('created_at', descending: true)
      .limit(200)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => InvoiceModel.fromJson(d.data(), d.id)).toList());
});

/// Seller-scoped: only invoices created by this seller.
final sellerInvoicesProvider = StreamProvider.autoDispose
    .family<List<InvoiceModel>, String>((ref, sellerId) {
  return FirebaseFirestore.instance
      .collection(Collections.invoices)
      .where('seller_id', isEqualTo: sellerId)
      .orderBy('created_at', descending: true)
      .limit(200)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => InvoiceModel.fromJson(d.data(), d.id)).toList());
});

/// Role-aware: admins see all, sellers see only their own.
final roleAwareInvoicesProvider =
    StreamProvider.autoDispose<List<InvoiceModel>>((ref) {
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  if (user.isAdmin) {
    return FirebaseFirestore.instance
        .collection(Collections.invoices)
        .orderBy('created_at', descending: true)
        .limit(200)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => InvoiceModel.fromJson(d.data(), d.id))
            .toList());
  }
  return FirebaseFirestore.instance
      .collection(Collections.invoices)
      .where('seller_id', isEqualTo: user.id)
      .orderBy('created_at', descending: true)
      .limit(200)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => InvoiceModel.fromJson(d.data(), d.id)).toList());
});

final invoiceByIdProvider =
    StreamProvider.autoDispose.family<InvoiceModel?, String>((ref, invoiceId) {
  return FirebaseFirestore.instance
      .collection(Collections.invoices)
      .doc(invoiceId)
      .snapshots()
      .map((doc) =>
          doc.exists ? InvoiceModel.fromJson(doc.data()!, doc.id) : null);
});

class InvoiceNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  void _restoreWarehouseStock(
    WriteBatch batch,
    FirebaseFirestore db,
    List<dynamic> rawItems,
    Timestamp now,
  ) {
    for (final item in rawItems.whereType<Map<String, dynamic>>()) {
      final variantId = (item['variant_id'] as String?)?.trim() ?? '';
      final qty = (item['qty'] as num?)?.toInt() ?? 0;
      if (variantId.isEmpty || qty <= 0) continue;
      batch.update(db.collection(Collections.productVariants).doc(variantId), {
        'quantity_available': FieldValue.increment(qty),
        'updated_at': now,
      });
    }
  }

  /// Generates the next invoice number: INV-YYYY-NNNN.
  ///
  /// Uses a Firestore transaction on settings/global.last_invoice_number so
  /// that concurrent invoice creation never produces duplicate numbers.
  Future<String> _nextInvoiceNumber() async {
    final db = FirebaseFirestore.instance;
    final settingsRef = db.collection(Collections.settings).doc('global');
    final next = await db.runTransaction<int>((txn) async {
      final doc = await txn.get(settingsRef);
      final currentNum = (doc.data()?['last_invoice_number'] as int?) ?? 0;
      final nextNum = currentNum + 1;
      txn.update(settingsRef, {'last_invoice_number': nextNum});
      return nextNum;
    });
    return 'INV-${DateTime.now().year}-${next.toString().padLeft(4, '0')}';
  }

  /// Creates a sale invoice with atomic customer balance update and stock deduction.
  ///
  /// Payment scenarios handled via [amountReceived]:
  /// - 0 â†’ full credit (status: issued)
  /// - > 0 and < total â†’ partial payment (status: partial)
  /// - >= total â†’ full payment (status: paid); excess reduces old balance
  Future<String> createSaleInvoice({
    required String customerId,
    required String customerName,
    String shopId = '',
    String shopName = '',
    required String routeId,
    String sellerId = '',
    String sellerName = '',
    required List<Map<String, dynamic>> items,
    required double subtotal,
    double discount = 0,
    required double total,
    double amountReceived = 0,
    String? notes,
    required String createdBy,
    Map<String, int> sellerInventoryDeductions = const {},
    String?
        idempotencyKey, // optional: pass a stable UUID to prevent duplicates on retry
  }) async {
    final normalizedCreatedBy = createdBy.trim();
    if (normalizedCreatedBy.isEmpty) {
      throw ArgumentError('createdBy must not be empty');
    }
    if (customerId.trim().isEmpty) {
      throw ArgumentError('customerId must not be empty');
    }
    if (discount < 0 || discount > subtotal) {
      throw ArgumentError('discount must be between 0 and subtotal');
    }
    if (amountReceived < 0) {
      throw ArgumentError('amountReceived must not be negative');
    }
    // Max-amount cap prevents fraudulent invoices
    const double maxInvoiceAmount = 999999.99;
    if (total > maxInvoiceAmount) {
      throw ArgumentError(
        'Invoice total exceeds maximum allowed amount '
        '(${maxInvoiceAmount.toStringAsFixed(2)})',
      );
    }
    // Item subtotal integrity check: sum of (qty * unit_price) must equal subtotal
    if (items.isNotEmpty) {
      final computedSubtotal = items.fold<double>(
        0,
        (acc, item) =>
            acc +
            ((item['qty'] as num?)?.toDouble() ?? 0) *
                ((item['unit_price'] as num?)?.toDouble() ?? 0),
      );
      // Allow 0.01 floating-point tolerance
      if ((computedSubtotal - subtotal).abs() > 0.01) {
        throw ArgumentError(
          'Item subtotals (${computedSubtotal.toStringAsFixed(2)}) '
          'do not match invoice subtotal (${subtotal.toStringAsFixed(2)})',
        );
      }
    }
    // FI-07: total must equal subtotal minus discount
    if ((total - (subtotal - discount)).abs() > 0.01) {
      throw ArgumentError(
        'Invoice total (${total.toStringAsFixed(2)}) must equal '
        'subtotal minus discount (${(subtotal - discount).toStringAsFixed(2)})',
      );
    }

    // Idempotency guard: if caller passes a key, check for existing invoice
    final db = FirebaseFirestore.instance;
    final resolvedKey = idempotencyKey ?? const Uuid().v4();
    if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
      final existing = await db
          .collection(Collections.invoices)
          .where('idempotency_key', isEqualTo: idempotencyKey)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        return existing
            .docs.first.id; // return existing instead of creating duplicate
      }
    }

    // Derive sale type and invoice status from payment
    final String saleType;
    final String invoiceStatus;
    if (amountReceived >= total && total > 0) {
      saleType = 'cash';
      invoiceStatus = InvoiceModel.statusPaid;
    } else if (amountReceived > 0) {
      saleType = 'credit';
      invoiceStatus = InvoiceModel.statusPartial;
    } else {
      saleType = 'credit';
      invoiceStatus = InvoiceModel.statusIssued;
    }

    final invoiceNumber = await _nextInvoiceNumber();
    final batch = db.batch();
    final now = Timestamp.now();

    // Create invoice doc
    final invRef = db.collection(Collections.invoices).doc();
    batch.set(invRef, {
      'invoice_number': invoiceNumber,
      'idempotency_key': resolvedKey,
      'type': InvoiceModel.typeSale,
      'customer_id': customerId,
      'customer_name': customerName,
      'shop_id': shopId,
      'shop_name': shopName,
      'route_id': routeId,
      'seller_id': sellerId,
      'seller_name': sellerName,
      'items': items,
      'subtotal': subtotal,
      'discount': discount,
      'total': total,
      'amount_received': amountReceived,
      'outstanding_amount': total - amountReceived,
      'sale_type': saleType,
      'status': invoiceStatus,
      'notes': notes,
      'linked_invoice_id': null,
      'seller_inventory_deductions': sellerInventoryDeductions,
      'created_by': normalizedCreatedBy,
      'created_at': now,
      'updated_at': now,
    });

    // Create cash_out transaction for the sale (goods delivered)
    final txRef = db.collection(Collections.transactions).doc();
    batch.set(txRef, {
      'shop_id': shopId,
      'shop_name': shopName,
      'route_id': routeId,
      'customer_id': customerId,
      'customer_name': customerName,
      'type': 'cash_out',
      'sale_type': saleType,
      'amount': total,
      'description': 'Invoice $invoiceNumber',
      'items': items,
      'invoice_id': invRef.id,
      'invoice_number': invoiceNumber,
      'created_by': normalizedCreatedBy,
      'created_at': now,
      'deleted': false, // DI-01: required for isNotEqualTo filter
    });

    // If payment received, create a separate cash_in transaction
    if (amountReceived > 0) {
      final payRef = db.collection(Collections.transactions).doc();
      batch.set(payRef, {
        'shop_id': shopId,
        'shop_name': shopName,
        'route_id': routeId,
        'customer_id': customerId,
        'customer_name': customerName,
        'type': 'cash_in',
        'sale_type': 'cash',
        'amount': amountReceived,
        'description': 'Payment for $invoiceNumber',
        'items': <Map<String, dynamic>>[],
        'invoice_id': invRef.id,
        'invoice_number': invoiceNumber,
        'created_by': normalizedCreatedBy,
        'created_at': now,
        'deleted': false, // DI-01: required for isNotEqualTo filter
      });
    }

    // Customer balance: net change = sale total âˆ’ amount received
    // e.g. sale 5000, received 2000 â†’ balance +3000
    // e.g. sale 5000, received 8000 â†’ balance âˆ’3000 (pays off old debt)
    if (customerId.isNotEmpty) {
      final balanceDelta = total - amountReceived;
      batch.update(db.collection(Collections.customers).doc(customerId), {
        'balance': FieldValue.increment(balanceDelta),
        'updated_at': now,
      });
    }

    // Deduct seller inventory if applicable
    for (final entry in sellerInventoryDeductions.entries) {
      if (entry.value > 0) {
        batch.update(
          db.collection(Collections.sellerInventory).doc(entry.key),
          {
            'quantity_available': FieldValue.increment(-entry.value),
            'updated_at': now,
          },
        );
      }
    }

    await batch.commit();
    return invRef.id;
  }

  /// Creates a return/credit note invoice that reverses balance and restores stock.
  Future<String> createReturnInvoice({
    required String customerId,
    required String customerName,
    String shopId = '',
    String shopName = '',
    required String routeId,
    String sellerId = '',
    String sellerName = '',
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double total,
    String? linkedInvoiceId,
    String? notes,
    required String createdBy,
    Map<String, int> sellerInventoryRestores = const {},
  }) async {
    final normalizedCreatedBy = createdBy.trim();
    if (normalizedCreatedBy.isEmpty) {
      throw ArgumentError('createdBy must not be empty');
    }
    if (customerId.trim().isEmpty) {
      throw ArgumentError('customerId must not be empty');
    }

    final db = FirebaseFirestore.instance;
    // I-12: 30-day time-lock on credit note creation
    if (linkedInvoiceId != null && linkedInvoiceId.isNotEmpty) {
      final origSnap =
          await db.collection(Collections.invoices).doc(linkedInvoiceId).get();
      if (origSnap.exists) {
        final origStatus = origSnap.data()?['status'] as String? ?? '';
        if (origStatus == InvoiceModel.statusVoid) {
          throw ArgumentError(
            'Cannot create a credit note against a voided invoice',
          );
        }
        final origCreatedAt = origSnap.data()?['created_at'] as Timestamp?;
        if (origCreatedAt != null) {
          final ageInDays =
              DateTime.now().difference(origCreatedAt.toDate()).inDays;
          if (ageInDays > 30) {
            throw ArgumentError(
              'Credit notes must be created within 30 days of the original invoice',
            );
          }
        }
      }
    }

    final invoiceNumber = await _nextInvoiceNumber();
    final batch = db.batch();
    final now = Timestamp.now();

    final invRef = db.collection(Collections.invoices).doc();
    batch.set(invRef, {
      'invoice_number': invoiceNumber,
      'idempotency_key': const Uuid().v4(), // dedup guard
      'type': InvoiceModel.typeCreditNote,
      'customer_id': customerId,
      'customer_name': customerName,
      'shop_id': shopId,
      'shop_name': shopName,
      'route_id': routeId,
      'seller_id': sellerId,
      'seller_name': sellerName,
      'items': items,
      'subtotal': subtotal,
      'discount': 0,
      'total': total,
      'amount_received': 0,
      'outstanding_amount': 0,
      'sale_type': 'return',
      'status': InvoiceModel.statusIssued,
      'notes': notes,
      'linked_invoice_id': linkedInvoiceId,
      'created_by': normalizedCreatedBy,
      'created_at': now,
      'updated_at': now,
    });

    // Create return transaction
    final txRef = db.collection(Collections.transactions).doc();
    batch.set(txRef, {
      'shop_id': shopId,
      'shop_name': shopName,
      'route_id': routeId,
      'customer_id': customerId,
      'customer_name': customerName,
      'type': 'return',
      'sale_type': 'return',
      'amount': total,
      'description': 'Credit note $invoiceNumber',
      'items': items,
      'invoice_id': invRef.id,
      'invoice_number': invoiceNumber,
      'created_by': normalizedCreatedBy,
      'created_at': now,
      'deleted': false, // DI-01: required for isNotEqualTo filter
    });

    // Return reduces customer balance
    if (customerId.isNotEmpty) {
      batch.update(db.collection(Collections.customers).doc(customerId), {
        'balance': FieldValue.increment(-total),
        'updated_at': now,
      });
    }

    // Restore seller inventory
    for (final entry in sellerInventoryRestores.entries) {
      if (entry.value > 0) {
        batch.update(
          db.collection(Collections.sellerInventory).doc(entry.key),
          {
            'quantity_available': FieldValue.increment(entry.value),
            'updated_at': now,
          },
        );
      }
    }

    if (sellerInventoryRestores.isEmpty) {
      _restoreWarehouseStock(batch, db, items, now);
    }

    await batch.commit();
    return invRef.id;
  }

  /// Voids an invoice â€” admin only, reverses balance impact.
  Future<void> voidInvoice({
    required String invoiceId,
    required String customerId,
    required double total,
    required String type,
    required String createdBy,
    VoidRefundMode refundMode = VoidRefundMode.creditBalance,
  }) async {
    if (invoiceId.trim().isEmpty) {
      throw ArgumentError('invoiceId must not be empty');
    }
    if (createdBy.trim().isEmpty) {
      throw ArgumentError('createdBy must not be empty');
    }

    final db = FirebaseFirestore.instance;
    // double-void guard — read current status before reversing
    final invSnap =
        await db.collection(Collections.invoices).doc(invoiceId).get();
    if (!invSnap.exists) {
      throw ArgumentError('Invoice not found: $invoiceId');
    }
    final currentStatus = invSnap.data()?['status'] as String? ?? '';
    if (currentStatus == 'void') {
      throw StateError('Invoice $invoiceId is already voided');
    }

    final data = invSnap.data()!;
    final amountReceived = (data['amount_received'] as num?)?.toDouble() ?? 0.0;
    final outstandingAmount =
        (data['outstanding_amount'] as num?)?.toDouble() ??
            (total - amountReceived);
    final invoiceNumber = data['invoice_number'] as String? ?? '';
    final routeId = data['route_id'] as String? ?? '';
    final shopId = data['shop_id'] as String? ?? '';
    final shopName = data['shop_name'] as String? ?? '';
    final customerName = data['customer_name'] as String? ?? '';
    final rawItems = (data['items'] as List<dynamic>?) ?? const [];
    final linkedTransactions = await db
        .collection(Collections.transactions)
        .where('invoice_id', isEqualTo: invoiceId)
        .where('deleted', isEqualTo: false)
        .get();

    final batch = db.batch();
    final now = Timestamp.now();

    Map<String, dynamic> transactionData({
      required String txType,
      required double amount,
      required String description,
      List<Map<String, dynamic>> items = const <Map<String, dynamic>>[],
      String txCustomerId = '',
      String txCustomerName = '',
      String txShopId = '',
      String txShopName = '',
    }) {
      return {
        'shop_id': txShopId,
        'shop_name': txShopName,
        'route_id': routeId,
        'customer_id': txCustomerId,
        'customer_name': txCustomerName,
        'type': txType,
        'sale_type': type == InvoiceModel.typeSale ? 'credit' : 'return',
        'amount': amount,
        'description': description,
        'items': items,
        'invoice_id': invoiceId,
        'invoice_number': invoiceNumber,
        'created_by': createdBy.trim(),
        'created_at': now,
        'deleted': false,
      };
    }

    batch.update(db.collection(Collections.invoices).doc(invoiceId), {
      'status': InvoiceModel.statusVoid,
      'updated_at': now,
    });

    for (final tx in linkedTransactions.docs) {
      batch.update(tx.reference, {
        'deleted': true,
        'deleted_at': now,
        'deleted_by': createdBy.trim(),
        'deleted_reason': 'invoice_voided',
        'updated_at': now,
      });
    }

    if (customerId.isNotEmpty) {
      final reversalDelta = switch (type) {
        InvoiceModel.typeSale => refundMode == VoidRefundMode.creditBalance
            ? -total
            : -outstandingAmount,
        _ => total,
      };

      batch.update(db.collection(Collections.customers).doc(customerId), {
        'balance': FieldValue.increment(reversalDelta),
        'updated_at': now,
      });

      final rawDeductions =
          (data['seller_inventory_deductions'] as Map<String, dynamic>?) ??
              const <String, dynamic>{};
      for (final entry in rawDeductions.entries) {
        final qty = (entry.value as num?)?.toInt() ?? 0;
        if (qty <= 0) continue;
        batch.update(
          db.collection(Collections.sellerInventory).doc(entry.key),
          {
            'quantity_available': FieldValue.increment(qty),
            'updated_at': now,
          },
        );
      }

      if (rawDeductions.isEmpty) {
        _restoreWarehouseStock(batch, db, rawItems, now);
      }

      if (type == InvoiceModel.typeSale) {
        // Write ONE reversal transaction (the live-ledger reversal entry).
        // The soft-deleted originals above already form the complete audit trail.
        final reversalAmount = refundMode == VoidRefundMode.creditBalance
            ? total
            : outstandingAmount;
        if (reversalAmount > 0) {
          batch.set(
            db.collection(Collections.transactions).doc(),
            transactionData(
              txType: 'return',
              amount: reversalAmount,
              description: refundMode == VoidRefundMode.creditBalance
                  ? 'Credit for voided invoice $invoiceNumber'
                  : 'Outstanding reversal for voided invoice $invoiceNumber',
              txCustomerId: customerId,
              txCustomerName: customerName,
              txShopId: shopId,
              txShopName: shopName,
            ),
          );
        }

        // Cash refund: record the physical cash disbursement (no balance impact —
        // the balance was already reversed via reversalDelta above).
        if (refundMode == VoidRefundMode.cashRefund && amountReceived > 0) {
          batch.set(
            db.collection(Collections.transactions).doc(),
            transactionData(
              txType: 'cash_out',
              amount: amountReceived,
              description: 'Cash refund for voided invoice $invoiceNumber',
              txCustomerId: customerId,
              txCustomerName: customerName,
              txShopId: shopId,
              txShopName: shopName,
            ),
          );
        }
      } else {
        batch.set(
          db.collection(Collections.transactions).doc(),
          transactionData(
            txType: 'return',
            amount: total,
            description: 'Voided credit note snapshot $invoiceNumber',
            items: rawItems.whereType<Map<String, dynamic>>().toList(),
            txCustomerId: customerId,
            txCustomerName: customerName,
            txShopId: shopId,
            txShopName: shopName,
          ),
        );
        batch.set(
          db.collection(Collections.transactions).doc(),
          transactionData(
            txType: 'cash_out',
            amount: total,
            description: 'Reversal for voided credit note $invoiceNumber',
            txCustomerId: customerId,
            txCustomerName: customerName,
            txShopId: shopId,
            txShopName: shopName,
          ),
        );
      }
    }

    await batch.commit();
  }

  /// Marks an invoice as paid.
  ///
  /// FI-06: Creates a cash_in transaction and decrements customer.balance
  /// by the outstanding_amount in the same atomic batch. Without this,
  /// the customer ledger would be permanently wrong.
  Future<void> markAsPaid({
    required String invoiceId,
    required String customerId,
    required String routeId,
    required String createdBy,
  }) async {
    if (invoiceId.trim().isEmpty) {
      throw ArgumentError('invoiceId must not be empty');
    }
    if (createdBy.trim().isEmpty) {
      throw ArgumentError('createdBy must not be empty');
    }
    final db = FirebaseFirestore.instance;
    final invSnap =
        await db.collection(Collections.invoices).doc(invoiceId).get();
    if (!invSnap.exists) {
      throw ArgumentError('Invoice not found: $invoiceId');
    }
    final invData = invSnap.data()!;
    final currentStatus = invData['status'] as String? ?? '';
    if (currentStatus == InvoiceModel.statusVoid) {
      throw StateError('Cannot mark a voided invoice as paid');
    }
    if (currentStatus == InvoiceModel.statusPaid) {
      return; // already paid, idempotent
    }

    final outstanding =
        (invData['outstanding_amount'] as num?)?.toDouble() ?? 0.0;
    final invoiceNumber = invData['invoice_number'] as String? ?? '';
    final shopId = invData['shop_id'] as String? ?? '';
    final shopName = invData['shop_name'] as String? ?? '';
    final customerName = invData['customer_name'] as String? ?? '';
    final now = Timestamp.now();
    final batch = db.batch();

    // Update invoice: mark paid, zero outstanding
    batch.update(db.collection(Collections.invoices).doc(invoiceId), {
      'status': InvoiceModel.statusPaid,
      'amount_received':
          FieldValue.increment(outstanding > 0 ? outstanding : 0),
      'outstanding_amount': 0,
      'updated_at': now,
    });

    // Create cash_in transaction for the settled amount
    if (outstanding > 0) {
      final payRef = db.collection(Collections.transactions).doc();
      batch.set(payRef, {
        'shop_id': shopId,
        'shop_name': shopName,
        'route_id': routeId,
        'customer_id': customerId,
        'customer_name': customerName,
        'type': 'cash_in',
        'sale_type': 'cash',
        'amount': outstanding,
        'description': 'Settled invoice $invoiceNumber',
        'items': <Map<String, dynamic>>[],
        'invoice_id': invoiceId,
        'invoice_number': invoiceNumber,
        'created_by': createdBy.trim(),
        'created_at': now,
        'deleted': false,
      });

      // Decrement customer balance
      if (customerId.isNotEmpty) {
        batch.update(db.collection(Collections.customers).doc(customerId), {
          'balance': FieldValue.increment(-outstanding),
          'updated_at': now,
        });
      }
    }

    await batch.commit();
  }
}

final invoiceNotifierProvider =
    AsyncNotifierProvider<InvoiceNotifier, void>(InvoiceNotifier.new);
