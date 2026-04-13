import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/collections.dart';
import '../models/invoice_model.dart';
import 'auth_provider.dart';

// =============================================================================
// InvoiceProvider — all invoice lifecycle operations.
//
// WHEN TO USE:
//   Call createSaleInvoice() ONLY when making a new sale with stock deduction.
//   For cash collection from existing debt: use TransactionNotifier.create()
//   with type='cash_in' — no invoice needed.
//
// INVOICE vs LEDGER PATHWAYS:
//   Sale + stock available  → createSaleInvoice()
//       └ atomic batch: invoice doc + cash_out tx + optional cash_in tx
//                        + seller_inventory deductions + balance update
//   Return of goods         → createReturnInvoice()
//       └ atomic batch: credit_note invoice + return tx + balance decrease
//                        + optional seller_inventory restore
//   Void invoice            → voidInvoice() [admin only]
//       └ atomic: marks invoice void, soft-deletes linked txs, reverses balance
//
// PARAMETER NOTE:
//   createSaleInvoice / createReturnInvoice use shopId/shopName as sole
//   identifiers. No customer_id field is written to any document.
//
// INVOICE STATE MACHINE:
//   draft → issued → partial → paid
//                  → void (terminal state, never re-opened)
// =============================================================================

enum VoidRefundMode { cashRefund, creditBalance }

/// Shop-scoped invoice query. Used in ShopDetailScreen invoice sections.
/// For all-invoice listing use [roleAwareInvoicesProvider].
final invoicesByShopProvider = StreamProvider.autoDispose
    .family<List<InvoiceModel>, String>((ref, shopId) {
      return FirebaseFirestore.instance
          .collection(Collections.invoices)
          .where('shop_id', isEqualTo: shopId)
          .orderBy('created_at', descending: true)
          .limit(100)
          .snapshots()
          .map(
            (snap) => snap.docs
                .map((d) => InvoiceModel.fromJson(d.data(), d.id))
                .toList(),
          );
    });

final allInvoicesProvider = StreamProvider.autoDispose<List<InvoiceModel>>((
  ref,
) {
  // Admin-only: this provider exposes ALL invoices. Non-admins get an empty
  // stream — use roleAwareInvoicesProvider or sellerInvoicesProvider instead.
  final user = ref.watch(authUserProvider).value;
  if (user == null || !user.isAdmin) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection(Collections.invoices)
      .orderBy('created_at', descending: true)
      .limit(200)
      .snapshots()
      .map(
        (snap) => snap.docs
            .map((d) => InvoiceModel.fromJson(d.data(), d.id))
            .toList(),
      );
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
          .map(
            (snap) => snap.docs
                .map((d) => InvoiceModel.fromJson(d.data(), d.id))
                .toList(),
          );
    });

/// Role-aware: admins see all, sellers see only their own.
/// Delegates to existing role-scoped providers so admin uses the shared
/// listener and AsyncValue loading/error state is preserved.
final roleAwareInvoicesProvider =
    Provider.autoDispose<AsyncValue<List<InvoiceModel>>>((ref) {
      final user = ref.watch(authUserProvider).value;
      if (user == null) return const AsyncData(<InvoiceModel>[]);
      if (user.isAdmin) {
        return ref.watch(allInvoicesProvider);
      }
      return ref.watch(sellerInvoicesProvider(user.id));
    });

final invoiceByIdProvider = StreamProvider.autoDispose
    .family<InvoiceModel?, String>((ref, invoiceId) {
      return FirebaseFirestore.instance
          .collection(Collections.invoices)
          .doc(invoiceId)
          .snapshots()
          .map(
            (doc) =>
                doc.exists ? InvoiceModel.fromJson(doc.data()!, doc.id) : null,
          );
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
      if (doc.exists) {
        txn.update(settingsRef, {'last_invoice_number': nextNum});
      } else {
        txn.set(settingsRef, {
          'last_invoice_number': nextNum,
        }, SetOptions(merge: true));
      }
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
    required String shopId,
    required String shopName,
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
    if (shopId.trim().isEmpty) {
      throw ArgumentError('shopId must not be empty');
    }
    if (discount < 0 || discount > subtotal) {
      throw ArgumentError('discount must be between 0 and subtotal');
    }
    if (amountReceived < 0) {
      throw ArgumentError('amountReceived must not be negative');
    }
    // FI-11: amountReceived cannot exceed the invoice total; doing so would
    // over-credit the customer and corrupt the ledger.
    if (amountReceived > total) {
      throw ArgumentError(
        'amountReceived (${amountReceived.toStringAsFixed(2)}) '
        'cannot exceed invoice total (${total.toStringAsFixed(2)})',
      );
    }
    // Max-amount cap prevents fraudulent invoices
    const double maxInvoiceAmount = 999999.99;
    if (total > maxInvoiceAmount) {
      throw ArgumentError(
        'Invoice total exceeds maximum allowed amount '
        '(${maxInvoiceAmount.toStringAsFixed(2)})',
      );
    }
    // Per-item validation: reject negative unit_price
    for (int i = 0; i < items.length; i++) {
      final price = (items[i]['unit_price'] as num?)?.toDouble() ?? 0;
      if (price < 0) {
        throw ArgumentError('Item $i has negative unit_price ($price)');
      }
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
            .docs
            .first
            .id; // return existing instead of creating duplicate
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
    if (shopId.isNotEmpty) {
      final balanceDelta = total - amountReceived;
      batch.update(db.collection(Collections.customers).doc(shopId), {
        'balance': FieldValue.increment(balanceDelta),
        'updated_at':
            FieldValue.serverTimestamp(), // server time avoids withinWriteRate skew
      });
    }

    // Deduct seller inventory if applicable
    for (final entry in sellerInventoryDeductions.entries) {
      if (entry.value > 0) {
        batch
            .update(db.collection(Collections.sellerInventory).doc(entry.key), {
              'quantity_available': FieldValue.increment(-entry.value),
              'updated_at': now,
            });
      }
    }

    await batch.commit();
    return invRef.id;
  }

  /// Creates a return/credit note invoice that reverses balance and restores stock.
  Future<String> createReturnInvoice({
    required String shopId,
    required String shopName,
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
    String? idempotencyKey,
  }) async {
    final normalizedCreatedBy = createdBy.trim();
    if (normalizedCreatedBy.isEmpty) {
      throw ArgumentError('createdBy must not be empty');
    }
    if (shopId.trim().isEmpty) {
      throw ArgumentError('shopId must not be empty');
    }

    final db = FirebaseFirestore.instance;
    // I-12: 30-day time-lock on credit note creation
    if (linkedInvoiceId != null && linkedInvoiceId.isNotEmpty) {
      final origSnap = await db
          .collection(Collections.invoices)
          .doc(linkedInvoiceId)
          .get();
      if (origSnap.exists) {
        final origStatus = origSnap.data()?['status'] as String? ?? '';
        if (origStatus == InvoiceModel.statusVoid) {
          throw ArgumentError(
            'Cannot create a credit note against a voided invoice',
          );
        }
        final origCreatedAt = origSnap.data()?['created_at'] as Timestamp?;
        if (origCreatedAt != null) {
          final ageInDays = DateTime.now()
              .difference(origCreatedAt.toDate())
              .inDays;
          if (ageInDays > 30) {
            throw ArgumentError(
              'Credit notes must be created within 30 days of the original invoice',
            );
          }
        }
      }
    }

    final normalizedKey = idempotencyKey?.trim();
    final resolvedKey = (normalizedKey != null && normalizedKey.isNotEmpty)
        ? normalizedKey
        : const Uuid().v4();
    if (normalizedKey != null && normalizedKey.isNotEmpty) {
      final existing = await db
          .collection(Collections.invoices)
          .where('idempotency_key', isEqualTo: normalizedKey)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        return existing.docs.first.id;
      }
    }

    final invoiceNumber = await _nextInvoiceNumber();
    final batch = db.batch();
    final now = Timestamp.now();

    final invRef = db.collection(Collections.invoices).doc();
    batch.set(invRef, {
      'invoice_number': invoiceNumber,
      'idempotency_key': resolvedKey,
      'type': InvoiceModel.typeCreditNote,
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

    // Return reduces shop balance
    if (shopId.isNotEmpty) {
      batch.update(db.collection(Collections.customers).doc(shopId), {
        'balance': FieldValue.increment(-total),
        'updated_at': FieldValue.serverTimestamp(),
      });
    }

    // Restore seller inventory
    for (final entry in sellerInventoryRestores.entries) {
      if (entry.value > 0) {
        batch
            .update(db.collection(Collections.sellerInventory).doc(entry.key), {
              'quantity_available': FieldValue.increment(entry.value),
              'updated_at': now,
            });
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
    } // Defense-in-depth: enforce admin-only at app level (rules enforce at DB level)
    final currentUser = ref.read(authUserProvider).value;
    if (currentUser == null || !currentUser.isAdmin) {
      throw StateError('voidInvoice requires admin privileges');
    }
    final db = FirebaseFirestore.instance;
    final invoiceRef = db.collection(Collections.invoices).doc(invoiceId);
    final now = Timestamp.now();

    // Atomic double-void guard: Firestore transaction atomically reads the
    // current status and marks the invoice as voided in one round-trip —
    // prevents two concurrent void calls from both succeeding.
    late final Map<String, dynamic> data;
    await db.runTransaction<void>((txn) async {
      final invSnap = await txn.get(invoiceRef);
      if (!invSnap.exists) {
        throw ArgumentError('Invoice not found: $invoiceId');
      }
      final currentStatus = invSnap.data()?['status'] as String? ?? '';
      if (currentStatus == 'void') {
        throw StateError('Invoice $invoiceId is already voided');
      }
      data = invSnap.data()!;
      txn.update(invoiceRef, {
        'status': InvoiceModel.statusVoid,
        'void_by': createdBy.trim(),
        'void_at': now,
        'void_reason': 'admin_void',
        'updated_at': now,
      });
    });

    // Always read total from the Firestore document — the caller-provided
    // value is used only as a last-resort fallback if the field is missing.
    final docTotal = (data['total'] as num?)?.toDouble() ?? total;
    final amountReceived = (data['amount_received'] as num?)?.toDouble() ?? 0.0;
    final outstandingAmount =
        (data['outstanding_amount'] as num?)?.toDouble() ??
        (docTotal - amountReceived);
    final invoiceNumber = data['invoice_number'] as String? ?? '';
    final routeId = data['route_id'] as String? ?? '';
    final shopId = data['shop_id'] as String? ?? '';
    final shopName = data['shop_name'] as String? ?? '';
    final rawItems = (data['items'] as List<dynamic>?) ?? const [];
    final linkedTransactions = await db
        .collection(Collections.transactions)
        .where('invoice_id', isEqualTo: invoiceId)
        .get();
    // Filter client-side: old docs may not have deleted field
    final activeTxDocs = linkedTransactions.docs
        .where((d) => d.data()['deleted'] != true)
        .toList();

    final batch = db.batch();

    Map<String, dynamic> transactionData({
      required String txType,
      required double amount,
      required String description,
      List<Map<String, dynamic>> items = const <Map<String, dynamic>>[],
      String txShopId = '',
      String txShopName = '',
    }) {
      return {
        'shop_id': txShopId,
        'shop_name': txShopName,
        'route_id': routeId,
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

    // Invoice status already set to void atomically in the transaction above.
    for (final tx in activeTxDocs) {
      batch.update(tx.reference, {
        'deleted': true,
        'deleted_at': now,
        'deleted_by': createdBy.trim(),
        'deleted_reason': 'invoice_voided',
        'updated_at': now,
      });
    }

    if (shopId.isNotEmpty) {
      // BUG-04: Read type from Firestore document, not caller parameter.
      // Prevents wrong-type reversal math if caller passes incorrect type.
      final docType = data['type'] as String? ?? type;
      final reversalDelta = switch (docType) {
        InvoiceModel.typeSale =>
          refundMode == VoidRefundMode.creditBalance
              ? -docTotal
              : -outstandingAmount,
        _ => docTotal,
      };

      batch.update(db.collection(Collections.customers).doc(shopId), {
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
          {'quantity_available': FieldValue.increment(qty), 'updated_at': now},
        );
      }

      if (rawDeductions.isEmpty) {
        _restoreWarehouseStock(batch, db, rawItems, now);
      }

      if (type == InvoiceModel.typeSale) {
        // Write ONE reversal transaction (the live-ledger reversal entry).
        // The soft-deleted originals above already form the complete audit trail.
        final reversalAmount = refundMode == VoidRefundMode.creditBalance
            ? docTotal
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
              txShopId: shopId,
              txShopName: shopName,
            ),
          );
        }
      } else {
        // FC-04: credit_note void — write ONE reversal tx only.
        // A credit note void cancels a previously issued credit; it increases
        // the shop's balance back by docTotal (reversalDelta = +docTotal above).
        // We write 1 'cash_out' tx to record the reversal in the ledger.
        // (The previous double-tx approach wrote both 'return' + 'cash_out'
        // which created a confusing duplicate entry with no clear accounting story.)
        batch.set(
          db.collection(Collections.transactions).doc(),
          transactionData(
            txType: 'cash_out',
            amount: docTotal,
            description: 'Reversed credit note $invoiceNumber',
            items: rawItems.whereType<Map<String, dynamic>>().toList(),
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
  /// FI-06 / BUG-05: Uses Firestore transaction for atomicity — prevents
  /// race condition where two sessions mark-as-paid simultaneously.
  Future<void> markAsPaid({
    required String invoiceId,
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
    final invRef = db.collection(Collections.invoices).doc(invoiceId);

    await db.runTransaction((txn) async {
      final invSnap = await txn.get(invRef);
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

      final invoiceTotal = (invData['total'] as num?)?.toDouble() ?? 0.0;
      final invAmountReceived =
          (invData['amount_received'] as num?)?.toDouble() ?? 0.0;
      final outstanding =
          (invData['outstanding_amount'] as num?)?.toDouble() ??
          (invoiceTotal - invAmountReceived).clamp(0.0, double.infinity);
      final invoiceNumber = invData['invoice_number'] as String? ?? '';
      final shopId = invData['shop_id'] as String? ?? '';
      final shopName = invData['shop_name'] as String? ?? '';
      final now = Timestamp.now();

      // Update invoice: mark paid, zero outstanding
      txn.update(invRef, {
        'status': InvoiceModel.statusPaid,
        'amount_received': FieldValue.increment(
          outstanding > 0 ? outstanding : 0,
        ),
        'outstanding_amount': 0,
        'updated_at': now,
      });

      // Create cash_in transaction for the settled amount
      if (outstanding > 0) {
        final payRef = db.collection(Collections.transactions).doc();
        txn.set(payRef, {
          'shop_id': shopId,
          'shop_name': shopName,
          'route_id': routeId,
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
        if (shopId.isNotEmpty) {
          txn.update(db.collection(Collections.customers).doc(shopId), {
            'balance': FieldValue.increment(-outstanding),
            'updated_at': now,
          });
        }
      }
    });
  }
}

final invoiceNotifierProvider = AsyncNotifierProvider<InvoiceNotifier, void>(
  InvoiceNotifier.new,
);
