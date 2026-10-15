import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/collections.dart';
import '../core/utils/notification_writer.dart';
import '../core/utils/tenant_scope.dart';
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

class VoidInvoiceAccountingPlan {
  final double balanceDelta;
  final double reversalTransactionAmount;
  final double cashRefundAmount;
  final double ledgerDelta;
  final String lastTransactionType;
  final double lastTransactionAmount;

  const VoidInvoiceAccountingPlan({
    required this.balanceDelta,
    required this.reversalTransactionAmount,
    required this.cashRefundAmount,
    required this.ledgerDelta,
    required this.lastTransactionType,
    required this.lastTransactionAmount,
  });
}

VoidInvoiceAccountingPlan buildVoidInvoiceAccountingPlan({
  required String type,
  required double total,
  required double amountReceived,
  required double outstandingAmount,
  required VoidRefundMode refundMode,
}) {
  if (type != InvoiceModel.typeSale) {
    return VoidInvoiceAccountingPlan(
      balanceDelta: total,
      reversalTransactionAmount: total,
      cashRefundAmount: 0,
      ledgerDelta: total,
      lastTransactionType: 'cash_out',
      lastTransactionAmount: total,
    );
  }

  final cashRefundAmount = refundMode == VoidRefundMode.cashRefund
      ? amountReceived
      : 0.0;
  final balanceDelta = refundMode == VoidRefundMode.creditBalance
      ? -total
      : -outstandingAmount;
  return VoidInvoiceAccountingPlan(
    balanceDelta: balanceDelta,
    reversalTransactionAmount: total,
    cashRefundAmount: cashRefundAmount,
    ledgerDelta: -total + cashRefundAmount,
    lastTransactionType: cashRefundAmount > 0 ? 'cash_out' : 'return',
    lastTransactionAmount: cashRefundAmount > 0 ? cashRefundAmount : total,
  );
}

/// Shop-scoped invoice query. Used in ShopDetailScreen invoice sections.
/// For all-invoice listing use [roleAwareInvoicesProvider].
final invoicesByShopProvider = StreamProvider.autoDispose
    .family<List<InvoiceModel>, String>((ref, shopId) {
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
        FirebaseFirestore.instance.collection(Collections.invoices),
        tenantId: tenantId,
      );
      return query
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
  // Use select() so heartbeat writes to last_active do NOT restart the stream.
  final isAdmin = ref.watch(
    authUserProvider.select((s) => s.value?.isAdmin ?? false),
  );
  final tenantId = ref.watch(
    authUserProvider.select((s) => TenantScope.normalize(s.value?.tenantId)),
  );
  if (!isAdmin) return const Stream.empty();
  final query = TenantScope.applyToQuery(
    FirebaseFirestore.instance.collection(Collections.invoices),
    tenantId: tenantId,
  );
  return query
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
      final tenantId = ref.watch(
        authUserProvider.select(
          (s) => TenantScope.normalize(s.value?.tenantId),
        ),
      );
      final query = TenantScope.applyToQuery(
        FirebaseFirestore.instance.collection(Collections.invoices),
        tenantId: tenantId,
      );
      return query
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
      // Use select() with a stable key so heartbeat writes do NOT restart.
      final (isAdmin, userId) = ref.watch(
        authUserProvider.select((s) {
          final u = s.value;
          if (u == null) return (false, '');
          return (u.isAdmin, u.id);
        }),
      );
      if (userId.isEmpty) return const AsyncData(<InvoiceModel>[]);
      if (isAdmin) {
        return ref.watch(allInvoicesProvider);
      }
      return ref.watch(sellerInvoicesProvider(userId));
    });

final invoiceByIdProvider = StreamProvider.autoDispose
    .family<InvoiceModel?, String>((ref, invoiceId) {
      final profileReady = ref.watch(
        authUserProvider.select((s) => s.hasValue && s.value != null),
      );
      if (!profileReady) return const Stream.empty();
      final tenantId = ref.watch(
        authUserProvider.select(
          (s) => TenantScope.normalize(s.value?.tenantId),
        ),
      );
      return FirebaseFirestore.instance
          .collection(Collections.invoices)
          .doc(invoiceId)
          .snapshots()
          .map((doc) {
            if (!doc.exists) return null;
            if (!TenantScope.matchesTenant(doc.data(), tenantId)) return null;
            return InvoiceModel.fromJson(doc.data()!, doc.id);
          });
    });

bool amountReceivedExceedsInvoiceTotal({
  required double amountReceived,
  required double total,
}) => amountReceived > total;

class InvoiceNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<String> _requireTenantId() async {
    final user = await ref.read(authUserProvider.future);
    if (user == null || !user.active) {
      throw StateError('An active user profile is required');
    }
    final tenantId = TenantScope.normalize(user.tenantId);
    if (tenantId == null) {
      throw StateError('A workspace is required for invoice operations');
    }
    return tenantId;
  }

  Map<String, dynamic> _invoiceHeaderSnapshot(Map<String, dynamic>? settings) {
    final header = Map<String, dynamic>.from(
      settings?['invoice_header'] as Map<String, dynamic>? ?? const {},
    );
    header['company_name'] =
        settings?['company_name'] as String? ?? 'My Business';
    final logoBase64 = settings?['logo_base64'];
    if (logoBase64 is String && logoBase64.isNotEmpty) {
      header['logo_base64'] = logoBase64;
    }
    return header;
  }

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

  Future<void> _validateSellerInventoryDeductions({
    required FirebaseFirestore db,
    required Map<String, int> sellerInventoryDeductions,
    required String sellerId,
  }) async {
    final normalizedSellerId = sellerId.trim();
    for (final entry in sellerInventoryDeductions.entries) {
      final inventoryDocId = entry.key.trim();
      final requestedQty = entry.value;
      if (requestedQty <= 0) continue;
      if (inventoryDocId.isEmpty) {
        throw ArgumentError(
          'sellerInventoryDeductions contains an empty document id',
        );
      }

      final inventorySnap = await db
          .collection(Collections.sellerInventory)
          .doc(inventoryDocId)
          .get();
      if (!inventorySnap.exists) {
        throw ArgumentError(
          'Seller inventory document not found: $inventoryDocId',
        );
      }

      final inventoryData = inventorySnap.data()!;
      final availableQty =
          (inventoryData['quantity_available'] as num?)?.toInt() ?? 0;
      if (availableQty < requestedQty) {
        throw ArgumentError(
          'Insufficient seller inventory for $inventoryDocId: '
          'requested $requestedQty, available $availableQty',
        );
      }

      if (normalizedSellerId.isNotEmpty) {
        final ownerSellerId = (inventoryData['seller_id'] as String? ?? '')
            .trim();
        if (ownerSellerId != normalizedSellerId) {
          throw ArgumentError(
            'Seller inventory document $inventoryDocId does not belong '
            'to seller $normalizedSellerId',
          );
        }
      }
    }
  }

  /// Generates the next invoice number: INV-YYYY-NNNN.
  ///
  /// Uses a Firestore transaction on the current tenant's
  /// settings.last_invoice_number so concurrent invoice creation never produces
  /// duplicate numbers.
  Future<String> _nextInvoiceNumber() async {
    final db = FirebaseFirestore.instance;
    final tenantId = TenantScope.requireTenant(
      (await ref.read(authUserProvider.future))?.tenantId,
    );
    final settingsRef = db.collection(Collections.settings).doc(tenantId);
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
  /// - 0: full credit (status: issued)
  /// - > 0 and < total: partial payment (status: partial)
  /// - == total: full payment (status: paid); excess is rejected
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
    String currency = 'SAR',
    Map<String, int> sellerInventoryDeductions = const {},
    String fulfillmentMode = InvoiceModel.fulfillmentStock,
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
    if (routeId.trim().isEmpty) {
      throw ArgumentError('routeId must not be empty');
    }
    if (items.isEmpty) {
      throw ArgumentError('At least one item is required');
    }
    if (fulfillmentMode != InvoiceModel.fulfillmentStock &&
        fulfillmentMode != InvoiceModel.fulfillmentNonStock) {
      throw ArgumentError('Unsupported invoice fulfillment mode');
    }
    if (fulfillmentMode == InvoiceModel.fulfillmentStock &&
        (sellerInventoryDeductions.isEmpty ||
            sellerInventoryDeductions.entries.any(
              (entry) => entry.key.trim().isEmpty || entry.value <= 0,
            ))) {
      throw ArgumentError(
        'A stock sale requires positive seller inventory stock deductions',
      );
    }
    if (fulfillmentMode == InvoiceModel.fulfillmentNonStock &&
        sellerInventoryDeductions.isNotEmpty) {
      throw ArgumentError('A non-stock invoice cannot deduct inventory');
    }
    if (subtotal <= 0) {
      throw ArgumentError('subtotal must be greater than 0');
    }
    if (total <= 0) {
      throw ArgumentError('total must be greater than 0');
    }
    if (discount < 0 || discount > subtotal) {
      throw ArgumentError('discount must be between 0 and subtotal');
    }
    if (amountReceived < 0) {
      throw ArgumentError('amountReceived must not be negative');
    }
    // FI-11: amountReceived cannot exceed the invoice total; doing so would
    // over-credit the customer and corrupt the ledger.
    if (amountReceivedExceedsInvoiceTotal(
      amountReceived: amountReceived,
      total: total,
    )) {
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
    final tenantId = await _requireTenantId();
    final settingsSnapshot = await db
        .collection(Collections.settings)
        .doc(tenantId)
        .get();
    final settingsData = settingsSnapshot.data();
    if (fulfillmentMode == InvoiceModel.fulfillmentNonStock &&
        settingsData?['allow_non_stock_invoices'] == false) {
      throw StateError('Non-stock invoices are disabled for this workspace');
    }
    final invoiceHeaderSnapshot = _invoiceHeaderSnapshot(settingsData);
    final resolvedKey = idempotencyKey ?? const Uuid().v4();
    if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
      final existing = await db
          .collection(Collections.invoices)
          .where('tenant_id', isEqualTo: tenantId)
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

    if (fulfillmentMode == InvoiceModel.fulfillmentStock) {
      await _validateSellerInventoryDeductions(
        db: db,
        sellerInventoryDeductions: sellerInventoryDeductions,
        sellerId: sellerId,
      );
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
    final paymentTxRef = amountReceived > 0
        ? db.collection(Collections.transactions).doc()
        : null;

    // Create invoice doc
    final invRef = db.collection(Collections.invoices).doc();
    batch.set(invRef, {
      'tenant_id': tenantId,
      'invoice_number': invoiceNumber,
      'idempotency_key': resolvedKey,
      'type': InvoiceModel.typeSale,
      'fulfillment_mode': fulfillmentMode,
      'invoice_header_snapshot': invoiceHeaderSnapshot,
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
      if (paymentTxRef != null) 'payment_transaction_id': paymentTxRef.id,
      'outstanding_amount': total - amountReceived,
      'currency': currency,
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
      'tenant_id': tenantId,
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
    if (paymentTxRef != null) {
      batch.set(paymentTxRef, {
        'tenant_id': tenantId,
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

    // Customer balance increases by the unpaid portion of this sale.
    if (shopId.isNotEmpty) {
      final balanceDelta = total - amountReceived;
      batch.update(db.collection(Collections.shops).doc(shopId), {
        'balance': FieldValue.increment(balanceDelta),
        'updated_at':
            FieldValue.serverTimestamp(), // server time avoids withinWriteRate skew
        'last_transaction_at': FieldValue.serverTimestamp(),
        'last_transaction_type': 'cash_out',
        'last_transaction_amount': total,
        'last_transaction_id': txRef.id,
      });
    }

    // Deduct seller inventory if applicable
    for (final entry in sellerInventoryDeductions.entries) {
      if (entry.value > 0) {
        batch
            .update(db.collection(Collections.sellerInventory).doc(entry.key), {
              'quantity_available': FieldValue.increment(-entry.value),
              'updated_at': now,
              'last_sale_invoice_id': invRef.id,
            });
      }
    }

    await batch.commit();

    // Best-effort notification for admin feed (non-critical, fire-and-forget).
    // P1-10 FIX: Include tenant_id to prevent cross-tenant leakage.
    try {
      final appUser = await ref.read(authUserProvider.future);
      if (appUser != null && appUser.isSeller) {
        await writeRateLimitedNotification(
          db: db,
          actorUid: appUser.id,
          data: {
            'type': 'invoice',
            'shop_id': shopId,
            'shop_name': shopName,
            'route_id': routeId,
            'seller_id': normalizedCreatedBy,
            'seller_name': appUser.displayName,
            'amount': total,
            'transaction_type': 'cash_out',
            'invoice_number': invoiceNumber,
            'ref_id': invRef.id,
            'target_role': 'admin',
            'read': false,
            'tenant_id': appUser.tenantId,
          },
        );
      }
    } catch (_) {
      /* best-effort only — non-critical */
    }
    return invRef.id;
  }

  Future<String> createCashReceipt({
    required String shopId,
    required String shopName,
    required String routeId,
    required String sellerId,
    required String sellerName,
    required double amount,
    required String createdBy,
    required String currency,
    String? notes,
    String? paymentMethod,
    String? referenceNumber,
    String? idempotencyKey,
  }) async {
    final normalizedCreatedBy = createdBy.trim();
    final normalizedShopId = shopId.trim();
    final normalizedRouteId = routeId.trim();
    if (normalizedCreatedBy.isEmpty) {
      throw ArgumentError('createdBy must not be empty');
    }
    if (normalizedShopId.isEmpty || normalizedRouteId.isEmpty) {
      throw ArgumentError('shopId and routeId must not be empty');
    }
    if (amount <= 0 || amount > 999999.99) {
      throw ArgumentError(
        'Receipt amount must be greater than 0 and <= 999999.99',
      );
    }
    final normalizedSellerId = sellerId.trim();
    if (normalizedSellerId.isEmpty) {
      throw ArgumentError('sellerId must not be empty');
    }
    final tenantId = await _requireTenantId();
    final normalizedKey = idempotencyKey?.trim();
    final resolvedKey = normalizedKey == null || normalizedKey.isEmpty
        ? const Uuid().v4()
        : normalizedKey;
    final receiptId = const Uuid().v5(
      Namespace.url.value,
      '$tenantId:cash-receipt:$resolvedKey',
    );
    final db = FirebaseFirestore.instance;
    final settingsRef = db.collection(Collections.settings).doc(tenantId);
    final shopRef = db.collection(Collections.shops).doc(normalizedShopId);
    final invoiceRef = db.collection(Collections.invoices).doc(receiptId);
    final transactionRef = db.collection(Collections.transactions).doc();
    final now = Timestamp.now();

    return db.runTransaction<String>((transaction) async {
      final settingsSnapshot = await transaction.get(settingsRef);
      final shopSnapshot = await transaction.get(shopRef);
      final invoiceSnapshot = await transaction.get(invoiceRef);
      if (invoiceSnapshot.exists) {
        final existingData = invoiceSnapshot.data()!;
        if (existingData['idempotency_key'] == resolvedKey &&
            existingData['type'] == InvoiceModel.typeCashReceipt &&
            existingData['shop_id'] == normalizedShopId &&
            (existingData['total'] as num?)?.toDouble() == amount) {
          return invoiceRef.id;
        }
        throw StateError('Cash receipt idempotency key was reused');
      }
      if (!settingsSnapshot.exists) {
        throw StateError(
          'Workspace settings are required for receipt numbering',
        );
      }
      if (!shopSnapshot.exists ||
          shopSnapshot.data()?['tenant_id'] != tenantId ||
          shopSnapshot.data()?['route_id'] != normalizedRouteId) {
        throw ArgumentError('Shop does not belong to this workspace and route');
      }

      final nextNumber =
          ((settingsSnapshot.data()?['last_cash_receipt_number'] as num?)
                  ?.toInt() ??
              0) +
          1;
      final receiptNumber =
          'REC-${now.toDate().year}-${nextNumber.toString().padLeft(4, '0')}';
      final balanceBefore =
          (shopSnapshot.data()?['balance'] as num?)?.toDouble() ?? 0;
      final balanceAfter = balanceBefore - amount;
      final cleanedMethod = paymentMethod?.trim();
      final cleanedReference = referenceNumber?.trim();
      final invoiceHeaderSnapshot = _invoiceHeaderSnapshot(
        settingsSnapshot.data(),
      );

      transaction.update(settingsRef, {'last_cash_receipt_number': nextNumber});
      transaction.set(invoiceRef, {
        'tenant_id': tenantId,
        'invoice_number': receiptNumber,
        'idempotency_key': resolvedKey,
        'type': InvoiceModel.typeCashReceipt,
        'fulfillment_mode': 'none',
        'invoice_header_snapshot': invoiceHeaderSnapshot,
        'cash_receipt_sequence': nextNumber,
        'shop_id': normalizedShopId,
        'shop_name': shopName,
        'route_id': normalizedRouteId,
        'seller_id': normalizedSellerId,
        'seller_name': sellerName,
        'items': <Map<String, dynamic>>[],
        'subtotal': 0,
        'discount': 0,
        'total': amount,
        'amount_received': amount,
        'outstanding_amount': 0,
        'shop_balance_before': balanceBefore,
        'shop_balance_after': balanceAfter,
        'currency': currency,
        'sale_type': 'cash',
        'status': InvoiceModel.statusPaid,
        'notes': notes,
        if (cleanedMethod != null && cleanedMethod.isNotEmpty)
          'payment_method': cleanedMethod,
        if (cleanedReference != null && cleanedReference.isNotEmpty)
          'payment_reference': cleanedReference,
        'cash_receipt_transaction_id': transactionRef.id,
        'created_by': normalizedCreatedBy,
        'created_at': now,
        'updated_at': now,
      });
      transaction.set(transactionRef, {
        'tenant_id': tenantId,
        'shop_id': normalizedShopId,
        'shop_name': shopName,
        'route_id': normalizedRouteId,
        'type': 'cash_in',
        'sale_type': 'cash',
        'amount': amount,
        'description': 'Cash receipt $receiptNumber',
        'items': <Map<String, dynamic>>[],
        'invoice_id': receiptId,
        'invoice_number': receiptNumber,
        'created_by': normalizedCreatedBy,
        'created_at': now,
        'deleted': false,
      });
      transaction.update(shopRef, {
        'balance': FieldValue.increment(-amount),
        'updated_at': now,
        'last_transaction_at': now,
        'last_transaction_type': 'cash_in',
        'last_transaction_amount': amount,
        'last_transaction_id': transactionRef.id,
      });
      return receiptId;
    });
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
    if (routeId.trim().isEmpty) {
      throw ArgumentError('routeId must not be empty');
    }
    if (items.isEmpty) {
      throw ArgumentError('At least one item is required');
    }
    if (subtotal <= 0) {
      throw ArgumentError('subtotal must be greater than 0');
    }
    if (total <= 0) {
      throw ArgumentError('total must be greater than 0');
    }
    final normalizedLinkedInvoiceId = linkedInvoiceId?.trim();
    if (normalizedLinkedInvoiceId == null ||
        normalizedLinkedInvoiceId.isEmpty) {
      throw ArgumentError('linkedInvoiceId must not be empty');
    }

    final db = FirebaseFirestore.instance;
    final tenantId = await _requireTenantId();
    // I-12: validate the original sale and enforce cumulative credit limits.
    final origSnap = await db
        .collection(Collections.invoices)
        .doc(normalizedLinkedInvoiceId)
        .get();
    if (!origSnap.exists) {
      throw ArgumentError('Original invoice does not exist');
    }
    final original = origSnap.data()!;
    if (original['tenant_id'] != tenantId ||
        original['shop_id'] != shopId ||
        original['type'] != InvoiceModel.typeSale) {
      throw ArgumentError(
        'Original invoice does not match this shop and workspace',
      );
    }
    if (original['status'] == InvoiceModel.statusVoid) {
      throw ArgumentError(
        'Cannot create a credit note against a voided invoice',
      );
    }
    final originalCreatedAt = original['created_at'] as Timestamp?;
    if (originalCreatedAt == null) {
      throw ArgumentError('Original invoice has no creation timestamp');
    }
    final ageInDays = DateTime.now()
        .difference(originalCreatedAt.toDate())
        .inDays;
    if (ageInDays > 30) {
      throw ArgumentError(
        'Credit notes must be created within 30 days of the original invoice',
      );
    }

    final normalizedKey = idempotencyKey?.trim();
    final resolvedKey = (normalizedKey != null && normalizedKey.isNotEmpty)
        ? normalizedKey
        : const Uuid().v4();
    if (normalizedKey != null && normalizedKey.isNotEmpty) {
      final existing = await db
          .collection(Collections.invoices)
          .where('tenant_id', isEqualTo: tenantId)
          .where('idempotency_key', isEqualTo: normalizedKey)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        return existing.docs.first.id;
      }
    }

    final creditedTotal =
        (original['credit_note_total'] as num?)?.toDouble() ?? 0;
    final originalTotal = (original['total'] as num?)?.toDouble() ?? 0;
    if (creditedTotal + total > originalTotal + 0.01) {
      throw ArgumentError(
        'Credit notes cannot exceed the original invoice total',
      );
    }

    final invoiceNumber = await _nextInvoiceNumber();
    final batch = db.batch();
    final now = Timestamp.now();

    batch.update(origSnap.reference, {
      'credit_note_total': FieldValue.increment(total),
      'updated_at': FieldValue.serverTimestamp(),
    });

    final invRef = db.collection(Collections.invoices).doc();
    batch.set(invRef, {
      'tenant_id': tenantId,
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
      'linked_invoice_id': normalizedLinkedInvoiceId,
      'created_by': normalizedCreatedBy,
      'created_at': now,
      'updated_at': now,
    });

    // Create return transaction
    final txRef = db.collection(Collections.transactions).doc();
    batch.set(txRef, {
      'tenant_id': tenantId,
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
      batch.update(db.collection(Collections.shops).doc(shopId), {
        'balance': FieldValue.increment(-total),
        'updated_at': FieldValue.serverTimestamp(),
        'last_transaction_at': FieldValue.serverTimestamp(),
        'last_transaction_type': 'return',
        'last_transaction_amount': total,
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

    // Best-effort notification for admin feed (non-critical, fire-and-forget).
    // P1-10 FIX: Include tenant_id to prevent cross-tenant leakage.
    try {
      final appUser = await ref.read(authUserProvider.future);
      if (appUser != null && appUser.isSeller) {
        await writeRateLimitedNotification(
          db: db,
          actorUid: appUser.id,
          data: {
            'type': 'invoice',
            'shop_id': shopId,
            'shop_name': shopName,
            'route_id': routeId,
            'seller_id': normalizedCreatedBy,
            'seller_name': appUser.displayName,
            'amount': total,
            'transaction_type': 'return',
            'invoice_number': invoiceNumber,
            'ref_id': invRef.id,
            'target_role': 'admin',
            'read': false,
            'tenant_id': appUser.tenantId,
          },
        );
      }
    } catch (_) {
      /* best-effort only — non-critical */
    }
    return invRef.id;
  }

  /// Voids an invoice â€” admin only, reverses balance impact.
  ///
  /// Original invoice-linked transactions remain visible for auditability.
  /// We append explicit reversal entries so transaction-derived ledgers stay
  /// aligned with `shop.balance` after a void.
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
    final currentUser = await ref.read(authUserProvider.future);
    if (currentUser == null || !currentUser.active || !currentUser.isAdmin) {
      throw StateError('voidInvoice requires admin privileges');
    }
    if (createdBy.trim() != currentUser.id) {
      throw StateError('createdBy must match the authenticated administrator');
    }
    final tenantId = await _requireTenantId();
    final db = FirebaseFirestore.instance;
    final invoiceRef = db.collection(Collections.invoices).doc(invoiceId);
    final now = Timestamp.now();
    final transactions = db.collection(Collections.transactions);

    await db.runTransaction<void>((transaction) async {
      final invSnap = await transaction.get(invoiceRef);
      if (!invSnap.exists) {
        throw ArgumentError('Invoice not found: $invoiceId');
      }
      final data = invSnap.data()!;
      final currentStatus = data['status'] as String? ?? '';
      if (currentStatus == 'void') {
        throw StateError('Invoice $invoiceId is already voided');
      }
      final invoiceTenantId = (data['tenant_id'] as String?)?.trim();
      if (invoiceTenantId != null &&
          invoiceTenantId.isNotEmpty &&
          invoiceTenantId != tenantId) {
        throw StateError('Invoice belongs to another workspace');
      }
      final effectiveTenantId = invoiceTenantId?.isNotEmpty == true
          ? invoiceTenantId!
          : tenantId;
      final docTotal = (data['total'] as num?)?.toDouble() ?? total;
      final amountReceived =
          (data['amount_received'] as num?)?.toDouble() ?? 0.0;
      final outstandingAmount =
          (data['outstanding_amount'] as num?)?.toDouble() ??
          (docTotal - amountReceived);
      final docType = data['type'] as String? ?? type;
      final invoiceNumber = data['invoice_number'] as String? ?? '';
      final routeId = data['route_id'] as String? ?? '';
      final shopId = (data['shop_id'] as String? ?? '').trim();
      final shopName = data['shop_name'] as String? ?? '';
      final rawItems = (data['items'] as List<dynamic>?) ?? const [];
      final rawDeductions =
          (data['seller_inventory_deductions'] as Map<String, dynamic>?) ??
          const <String, dynamic>{};
      final accountingPlan = buildVoidInvoiceAccountingPlan(
        type: docType,
        total: docTotal,
        amountReceived: amountReceived,
        outstandingAmount: outstandingAmount,
        refundMode: refundMode,
      );
      final invoice = InvoiceModel.fromJson(data, invoiceId);
      final shopRef = shopId.isEmpty
          ? null
          : db.collection(Collections.shops).doc(shopId);
      final sellerInventoryRefs =
          <String, DocumentReference<Map<String, dynamic>>>{};
      for (final entry in rawDeductions.entries) {
        final quantity = (entry.value as num?)?.toInt() ?? 0;
        final inventoryId = entry.key.trim();
        if (quantity > 0) {
          if (inventoryId.isEmpty) {
            throw StateError('Invalid seller inventory deduction reference');
          }
          sellerInventoryRefs[inventoryId] = db
              .collection(Collections.sellerInventory)
              .doc(inventoryId);
        }
      }
      final warehouseVariantIds = <String>{};
      if (shopRef != null &&
          sellerInventoryRefs.isEmpty &&
          !invoice.isNonStockSale) {
        for (final item in rawItems.whereType<Map<String, dynamic>>()) {
          final variantId = (item['variant_id'] as String?)?.trim() ?? '';
          if (variantId.isNotEmpty) warehouseVariantIds.add(variantId);
        }
      }
      final warehouseVariantRefs = {
        for (final variantId in warehouseVariantIds)
          variantId: db.collection(Collections.productVariants).doc(variantId),
      };
      final refsToRead = <DocumentReference<Map<String, dynamic>>>[
        ?shopRef,
        ...sellerInventoryRefs.values,
        ...warehouseVariantRefs.values,
      ];
      final snapshots = await Future.wait(refsToRead.map(transaction.get));
      var snapshotIndex = 0;
      if (shopRef != null) {
        final shopSnapshot = snapshots[snapshotIndex++];
        if (!shopSnapshot.exists ||
            shopSnapshot.data()?['tenant_id'] != tenantId) {
          throw StateError('Invoice shop is unavailable in this workspace');
        }
      }
      for (var index = 0; index < sellerInventoryRefs.length; index++) {
        final snapshot = snapshots[snapshotIndex++];
        if (!snapshot.exists || snapshot.data()?['tenant_id'] != tenantId) {
          throw StateError('Invoice seller inventory is unavailable');
        }
      }
      for (var index = 0; index < warehouseVariantRefs.length; index++) {
        final snapshot = snapshots[snapshotIndex++];
        if (!snapshot.exists || snapshot.data()?['tenant_id'] != tenantId) {
          throw StateError('Invoice warehouse stock is unavailable');
        }
      }

      final reversalTransactionRef = shopRef == null || docTotal <= 0
          ? null
          : transactions.doc();
      final refundTransactionRef =
          shopRef == null || accountingPlan.cashRefundAmount <= 0
          ? null
          : transactions.doc();
      final lastTransactionRef = refundTransactionRef ?? reversalTransactionRef;

      Map<String, dynamic> transactionData({
        required String txType,
        required double amount,
        required String description,
        List<Map<String, dynamic>> items = const <Map<String, dynamic>>[],
      }) => {
        'tenant_id': effectiveTenantId,
        'shop_id': shopId,
        'shop_name': shopName,
        'route_id': routeId,
        'type': txType,
        'sale_type': docType == InvoiceModel.typeSale ? 'credit' : 'return',
        'amount': amount,
        'description': description,
        'items': items,
        'invoice_id': invoiceId,
        'invoice_number': invoiceNumber,
        'created_by': currentUser.id,
        'created_at': now,
        'deleted': false,
      };

      transaction.update(invoiceRef, {
        'status': InvoiceModel.statusVoid,
        'void_by': currentUser.id,
        'void_at': now,
        'void_reason': 'admin_void',
        'updated_at': now,
      });

      if (shopRef != null) {
        transaction.update(shopRef, {
          'balance': FieldValue.increment(accountingPlan.balanceDelta),
          'updated_at': now,
          'last_transaction_at': now,
          'last_transaction_type': accountingPlan.lastTransactionType,
          'last_transaction_amount': accountingPlan.lastTransactionAmount,
          'last_transaction_id': ?lastTransactionRef?.id,
        });
        for (final entry in sellerInventoryRefs.entries) {
          final quantity = (rawDeductions[entry.key] as num?)?.toInt() ?? 0;
          transaction.update(entry.value, {
            'quantity_available': FieldValue.increment(quantity),
            'updated_at': now,
          });
        }
        for (final item in rawItems.whereType<Map<String, dynamic>>()) {
          final variantId = (item['variant_id'] as String?)?.trim() ?? '';
          final quantity = (item['qty'] as num?)?.toInt() ?? 0;
          final variantRef = warehouseVariantRefs[variantId];
          if (variantRef == null || quantity <= 0) continue;
          transaction.update(variantRef, {
            'quantity_available': FieldValue.increment(quantity),
            'updated_at': now,
          });
        }
        if (docType == InvoiceModel.typeSale) {
          if (reversalTransactionRef != null) {
            transaction.set(
              reversalTransactionRef,
              transactionData(
                txType: 'return',
                amount: accountingPlan.reversalTransactionAmount,
                description: refundMode == VoidRefundMode.creditBalance
                    ? 'Credit for voided invoice $invoiceNumber'
                    : 'Full reversal for voided invoice $invoiceNumber',
              ),
            );
          }
          if (refundTransactionRef != null) {
            transaction.set(
              refundTransactionRef,
              transactionData(
                txType: 'cash_out',
                amount: accountingPlan.cashRefundAmount,
                description: 'Cash refund for voided invoice $invoiceNumber',
              ),
            );
          }
        } else if (reversalTransactionRef != null) {
          transaction.set(
            reversalTransactionRef,
            transactionData(
              txType: 'cash_out',
              amount: accountingPlan.reversalTransactionAmount,
              description: 'Reversed invoice $invoiceNumber',
              items: rawItems.whereType<Map<String, dynamic>>().toList(),
            ),
          );
        }
      }
    });
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
    final currentUser = await ref.read(authUserProvider.future);
    if (currentUser == null || !currentUser.isAdmin) {
      throw StateError('markAsPaid requires admin privileges');
    }
    final tenantId = await _requireTenantId();
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
      final storedOutstanding = (invData['outstanding_amount'] as num?)
          ?.toDouble();
      if (storedOutstanding != null && storedOutstanding < 0) {
        throw StateError(
          'Invoice $invoiceId has a negative outstanding_amount '
          '($storedOutstanding)',
        );
      }
      final computedOutstanding = invoiceTotal - invAmountReceived;
      if (storedOutstanding == null && computedOutstanding < 0) {
        throw StateError(
          'Invoice $invoiceId is overpaid: total $invoiceTotal, '
          'received $invAmountReceived',
        );
      }
      final outstanding = storedOutstanding ?? computedOutstanding;
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
          'tenant_id': tenantId,
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
          txn.update(db.collection(Collections.shops).doc(shopId), {
            'balance': FieldValue.increment(-outstanding),
            'updated_at': now,
            'last_transaction_at': now,
            'last_transaction_type': 'cash_in',
            'last_transaction_amount': outstanding,
          });
        }
      }
    });
  }
}

final invoiceNotifierProvider = AsyncNotifierProvider<InvoiceNotifier, void>(
  InvoiceNotifier.new,
);
