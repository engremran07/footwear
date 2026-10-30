import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/constants/collections.dart';
import '../core/utils/formatters.dart';
import '../core/utils/financial_amount_policy.dart';
import '../core/utils/financial_minor_unit_migration.dart';
import '../core/utils/firestore_pagination.dart';
import '../core/utils/invoice_numbering.dart';
import '../core/utils/notification_writer.dart';
import '../core/utils/permission_policy.dart';
import '../core/utils/role_names.dart';
import '../core/utils/tenant_scope.dart';
import '../models/invoice_model.dart';
import '../models/user_model.dart';
import 'auth_provider.dart';

final _logger = Logger();
const _maxCreditNotesForQuantityReconstruction = 50;

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
//       └ atomic: marks invoice void, hides linked txs, reverses balance
//
// PARAMETER NOTE:
//   createSaleInvoice / createReturnInvoice use shopId/shopName as sole
//   identifiers. Ledger rows also dual-write customer_id for legacy readers.
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

bool shouldPreserveInvoicePaymentAsCustomerCredit({
  required String invoiceId,
  required String invoiceType,
  required VoidRefundMode refundMode,
  required Map<String, dynamic> transactionData,
}) {
  final amount = (transactionData['amount'] as num?)?.toDouble() ?? 0;
  return invoiceType == InvoiceModel.typeSale &&
      refundMode == VoidRefundMode.creditBalance &&
      transactionData['invoice_id'] == invoiceId &&
      transactionData['type'] == 'cash_in' &&
      amount > 0;
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
    authUserProvider.select((s) => s.value?.canManageOperationalData ?? false),
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
          return (u.canManageOperationalData, u.id);
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

void validateInvoiceItems(List<Map<String, dynamic>> items) {
  for (var index = 0; index < items.length; index++) {
    final item = items[index];
    final variantId = (item['variant_id'] as String?)?.trim() ?? '';
    final quantity = item['qty'];
    final unitPrice = item['unit_price'];
    if (variantId.isEmpty) {
      throw ArgumentError('Item $index must have a variant_id');
    }
    if (quantity is! num ||
        !quantity.isFinite ||
        quantity <= 0 ||
        quantity % 1 != 0) {
      throw ArgumentError('Item $index quantity must be a positive integer');
    }
    if (unitPrice is! num ||
        !unitPrice.isFinite ||
        unitPrice < 0 ||
        !AppFormatters.hasAtMostTwoDecimalPlaces(unitPrice.toDouble())) {
      throw ArgumentError('Item $index must have a valid unit_price');
    }
  }
}

Map<String, int> invoiceQuantitiesByVariant(List<Map<String, dynamic>> items) {
  final quantities = <String, int>{};
  for (var index = 0; index < items.length; index++) {
    final item = items[index];
    final variantId = (item['variant_id'] as String?)?.trim() ?? '';
    final quantity = item['qty'];
    if (variantId.isEmpty ||
        quantity is! num ||
        !quantity.isFinite ||
        quantity <= 0 ||
        quantity % 1 != 0) {
      throw StateError('Invoice item $index has invalid variant quantity data');
    }
    quantities.update(
      variantId,
      (current) => current + quantity.toInt(),
      ifAbsent: () => quantity.toInt(),
    );
  }
  return quantities;
}

bool sellerInventoryDeductionsMatchInvoiceItems({
  required List<Map<String, dynamic>> items,
  required Map<String, int> deductions,
  required Map<String, String> inventoryVariantIds,
  required int pairsPerCarton,
}) {
  if (pairsPerCarton <= 0 || deductions.isEmpty) return false;
  final expectedPairsByVariant = <String, int>{};
  for (final item in items) {
    final variantId = (item['variant_id'] as String?)?.trim() ?? '';
    final quantity = item['qty'];
    final extraPairs = item['extra_pairs'] ?? 0;
    if (variantId.isEmpty ||
        quantity is! num ||
        !quantity.isFinite ||
        quantity <= 0 ||
        quantity % 1 != 0 ||
        extraPairs is! num ||
        !extraPairs.isFinite ||
        extraPairs < 0 ||
        extraPairs >= pairsPerCarton ||
        extraPairs % 1 != 0) {
      return false;
    }
    expectedPairsByVariant.update(
      variantId,
      (current) =>
          current + quantity.toInt() * pairsPerCarton + extraPairs.toInt(),
      ifAbsent: () => quantity.toInt() * pairsPerCarton + extraPairs.toInt(),
    );
  }

  final deductedPairsByVariant = <String, int>{};
  for (final entry in deductions.entries) {
    final variantId = inventoryVariantIds[entry.key]?.trim() ?? '';
    if (entry.key.trim().isEmpty || entry.value <= 0 || variantId.isEmpty) {
      return false;
    }
    deductedPairsByVariant.update(
      variantId,
      (current) => current + entry.value,
      ifAbsent: () => entry.value,
    );
  }
  if (expectedPairsByVariant.length != deductedPairsByVariant.length) {
    return false;
  }
  return expectedPairsByVariant.entries.every(
    (entry) => deductedPairsByVariant[entry.key] == entry.value,
  );
}

Map<String, int> creditNoteQuantitiesAfter({
  required Map<String, int> soldQuantities,
  required Map<String, int> previouslyCreditedQuantities,
  required Map<String, int> requestedQuantities,
}) {
  for (final entry in previouslyCreditedQuantities.entries) {
    final sold = soldQuantities[entry.key];
    if (sold == null || entry.value <= 0 || entry.value > sold) {
      throw StateError('Existing credit-note quantities exceed the sale');
    }
  }

  final updated = Map<String, int>.from(previouslyCreditedQuantities);
  for (final entry in requestedQuantities.entries) {
    final sold = soldQuantities[entry.key];
    if (sold == null || entry.value <= 0) {
      throw ArgumentError(
        'Credit note contains an item not sold on the invoice',
      );
    }
    final totalCredited = (updated[entry.key] ?? 0) + entry.value;
    if (totalCredited > sold) {
      throw ArgumentError(
        'Credit-note quantities cannot exceed quantities on the original sale',
      );
    }
    updated[entry.key] = totalCredited;
  }
  return updated;
}

List<Map<String, dynamic>> _invoiceItemMapsFromStored(Object? rawItems) {
  if (rawItems is! List) {
    throw StateError('Invoice quantity history is unavailable');
  }
  return rawItems.map((rawItem) {
    if (rawItem is! Map) {
      throw StateError('Invoice quantity history contains an invalid item');
    }
    return Map<String, dynamic>.from(rawItem);
  }).toList();
}

Map<String, int> reconstructCreditNoteQuantities({
  required Map<String, int> soldQuantities,
  required List<Map<String, dynamic>> existingCreditNotes,
  int maxCreditNotes = _maxCreditNotesForQuantityReconstruction,
}) {
  if (existingCreditNotes.length > maxCreditNotes) {
    throw StateError(
      'Credit-note history exceeds the safe reconstruction limit',
    );
  }
  var creditedQuantities = <String, int>{};
  for (final creditNote in existingCreditNotes) {
    if (creditNote['type'] != InvoiceModel.typeCreditNote ||
        creditNote['status'] == InvoiceModel.statusVoid) {
      continue;
    }
    creditedQuantities = creditNoteQuantitiesAfter(
      soldQuantities: soldQuantities,
      previouslyCreditedQuantities: creditedQuantities,
      requestedQuantities: invoiceQuantitiesByVariant(
        _invoiceItemMapsFromStored(creditNote['items']),
      ),
    );
  }
  return creditedQuantities;
}

bool sellerInventoryRestoresWithinOriginalSale({
  required Object? originalDeductions,
  required List<Map<String, dynamic>> existingCreditNotes,
  required Map<String, int> requestedRestores,
}) {
  Map<String, int>? parseQuantities(Object? raw) {
    if (raw == null) return <String, int>{};
    if (raw is! Map) return null;
    final quantities = <String, int>{};
    for (final entry in raw.entries) {
      final inventoryId = entry.key;
      final quantity = entry.value;
      if (inventoryId is! String ||
          inventoryId.trim().isEmpty ||
          quantity is! num ||
          !quantity.isFinite ||
          quantity <= 0 ||
          quantity % 1 != 0) {
        return null;
      }
      quantities[inventoryId] = quantity.toInt();
    }
    return quantities;
  }

  final original = parseQuantities(originalDeductions);
  if (original == null) return false;
  final restored = <String, int>{};
  for (final creditNote in existingCreditNotes) {
    if (creditNote['type'] != InvoiceModel.typeCreditNote ||
        creditNote['status'] == InvoiceModel.statusVoid) {
      continue;
    }
    final rawRestores = creditNote['seller_inventory_restores'];
    if (original.isNotEmpty && rawRestores == null) return false;
    final previous = parseQuantities(rawRestores);
    if (previous == null) return false;
    for (final entry in previous.entries) {
      if (!original.containsKey(entry.key)) return false;
      restored.update(
        entry.key,
        (current) => current + entry.value,
        ifAbsent: () => entry.value,
      );
    }
  }
  final requested = parseQuantities(requestedRestores);
  if (requested == null) return false;
  for (final entry in requested.entries) {
    if (!original.containsKey(entry.key)) return false;
    restored.update(
      entry.key,
      (current) => current + entry.value,
      ifAbsent: () => entry.value,
    );
  }
  return restored.entries.every(
    (entry) => entry.value <= (original[entry.key] ?? 0),
  );
}

bool isCreditNoteWithin30DayWindow({
  required DateTime invoiceCreatedAt,
  required DateTime now,
}) =>
    !invoiceCreatedAt.isAfter(now) &&
    now.difference(invoiceCreatedAt) <= const Duration(days: 30);

class InvoiceNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<({UserModel user, String tenantId})> _requireInvoiceAccess({
    required AppCapability capability,
    required String actorId,
  }) async {
    final activeUser = await ref.read(authUserProvider.future);
    if (activeUser == null || !activeUser.active) {
      throw StateError('An active user profile is required');
    }
    final tenantId = TenantScope.normalize(activeUser.tenantId);
    if (tenantId == null) {
      throw StateError('A workspace is required for invoice operations');
    }
    if (actorId.trim() != activeUser.id) {
      throw StateError('Invoice actor must match the authenticated user');
    }
    if (!PermissionPolicy.can(activeUser, capability, tenantId: tenantId)) {
      throw StateError('User is not authorized for this invoice operation');
    }
    return (user: activeUser, tenantId: tenantId);
  }

  Map<String, dynamic> _invoiceHeaderSnapshot(Map<String, dynamic>? settings) {
    final header = Map<String, dynamic>.from(
      settings?['invoice_header'] as Map<String, dynamic>? ?? const {},
    );
    final legacyName = settings?['company_name'] as String? ?? '';
    if (legacyName.trim().isNotEmpty) {
      header['company_name'] = legacyName;
    }
    final logoBase64 = settings?['logo_base64'];
    if (logoBase64 is String && logoBase64.isNotEmpty) {
      header['logo_base64'] = logoBase64;
    }
    return header;
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
    String? idempotencyKey, // optional: pass a stable UUID to prevent duplicates on retry
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
    validateInvoiceItems(items);
    if (![
      subtotal,
      discount,
      total,
      amountReceived,
    ].every(AppFormatters.hasAtMostTwoDecimalPlaces)) {
      throw ArgumentError(
        'Invoice amounts may have at most two decimal places',
      );
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
    if (!FinancialAmountPolicy.accepts(total, currency: currency) ||
        subtotal > FinancialAmountPolicy.maximumForCurrency(currency) ||
        discount > FinancialAmountPolicy.maximumForCurrency(currency) ||
        amountReceived > FinancialAmountPolicy.maximumForCurrency(currency)) {
      throw ArgumentError(
        'Invoice amounts exceed the maximum allowed amount '
        '(${FinancialAmountPolicy.maximumForCurrency(currency).toStringAsFixed(2)} $currency)',
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

    final db = FirebaseFirestore.instance;
    final invoiceAccess = await _requireInvoiceAccess(
      capability: AppCapability.createInvoice,
      actorId: normalizedCreatedBy,
    );
    final tenantId = invoiceAccess.tenantId;
    final normalizedKey = idempotencyKey?.trim();
    final resolvedKey = normalizedKey == null || normalizedKey.isEmpty
        ? const Uuid().v4()
        : normalizedKey;
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

    final settingsRef = db.collection(Collections.settings).doc(tenantId);
    final shopRef = db.collection(Collections.shops).doc(shopId);
    final invoiceId = const Uuid().v5(
      Namespace.url.value,
      '$tenantId:sale:$resolvedKey',
    );
    final invRef = db.collection(Collections.invoices).doc(invoiceId);
    final paymentTxRef = amountReceived > 0
        ? db.collection(Collections.transactions).doc()
        : null;
    final txRef = db.collection(Collections.transactions).doc();
    final inventoryRefs = <String, DocumentReference<Map<String, dynamic>>>{
      for (final entry in sellerInventoryDeductions.entries)
        if (entry.value > 0)
          entry.key: db.collection(Collections.sellerInventory).doc(entry.key),
    };
    final result = await db.runTransaction<({String invoiceNumber, bool created})>((
      transaction,
    ) async {
      final settingsSnapshot = await transaction.get(settingsRef);
      final invoiceSnapshot = await transaction.get(invRef);
      if (invoiceSnapshot.exists) {
        final existing = invoiceSnapshot.data()!;
        if (existing['tenant_id'] == tenantId &&
            existing['idempotency_key'] == resolvedKey &&
            existing['type'] == InvoiceModel.typeSale &&
            existing['shop_id'] == shopId &&
            (existing['total'] as num?)?.toDouble() == total) {
          return (
            invoiceNumber: existing['invoice_number'] as String? ?? '',
            created: false,
          );
        }
        throw StateError('Sale invoice idempotency key was reused');
      }
      if (!settingsSnapshot.exists) {
        throw StateError('Workspace settings are required for invoicing');
      }
      final shopSnapshot = await transaction.get(shopRef);
      final shopData = shopSnapshot.data();
      if (!shopSnapshot.exists ||
          shopData == null ||
          shopData['tenant_id'] != tenantId ||
          shopData['route_id'] != routeId ||
          shopData['active'] == false ||
          shopData['deleted'] == true) {
        throw ArgumentError(
          'Shop does not belong to this workspace and route or cannot accept new sales',
        );
      }
      final settingsData = settingsSnapshot.data();
      final inventorySnapshots =
          <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final entry in inventoryRefs.entries) {
        inventorySnapshots[entry.key] = await transaction.get(entry.value);
      }
      for (final entry in inventorySnapshots.entries) {
        final snapshot = entry.value;
        final inventoryData = snapshot.data();
        final requestedQty = sellerInventoryDeductions[entry.key]!;
        if (!snapshot.exists ||
            inventoryData == null ||
            inventoryData['tenant_id'] != tenantId ||
            inventoryData['seller_id'] != sellerId.trim()) {
          throw ArgumentError(
            'Seller inventory is unavailable in this workspace',
          );
        }
        final variantId =
            (inventoryData['variant_id'] as String?)?.trim() ?? '';
        if (variantId.isEmpty) {
          throw ArgumentError(
            'Seller inventory is missing its variant reference',
          );
        }
        final availableQty =
            (inventoryData['quantity_available'] as num?)?.toInt() ?? 0;
        if (availableQty < requestedQty) {
          throw ArgumentError(
            'Insufficient seller inventory for ${entry.key}: requested $requestedQty, available $availableQty',
          );
        }
      }
      if (fulfillmentMode == InvoiceModel.fulfillmentStock &&
          !sellerInventoryDeductionsMatchInvoiceItems(
            items: items,
            deductions: sellerInventoryDeductions,
            inventoryVariantIds: {
              for (final entry in inventorySnapshots.entries)
                entry.key:
                    (entry.value.data()?['variant_id'] as String?)?.trim() ??
                    '',
            },
            pairsPerCarton:
                (settingsData?['pairs_per_carton'] as num?)?.toInt() ?? 12,
          )) {
        throw ArgumentError(
          'Seller inventory deductions must match invoice item quantities',
        );
      }
      if (fulfillmentMode == InvoiceModel.fulfillmentNonStock &&
          settingsData?['allow_non_stock_invoices'] != true) {
        throw StateError('Non-stock invoices are disabled for this workspace');
      }
      final sequence = InvoiceNumbering.nextSequence(settingsData);
      final invoiceNumber = InvoiceNumbering.sale(sequence);
      final invoiceHeaderSnapshot = _invoiceHeaderSnapshot(settingsData);
      final now = Timestamp.now();

      transaction.update(settingsRef, {
        'last_invoice_number': sequence,
        'last_invoice_id': invRef.id,
      });
      transaction.set(
        invRef,
        FinancialMinorUnitMigration.withMinorUnits('invoices', {
          'tenant_id': tenantId,
          'invoice_number': invoiceNumber,
          'invoice_sequence': sequence,
          'sale_transaction_id': txRef.id,
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
          'payment_transaction_ids': [
            if (paymentTxRef != null) paymentTxRef.id,
          ],
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
        }),
      );
      transaction.set(
        txRef,
        FinancialMinorUnitMigration.withMinorUnits('transactions', {
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
          'deleted': false,
        }),
      );
      if (paymentTxRef != null) {
        transaction.set(
          paymentTxRef,
          FinancialMinorUnitMigration.withMinorUnits('transactions', {
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
            'deleted': false,
          }),
        );
      }
      transaction.update(shopRef, {
        'balance': FieldValue.increment(total - amountReceived),
        'financial_minor_units':
            FinancialMinorUnitMigration.companionsAfterUpdate(
              'shops',
              shopData,
              {
                'balance':
                    (shopData['balance'] as num).toDouble() +
                    total -
                    amountReceived,
                'last_transaction_amount': total,
              },
            ),
        'updated_at': now,
        'last_transaction_at': now,
        'last_transaction_type': 'cash_out',
        'last_transaction_amount': total,
        'last_transaction_id': txRef.id,
      });
      for (final entry in inventoryRefs.entries) {
        transaction.update(entry.value, {
          'quantity_available': FieldValue.increment(
            -sellerInventoryDeductions[entry.key]!,
          ),
          'updated_at': now,
          'last_sale_invoice_id': invRef.id,
        });
      }
      return (invoiceNumber: invoiceNumber, created: true);
    });
    if (!result.created) return invRef.id;

    try {
      final appUser = await ref.read(authUserProvider.future);
      if (appUser != null && appUser.isSeller) {
        await writeSellerNotification(
          db: db,
          data: buildSellerNotification(
            sourceType: 'invoice',
            sourceId: invRef.id,
            sellerId: appUser.id,
            sellerName: appUser.displayName,
            tenantId: tenantId,
            shopId: shopId,
            shopName: shopName,
            routeId: routeId,
            amount: total,
            transactionType: 'cash_out',
            invoiceNumber: result.invoiceNumber,
          ),
        );
      }
    } catch (error, stackTrace) {
      _logger.w(
        'Best-effort invoice notification write failed',
        error: error,
        stackTrace: stackTrace,
      );
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
    if (!AppFormatters.hasAtMostTwoDecimalPlaces(amount) ||
        !FinancialAmountPolicy.accepts(amount, currency: currency)) {
      throw ArgumentError(
        'Receipt amount must have at most two decimal places, be greater than 0, and <= '
        '${FinancialAmountPolicy.maximumForCurrency(currency).toStringAsFixed(2)} $currency',
      );
    }
    final normalizedSellerId = sellerId.trim();
    if (normalizedSellerId.isEmpty) {
      throw ArgumentError('sellerId must not be empty');
    }
    final invoiceAccess = await _requireInvoiceAccess(
      capability: AppCapability.createCashReceipt,
      actorId: normalizedCreatedBy,
    );
    final tenantId = invoiceAccess.tenantId;
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

    final receipt = await db.runTransaction<({String id, String number})>((
      transaction,
    ) async {
      final settingsSnapshot = await transaction.get(settingsRef);
      final shopSnapshot = await transaction.get(shopRef);
      final invoiceSnapshot = await transaction.get(invoiceRef);
      if (invoiceSnapshot.exists) {
        final existingData = invoiceSnapshot.data()!;
        if (existingData['idempotency_key'] == resolvedKey &&
            existingData['type'] == InvoiceModel.typeCashReceipt &&
            existingData['shop_id'] == normalizedShopId &&
            (existingData['total'] as num?)?.toDouble() == amount) {
          return (
            id: invoiceRef.id,
            number: existingData['invoice_number'] as String? ?? '',
          );
        }
        throw StateError('Cash receipt idempotency key was reused');
      }
      if (!settingsSnapshot.exists) {
        throw StateError(
          'Workspace settings are required for receipt numbering',
        );
      }
      final shopData = shopSnapshot.data();
      if (!shopSnapshot.exists ||
          shopData == null ||
          shopData['tenant_id'] != tenantId ||
          shopData['route_id'] != normalizedRouteId) {
        throw ArgumentError('Shop does not belong to this workspace and route');
      }

      final nextNumber = InvoiceNumbering.nextSequence(settingsSnapshot.data());
      final receiptNumber = InvoiceNumbering.receipt(nextNumber);
      final balanceBefore = (shopData['balance'] as num?)?.toDouble() ?? 0;
      final balanceAfter = balanceBefore - amount;
      final cleanedMethod = paymentMethod?.trim();
      final cleanedReference = referenceNumber?.trim();
      final invoiceHeaderSnapshot = _invoiceHeaderSnapshot(
        settingsSnapshot.data(),
      );

      transaction.update(settingsRef, {
        'last_cash_receipt_number': nextNumber,
        'last_cash_receipt_id': invoiceRef.id,
      });
      transaction.set(
        invoiceRef,
        FinancialMinorUnitMigration.withMinorUnits('invoices', {
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
        }),
      );
      transaction.set(
        transactionRef,
        FinancialMinorUnitMigration.withMinorUnits('transactions', {
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
        }),
      );
      transaction.update(shopRef, {
        'balance': FieldValue.increment(-amount),
        'financial_minor_units':
            FinancialMinorUnitMigration.companionsAfterUpdate(
              'shops',
              shopData,
              {'balance': balanceAfter, 'last_transaction_amount': amount},
            ),
        'updated_at': now,
        'last_transaction_at': now,
        'last_transaction_type': 'cash_in',
        'last_transaction_amount': amount,
        'last_transaction_id': transactionRef.id,
      });
      return (id: receiptId, number: receiptNumber);
    });
    if (invoiceAccess.user.isSeller) {
      try {
        await writeSellerNotification(
          db: db,
          data: buildSellerNotification(
            sourceType: 'invoice',
            sourceId: receipt.id,
            sellerId: normalizedSellerId,
            sellerName: sellerName,
            tenantId: tenantId,
            shopId: normalizedShopId,
            shopName: shopName,
            routeId: normalizedRouteId,
            amount: amount,
            transactionType: 'cash_in',
            invoiceNumber: receipt.number,
          ),
        );
      } catch (error, stackTrace) {
        _logger.w(
          'Best-effort cash receipt notification write failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    return receipt.id;
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
    validateInvoiceItems(items);
    if (sellerInventoryRestores.entries.any(
      (entry) => entry.key.trim().isEmpty || entry.value <= 0,
    )) {
      throw ArgumentError(
        'Seller inventory restores must have positive quantities and IDs',
      );
    }
    if (subtotal <= 0) {
      throw ArgumentError('subtotal must be greater than 0');
    }
    if (total <= 0) {
      throw ArgumentError('total must be greater than 0');
    }
    if (!AppFormatters.hasAtMostTwoDecimalPlaces(subtotal) ||
        !AppFormatters.hasAtMostTwoDecimalPlaces(total) ||
        total > FinancialAmountPolicy.maximumAmount ||
        (total - subtotal).abs() > 0.01) {
      throw ArgumentError(
        'Credit note total must equal its subtotal and remain within the invoice limit',
      );
    }
    final computedSubtotal = items.fold<double>(
      0,
      (acc, item) =>
          acc +
          (item['qty'] as num).toDouble() *
              (item['unit_price'] as num).toDouble(),
    );
    if ((computedSubtotal - subtotal).abs() > 0.01) {
      throw ArgumentError('Credit note item totals do not match the subtotal');
    }
    final normalizedLinkedInvoiceId = linkedInvoiceId?.trim();
    if (normalizedLinkedInvoiceId == null ||
        normalizedLinkedInvoiceId.isEmpty) {
      throw ArgumentError('linkedInvoiceId must not be empty');
    }

    final invoiceAccess = await _requireInvoiceAccess(
      capability: AppCapability.creditNote,
      actorId: normalizedCreatedBy,
    );
    final tenantId = invoiceAccess.tenantId;

    final db = FirebaseFirestore.instance;
    final normalizedKey = idempotencyKey?.trim();
    final resolvedKey = (normalizedKey != null && normalizedKey.isNotEmpty)
        ? normalizedKey
        : const Uuid().v4();
    final invoiceId = const Uuid().v5(
      Namespace.url.value,
      '$tenantId:credit-note:$resolvedKey',
    );
    final invoiceRef = db.collection(Collections.invoices).doc(invoiceId);
    final originalRef = db
        .collection(Collections.invoices)
        .doc(normalizedLinkedInvoiceId);
    final settingsRef = db.collection(Collections.settings).doc(tenantId);
    final legacyCreditNotesQuery = db
        .collection(Collections.invoices)
        .where('tenant_id', isEqualTo: tenantId)
        .where('linked_invoice_id', isEqualTo: normalizedLinkedInvoiceId)
        .limit(_maxCreditNotesForQuantityReconstruction + 1);
    final shopRef = db.collection(Collections.shops).doc(shopId);
    final transactionRef = db
        .collection(Collections.transactions)
        .doc(
          const Uuid().v5(
            Namespace.url.value,
            '$tenantId:credit-note-tx:$resolvedKey',
          ),
        );
    final sellerInventoryRefs =
        <String, DocumentReference<Map<String, dynamic>>>{
          for (final entry in sellerInventoryRestores.entries)
            if (entry.value > 0)
              entry.key: db
                  .collection(Collections.sellerInventory)
                  .doc(entry.key),
        };
    final warehouseVariantIds = sellerInventoryRestores.isEmpty
        ? items
              .map((item) => (item['variant_id'] as String?)?.trim() ?? '')
              .where((id) => id.isNotEmpty)
              .toSet()
        : <String>{};
    final warehouseVariantRefs =
        <String, DocumentReference<Map<String, dynamic>>>{
          for (final id in warehouseVariantIds)
            id: db.collection(Collections.productVariants).doc(id),
        };

    final result = await db
        .runTransaction<({String invoiceNumber, bool created})>((
          transaction,
        ) async {
          final originalSnapshot = await transaction.get(originalRef);
          final settingsSnapshot = await transaction.get(settingsRef);
          final invoiceSnapshot = await transaction.get(invoiceRef);
          if (invoiceSnapshot.exists) {
            final existing = invoiceSnapshot.data()!;
            if (existing['tenant_id'] == tenantId &&
                existing['idempotency_key'] == resolvedKey &&
                existing['linked_invoice_id'] == normalizedLinkedInvoiceId &&
                (existing['total'] as num?)?.toDouble() == total) {
              return (
                invoiceNumber: existing['invoice_number'] as String? ?? '',
                created: false,
              );
            }
            throw StateError('Credit note idempotency key was reused');
          }
          if (!originalSnapshot.exists) {
            throw ArgumentError('Original invoice does not exist');
          }
          if (!settingsSnapshot.exists) {
            throw StateError('Workspace settings are required for invoicing');
          }
          final original = originalSnapshot.data()!;
          if (original['tenant_id'] != tenantId ||
              original['shop_id'] != shopId ||
              original['route_id'] != routeId ||
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
          if (!isCreditNoteWithin30DayWindow(
            invoiceCreatedAt: originalCreatedAt.toDate(),
            now: DateTime.now(),
          )) {
            throw ArgumentError(
              'Credit notes must be created within 30 days of the original invoice',
            );
          }
          final creditedTotal =
              (original['credit_note_total'] as num?)?.toDouble() ?? 0;
          final originalTotal = (original['total'] as num?)?.toDouble() ?? 0;
          if (creditedTotal + total > originalTotal + 0.01) {
            throw ArgumentError(
              'Credit notes cannot exceed the original invoice total',
            );
          }
          final updatedCreditNoteTotal = creditedTotal + total;
          final soldQuantities = invoiceQuantitiesByVariant(
            _invoiceItemMapsFromStored(original['items']),
          );
          // Linked credit-note writes also update this pointer atomically. If
          // it is absent from the bounded query, the query is stale.
          final legacyCreditNotes = await legacyCreditNotesQuery.get();
          if (legacyCreditNotes.docs.length >
              _maxCreditNotesForQuantityReconstruction) {
            throw StateError(
              'Credit-note history exceeds the safe reconstruction limit',
            );
          }
          final latestCreditNoteId =
              (original['latest_credit_note_invoice_id'] as String?)?.trim();
          if (latestCreditNoteId?.isNotEmpty == true &&
              !legacyCreditNotes.docs.any(
                (creditNoteDoc) => creditNoteDoc.id == latestCreditNoteId,
              )) {
            throw StateError(
              'Credit-note history changed during validation; retry the operation',
            );
          }
          final previouslyCreditedQuantities = reconstructCreditNoteQuantities(
            soldQuantities: soldQuantities,
            existingCreditNotes: legacyCreditNotes.docs
                .map((creditNoteDoc) => creditNoteDoc.data())
                .toList(),
          );
          creditNoteQuantitiesAfter(
            soldQuantities: soldQuantities,
            previouslyCreditedQuantities: previouslyCreditedQuantities,
            requestedQuantities: invoiceQuantitiesByVariant(items),
          );
          if (!sellerInventoryRestoresWithinOriginalSale(
            originalDeductions: original['seller_inventory_deductions'],
            existingCreditNotes: legacyCreditNotes.docs
                .map((creditNoteDoc) => creditNoteDoc.data())
                .toList(),
            requestedRestores: sellerInventoryRestores,
          )) {
            throw ArgumentError(
              'Seller inventory restores cannot exceed stock deducted for the original sale',
            );
          }
          final originalAmountReceived =
              (original['amount_received'] as num?)?.toDouble() ?? 0;

          final shopSnapshot = await transaction.get(shopRef);
          final shopData = shopSnapshot.data();
          if (!shopSnapshot.exists ||
              shopData == null ||
              shopData['tenant_id'] != tenantId ||
              shopData['route_id'] != routeId) {
            throw ArgumentError(
              'Shop does not belong to this workspace and route',
            );
          }
          final sellerInventoryData = <String, Map<String, dynamic>>{};
          for (final entry in sellerInventoryRefs.entries) {
            final snapshot = await transaction.get(entry.value);
            if (!snapshot.exists || snapshot.data()?['tenant_id'] != tenantId) {
              throw StateError('Invoice seller inventory is unavailable');
            }
            sellerInventoryData[entry.key] = snapshot.data()!;
          }
          final warehouseVariantData = <String, Map<String, dynamic>>{};
          for (final entry in warehouseVariantRefs.entries) {
            final snapshot = await transaction.get(entry.value);
            if (!snapshot.exists || snapshot.data()?['tenant_id'] != tenantId) {
              throw StateError('Invoice warehouse stock is unavailable');
            }
            warehouseVariantData[entry.key] = snapshot.data()!;
          }

          final settingsData = settingsSnapshot.data();
          final sequence = InvoiceNumbering.nextSequence(settingsData);
          final invoiceNumber = InvoiceNumbering.creditNote(sequence);
          final now = Timestamp.now();
          transaction.update(settingsRef, {
            'last_invoice_number': sequence,
            'last_invoice_id': invoiceRef.id,
          });
          final originalOutstanding = invoiceOutstandingAfterCredits(
            total: originalTotal,
            amountReceived: originalAmountReceived,
            creditNoteTotal: updatedCreditNoteTotal,
          );
          transaction.update(originalRef, {
            'credit_note_total': updatedCreditNoteTotal,
            'outstanding_amount': originalOutstanding,
            'status': invoiceStatusAfterCredits(
              total: originalTotal,
              amountReceived: originalAmountReceived,
              creditNoteTotal: updatedCreditNoteTotal,
            ),
            'latest_credit_note_invoice_id': invoiceRef.id,
            'financial_minor_units':
                FinancialMinorUnitMigration.companionsAfterUpdate(
                  'invoices',
                  original,
                  {
                    'credit_note_total': updatedCreditNoteTotal,
                    'outstanding_amount': originalOutstanding,
                  },
                ),
            'updated_at': now,
          });
          transaction.set(
            invoiceRef,
            FinancialMinorUnitMigration.withMinorUnits('invoices', {
              'tenant_id': tenantId,
              'invoice_number': invoiceNumber,
              'invoice_sequence': sequence,
              'idempotency_key': resolvedKey,
              'type': InvoiceModel.typeCreditNote,
              'invoice_header_snapshot': _invoiceHeaderSnapshot(settingsData),
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
              'return_transaction_id': transactionRef.id,
              'seller_inventory_restores': sellerInventoryRestores,
              'created_by': normalizedCreatedBy,
              'created_at': now,
              'updated_at': now,
            }),
          );
          transaction.set(
            transactionRef,
            FinancialMinorUnitMigration.withMinorUnits('transactions', {
              'tenant_id': tenantId,
              'shop_id': shopId,
              'shop_name': shopName,
              'route_id': routeId,
              'type': 'return',
              'sale_type': 'return',
              'amount': total,
              'description': 'Credit note $invoiceNumber',
              'items': items,
              'invoice_id': invoiceId,
              'invoice_number': invoiceNumber,
              'created_by': normalizedCreatedBy,
              'created_at': now,
              'deleted': false,
            }),
          );
          transaction.update(shopRef, {
            'balance': FieldValue.increment(-total),
            'financial_minor_units':
                FinancialMinorUnitMigration.companionsAfterUpdate(
                  'shops',
                  shopData,
                  {
                    'balance': (shopData['balance'] as num).toDouble() - total,
                    'last_transaction_amount': total,
                  },
                ),
            'updated_at': now,
            'last_transaction_at': now,
            'last_transaction_type': 'return',
            'last_transaction_amount': total,
            'last_transaction_id': transactionRef.id,
          });
          for (final entry in sellerInventoryRefs.entries) {
            final inventoryData = sellerInventoryData[entry.key]!;
            final before =
                (inventoryData['quantity_available'] as num?)?.toInt() ?? 0;
            final quantity = sellerInventoryRestores[entry.key]!;
            transaction.update(entry.value, {
              'quantity_available': FieldValue.increment(quantity),
              'updated_at': now,
            });
            transaction.set(
              db.collection(Collections.inventoryTransactions).doc(),
              {
                'type': 'return_from_shop',
                'seller_id': inventoryData['seller_id'] as String? ?? sellerId,
                'seller_name':
                    inventoryData['seller_name'] as String? ?? sellerName,
                'product_id': inventoryData['product_id'] as String? ?? '',
                'variant_id': inventoryData['variant_id'] as String? ?? '',
                'variant_name': inventoryData['variant_name'] as String? ?? '',
                'quantity': quantity,
                'direction': 'in',
                'previous_quantity': before,
                'new_quantity': before + quantity,
                'notes': 'credit_note:$invoiceNumber',
                'created_by': normalizedCreatedBy,
                'created_at': now,
                'tenant_id': tenantId,
              },
            );
          }
          for (final entry in warehouseVariantRefs.entries) {
            final item = items.firstWhere(
              (value) => value['variant_id'] == entry.key,
            );
            final quantity = (item['qty'] as num?)?.toInt() ?? 0;
            if (quantity > 0) {
              final variantData = warehouseVariantData[entry.key]!;
              final before =
                  (variantData['quantity_available'] as num?)?.toInt() ?? 0;
              transaction.update(entry.value, {
                'quantity_available': FieldValue.increment(quantity),
                'updated_at': now,
              });
              transaction.set(
                db.collection(Collections.inventoryTransactions).doc(),
                {
                  'type': 'return_from_shop',
                  'seller_id': '',
                  'seller_name': 'warehouse',
                  'product_id': variantData['product_id'] as String? ?? '',
                  'variant_id': entry.key,
                  'variant_name': variantData['variant_name'] as String? ?? '',
                  'quantity': quantity,
                  'direction': 'in',
                  'previous_quantity': before,
                  'new_quantity': before + quantity,
                  'notes': 'credit_note:$invoiceNumber',
                  'created_by': normalizedCreatedBy,
                  'created_at': now,
                  'tenant_id': tenantId,
                },
              );
            }
          }
          return (invoiceNumber: invoiceNumber, created: true);
        });
    if (!result.created) return invoiceRef.id;

    return invoiceRef.id;
  }

  /// Voids an invoice — admin only, reversing its balance impact.
  ///
  /// Linked rows retain audit metadata but are excluded from customer-facing
  /// ledgers. Admin history remains available, and the reversal keeps balances
  /// aligned with `shop.balance`.
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
    final invoiceAccess = await _requireInvoiceAccess(
      capability: AppCapability.voidInvoice,
      actorId: createdBy,
    );
    final currentUser = invoiceAccess.user;
    final tenantId = invoiceAccess.tenantId;
    final db = FirebaseFirestore.instance;
    final invoiceRef = db.collection(Collections.invoices).doc(invoiceId);
    final now = Timestamp.now();
    final transactions = db.collection(Collections.transactions);

    final transactionDocuments = await fetchAllQueryDocuments(
      transactions
          .where('tenant_id', isEqualTo: tenantId)
          .where('invoice_id', isEqualTo: invoiceId),
    );
    final transactionIdsForInvoice = transactionDocuments
        .map((document) => document.id)
        .toSet();

    await db.runTransaction<void>((transaction) async {
      final invSnap = await transaction.get(invoiceRef);
      if (!invSnap.exists) {
        throw ArgumentError('Invoice not found: $invoiceId');
      }
      final data = invSnap.data()!;
      final currentStatus = data['status'] as String? ?? '';
      if (currentStatus == InvoiceModel.statusVoid) {
        throw StateError('Invoice $invoiceId is already voided');
      }
      final invoiceTenantId = (data['tenant_id'] as String?)?.trim();
      if (invoiceTenantId == null ||
          invoiceTenantId.isEmpty ||
          invoiceTenantId != tenantId) {
        throw StateError('Invoice belongs to another workspace');
      }
      final effectiveTenantId = invoiceTenantId;
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
      final linkedTransactionRefs =
          <String, DocumentReference<Map<String, dynamic>>>{};
      for (final field in const [
        'sale_transaction_id',
        'payment_transaction_id',
        'cash_receipt_transaction_id',
        'return_transaction_id',
      ]) {
        final transactionId = (data[field] as String?)?.trim() ?? '';
        if (transactionId.isNotEmpty) {
          linkedTransactionRefs[transactionId] = transactions.doc(
            transactionId,
          );
        }
      }
      final paymentTransactionIds = data['payment_transaction_ids'];
      if (paymentTransactionIds is Iterable) {
        for (final value in paymentTransactionIds) {
          if (value is String && value.trim().isNotEmpty) {
            linkedTransactionRefs[value.trim()] = transactions.doc(
              value.trim(),
            );
          }
        }
      }
      for (final transactionId in transactionIdsForInvoice) {
        linkedTransactionRefs.putIfAbsent(
          transactionId,
          () => transactions.doc(transactionId),
        );
      }
      final linkedTransactionEntries = linkedTransactionRefs.entries.toList();
      final linkedTransactionSnapshots = await Future.wait(
        linkedTransactionEntries.map((entry) => transaction.get(entry.value)),
      );
      final rawItems = (data['items'] as List<dynamic>?) ?? const [];
      final rawDeductions =
          (data['seller_inventory_deductions'] as Map<String, dynamic>?) ??
          const <String, dynamic>{};
      final rawRestores =
          (data['seller_inventory_restores'] as Map<String, dynamic>?) ??
          const <String, dynamic>{};
      final stockMovements = docType == InvoiceModel.typeSale
          ? rawDeductions
          : rawRestores;
      final accountingPlan = buildVoidInvoiceAccountingPlan(
        type: docType,
        total: docTotal,
        amountReceived: amountReceived,
        outstandingAmount: outstandingAmount,
        refundMode: refundMode,
      );
      final invoice = InvoiceModel.fromJson(data, invoiceId);
      if (shopId.isEmpty || routeId.trim().isEmpty) {
        throw StateError('Invoice is missing its shop or route');
      }
      final shopRef = shopId.isEmpty
          ? null
          : db.collection(Collections.shops).doc(shopId);
      final sellerInventoryRefs =
          <String, DocumentReference<Map<String, dynamic>>>{};
      for (final entry in stockMovements.entries) {
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
          !(docType == InvoiceModel.typeSale && invoice.isNonStockSale)) {
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
      Map<String, dynamic>? shopData;
      final sellerInventoryData = <String, Map<String, dynamic>>{};
      final warehouseVariantData = <String, Map<String, dynamic>>{};
      if (shopRef != null) {
        final shopSnapshot = snapshots[snapshotIndex++];
        shopData = shopSnapshot.data();
        if (!shopSnapshot.exists ||
            shopData == null ||
            shopData['tenant_id'] != tenantId) {
          throw StateError('Invoice shop is unavailable in this workspace');
        }
      }
      for (final entry in sellerInventoryRefs.entries) {
        final snapshot = snapshots[snapshotIndex++];
        if (!snapshot.exists || snapshot.data()?['tenant_id'] != tenantId) {
          throw StateError('Invoice seller inventory is unavailable');
        }
        sellerInventoryData[entry.key] = snapshot.data()!;
      }
      for (final entry in warehouseVariantRefs.entries) {
        final snapshot = snapshots[snapshotIndex++];
        if (!snapshot.exists || snapshot.data()?['tenant_id'] != tenantId) {
          throw StateError('Invoice warehouse stock is unavailable');
        }
        warehouseVariantData[entry.key] = snapshot.data()!;
      }
      DocumentReference<Map<String, dynamic>>? originalInvoiceRef;
      Map<String, int>? updatedOriginalFinancialMinorUnits;
      double? updatedOriginalCreditNoteTotal;
      double? updatedOriginalOutstanding;
      String? updatedOriginalStatus;
      if (docType == InvoiceModel.typeCreditNote) {
        final linkedInvoiceId = (data['linked_invoice_id'] as String?)?.trim();
        if (linkedInvoiceId == null || linkedInvoiceId.isEmpty) {
          throw StateError('Credit note has no linked sale invoice');
        }
        originalInvoiceRef = db
            .collection(Collections.invoices)
            .doc(linkedInvoiceId);
        final originalSnapshot = await transaction.get(originalInvoiceRef);
        final originalData = originalSnapshot.data();
        final creditedTotal =
            (originalData?['credit_note_total'] as num?)?.toDouble() ?? 0;
        if (!originalSnapshot.exists ||
            originalData == null ||
            originalData['tenant_id'] != tenantId ||
            originalData['type'] != InvoiceModel.typeSale ||
            originalData['shop_id'] != shopId ||
            creditedTotal < docTotal) {
          throw StateError('Linked sale invoice is unavailable for reversal');
        }
        final updatedCreditNoteTotal = creditedTotal - docTotal;
        updatedOriginalCreditNoteTotal = updatedCreditNoteTotal;
        final originalTotal = (originalData['total'] as num?)?.toDouble() ?? 0;
        final originalAmountReceived =
            (originalData['amount_received'] as num?)?.toDouble() ?? 0;
        final updatedOutstanding = invoiceOutstandingAfterCredits(
          total: originalTotal,
          amountReceived: originalAmountReceived,
          creditNoteTotal: updatedCreditNoteTotal,
        );
        updatedOriginalOutstanding = updatedOutstanding;
        updatedOriginalStatus = invoiceStatusAfterCredits(
          total: originalTotal,
          amountReceived: originalAmountReceived,
          creditNoteTotal: updatedCreditNoteTotal,
        );
        updatedOriginalFinancialMinorUnits =
            FinancialMinorUnitMigration.companionsAfterUpdate(
              'invoices',
              originalData,
              {
                'credit_note_total': updatedCreditNoteTotal,
                'outstanding_amount': updatedOutstanding,
              },
            );
      }

      for (var index = 0; index < linkedTransactionSnapshots.length; index++) {
        final snapshot = linkedTransactionSnapshots[index];
        final transactionData = snapshot.data();
        final preservedCreditPayment =
            transactionData != null &&
            shouldPreserveInvoicePaymentAsCustomerCredit(
              invoiceId: invoiceId,
              invoiceType: docType,
              refundMode: refundMode,
              transactionData: transactionData,
            );
        if (!snapshot.exists ||
            transactionData == null ||
            transactionData['tenant_id'] != tenantId ||
            transactionData['invoice_id'] != invoiceId ||
            preservedCreditPayment) {
          continue;
        }
        transaction.update(snapshot.reference, {
          'voided': true,
          'voided_invoice_id': invoiceId,
          'voided_at': now,
          'voided_by': currentUser.id,
          'updated_at': now,
        });
      }
      if (originalInvoiceRef != null &&
          updatedOriginalCreditNoteTotal != null &&
          updatedOriginalOutstanding != null &&
          updatedOriginalStatus != null) {
        transaction.update(originalInvoiceRef, {
          'credit_note_total': updatedOriginalCreditNoteTotal,
          'outstanding_amount': updatedOriginalOutstanding,
          'status': updatedOriginalStatus,
          'voided_credit_note_id': invoiceId,
          'financial_minor_units': updatedOriginalFinancialMinorUnits,
          'updated_at': now,
        });
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
        'voided': true,
        'voided_invoice_id': invoiceId,
        'voided_at': now,
        'voided_by': currentUser.id,
        'created_by': currentUser.id,
        'created_at': now,
        'deleted': false,
      };

      transaction.update(invoiceRef, {
        'status': InvoiceModel.statusVoid,
        'void_by': currentUser.id,
        'void_at': now,
        'void_reason': 'admin_void',
        if (reversalTransactionRef != null)
          'void_reversal_transaction_id': reversalTransactionRef.id,
        'updated_at': now,
      });

      if (shopRef != null) {
        final currentShopData = shopData;
        if (currentShopData == null) {
          throw StateError('Invoice shop data is unavailable');
        }
        transaction.update(shopRef, {
          'balance': FieldValue.increment(accountingPlan.balanceDelta),
          'financial_minor_units':
              FinancialMinorUnitMigration.companionsAfterUpdate(
                'shops',
                currentShopData,
                {
                  'balance':
                      (currentShopData['balance'] as num).toDouble() +
                      accountingPlan.balanceDelta,
                  'last_transaction_amount':
                      accountingPlan.lastTransactionAmount,
                },
              ),
          'updated_at': now,
          'last_transaction_at': now,
          'last_transaction_type': accountingPlan.lastTransactionType,
          'last_transaction_amount': accountingPlan.lastTransactionAmount,
          'last_transaction_id': ?lastTransactionRef?.id,
        });
        for (final entry in sellerInventoryRefs.entries) {
          final quantity = (stockMovements[entry.key] as num?)?.toInt() ?? 0;
          final inventoryData = sellerInventoryData[entry.key]!;
          final before =
              (inventoryData['quantity_available'] as num?)?.toInt() ?? 0;
          final stockDelta = docType == InvoiceModel.typeSale
              ? quantity
              : -quantity;
          transaction.update(entry.value, {
            'quantity_available': FieldValue.increment(stockDelta),
            'updated_at': now,
          });
          transaction.set(
            db.collection(Collections.inventoryTransactions).doc(),
            {
              'type': docType == InvoiceModel.typeSale
                  ? 'return_from_shop'
                  : 'stock_adjustment',
              'seller_id': inventoryData['seller_id'] as String? ?? '',
              'seller_name': inventoryData['seller_name'] as String? ?? '',
              'product_id': inventoryData['product_id'] as String? ?? '',
              'variant_id': inventoryData['variant_id'] as String? ?? '',
              'variant_name': inventoryData['variant_name'] as String? ?? '',
              'quantity': quantity,
              'direction': stockDelta > 0 ? 'in' : 'out',
              'previous_quantity': before,
              'new_quantity': before + stockDelta,
              'notes': 'invoice_void:$invoiceNumber',
              'created_by': currentUser.id,
              'created_at': now,
              'tenant_id': effectiveTenantId,
            },
          );
        }
        for (final item in rawItems.whereType<Map<String, dynamic>>()) {
          final variantId = (item['variant_id'] as String?)?.trim() ?? '';
          final quantity = (item['qty'] as num?)?.toInt() ?? 0;
          final variantRef = warehouseVariantRefs[variantId];
          if (variantRef == null || quantity <= 0) continue;
          final variantData = warehouseVariantData[variantId]!;
          final before =
              (variantData['quantity_available'] as num?)?.toInt() ?? 0;
          final stockDelta = docType == InvoiceModel.typeSale
              ? quantity
              : -quantity;
          transaction.update(variantRef, {
            'quantity_available': FieldValue.increment(stockDelta),
            'updated_at': now,
          });
          transaction.set(
            db.collection(Collections.inventoryTransactions).doc(),
            {
              'type': docType == InvoiceModel.typeSale
                  ? 'return_from_shop'
                  : 'stock_adjustment',
              'seller_id': '',
              'seller_name': 'warehouse',
              'product_id': variantData['product_id'] as String? ?? '',
              'variant_id': variantId,
              'variant_name': variantData['variant_name'] as String? ?? '',
              'quantity': quantity,
              'direction': stockDelta > 0 ? 'in' : 'out',
              'previous_quantity': before,
              'new_quantity': before + stockDelta,
              'notes': 'invoice_void:$invoiceNumber',
              'created_by': currentUser.id,
              'created_at': now,
              'tenant_id': effectiveTenantId,
            },
          );
        }
        if (docType == InvoiceModel.typeSale) {
          if (reversalTransactionRef != null) {
            transaction.set(
              reversalTransactionRef,
              FinancialMinorUnitMigration.withMinorUnits(
                'transactions',
                transactionData(
                  txType: 'return',
                  amount: accountingPlan.reversalTransactionAmount,
                  description: refundMode == VoidRefundMode.creditBalance
                      ? 'Credit for voided invoice $invoiceNumber'
                      : 'Full reversal for voided invoice $invoiceNumber',
                ),
              ),
            );
          }
          if (refundTransactionRef != null) {
            transaction.set(
              refundTransactionRef,
              FinancialMinorUnitMigration.withMinorUnits(
                'transactions',
                transactionData(
                  txType: 'cash_out',
                  amount: accountingPlan.cashRefundAmount,
                  description: 'Cash refund for voided invoice $invoiceNumber',
                ),
              ),
            );
          }
        } else if (reversalTransactionRef != null) {
          transaction.set(
            reversalTransactionRef,
            FinancialMinorUnitMigration.withMinorUnits(
              'transactions',
              transactionData(
                txType: 'cash_out',
                amount: accountingPlan.reversalTransactionAmount,
                description: 'Reversed invoice $invoiceNumber',
                items: rawItems.whereType<Map<String, dynamic>>().toList(),
              ),
            ),
          );
        }
      }
    });
  }

  /// Marks an invoice as paid.
  ///
  /// FI-06 / BUG-05: Uses Firestore transaction for atomicity — prevents
  /// race condition where two concurrent transactions mark-as-paid simultaneously.
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
    final invoiceAccess = await _requireInvoiceAccess(
      capability: AppCapability.settleInvoice,
      actorId: createdBy,
    );
    final currentUser = invoiceAccess.user;
    final tenantId = invoiceAccess.tenantId;
    final invRef = db.collection(Collections.invoices).doc(invoiceId);

    await db.runTransaction((txn) async {
      final invSnap = await txn.get(invRef);
      if (!invSnap.exists) {
        throw ArgumentError('Invoice not found: $invoiceId');
      }
      final invData = invSnap.data()!;
      if (invData['tenant_id'] != tenantId ||
          invData['type'] != InvoiceModel.typeSale ||
          createdBy.trim() != currentUser.id) {
        throw StateError('Invoice is unavailable in this workspace');
      }
      final invoiceRouteId = (invData['route_id'] as String? ?? '').trim();
      if (invoiceRouteId.isEmpty || invoiceRouteId != routeId.trim()) {
        throw StateError('Invoice route does not match the requested route');
      }
      final currentStatus = invData['status'] as String? ?? '';
      if (currentStatus == InvoiceModel.statusVoid) {
        throw StateError('Cannot mark a voided invoice as paid');
      }

      final invoiceTotal = (invData['total'] as num?)?.toDouble() ?? 0.0;
      final invAmountReceived =
          (invData['amount_received'] as num?)?.toDouble() ?? 0.0;
      final creditNoteTotal =
          (invData['credit_note_total'] as num?)?.toDouble() ?? 0.0;
      if (invAmountReceived < 0 ||
          invAmountReceived > invoiceTotal ||
          creditNoteTotal < 0 ||
          creditNoteTotal > invoiceTotal) {
        throw StateError(
          'Invoice $invoiceId has invalid received or credit-note totals',
        );
      }
      final outstanding = invoiceOutstandingAfterCredits(
        total: invoiceTotal,
        amountReceived: invAmountReceived,
        creditNoteTotal: creditNoteTotal,
      );
      if (currentStatus == InvoiceModel.statusPaid && outstanding == 0) {
        return;
      }
      final invoiceNumber = invData['invoice_number'] as String? ?? '';
      final shopId = invData['shop_id'] as String? ?? '';
      if (shopId.trim().isEmpty) {
        throw StateError('Invoice has no shop');
      }
      final shopName = invData['shop_name'] as String? ?? '';
      final shopRef = db.collection(Collections.shops).doc(shopId);
      final shopSnapshot = await txn.get(shopRef);
      final shopData = shopSnapshot.data();
      if (!shopSnapshot.exists ||
          shopData == null ||
          shopData['tenant_id'] != tenantId ||
          shopData['route_id'] != invoiceRouteId) {
        throw StateError('Invoice shop is unavailable in this workspace');
      }
      final now = Timestamp.now();

      final payRef = outstanding > 0
          ? db.collection(Collections.transactions).doc()
          : null;

      // Update invoice: mark paid, zero outstanding
      txn.update(invRef, {
        'status': InvoiceModel.statusPaid,
        'amount_received': FieldValue.increment(
          outstanding > 0 ? outstanding : 0,
        ),
        'outstanding_amount': 0,
        'financial_minor_units':
            FinancialMinorUnitMigration.companionsAfterUpdate(
              'invoices',
              invData,
              {
                'amount_received': invAmountReceived + outstanding,
                'outstanding_amount': 0,
              },
            ),
        if (payRef != null)
          'payment_transaction_ids': FieldValue.arrayUnion([payRef.id]),
        if (payRef != null) 'latest_payment_transaction_id': payRef.id,
        'updated_at': now,
      });

      // Create cash_in transaction for the settled amount
      if (payRef != null) {
        txn.set(
          payRef,
          FinancialMinorUnitMigration.withMinorUnits('transactions', {
            'tenant_id': tenantId,
            'shop_id': shopId,
            'shop_name': shopName,
            'route_id': invoiceRouteId,
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
          }),
        );

        // Decrement customer balance
        if (shopId.isNotEmpty) {
          txn.update(shopRef, {
            'balance': FieldValue.increment(-outstanding),
            'financial_minor_units':
                FinancialMinorUnitMigration.companionsAfterUpdate(
                  'shops',
                  shopData,
                  {
                    'balance':
                        (shopData['balance'] as num).toDouble() - outstanding,
                    'last_transaction_amount': outstanding,
                  },
                ),
            'updated_at': now,
            'last_transaction_at': now,
            'last_transaction_type': 'cash_in',
            'last_transaction_amount': outstanding,
            'last_transaction_id': payRef.id,
          });
        }
      }
    });
  }
}

final invoiceNotifierProvider = AsyncNotifierProvider<InvoiceNotifier, void>(
  InvoiceNotifier.new,
);
