import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../models/invoice_model.dart';
import 'auth_provider.dart';

final invoicesByCustomerProvider =
    StreamProvider.family<List<InvoiceModel>, String>((ref, customerId) {
  return FirebaseFirestore.instance
      .collection(Collections.invoices)
      .where('customer_id', isEqualTo: customerId)
      .orderBy('created_at', descending: true)
      .limit(100)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => InvoiceModel.fromJson(d.data(), d.id)).toList());
});

final invoicesByShopProvider =
    StreamProvider.family<List<InvoiceModel>, String>((ref, shopId) {
  return FirebaseFirestore.instance
      .collection(Collections.invoices)
      .where('shop_id', isEqualTo: shopId)
      .orderBy('created_at', descending: true)
      .limit(100)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => InvoiceModel.fromJson(d.data(), d.id)).toList());
});

final allInvoicesProvider = StreamProvider<List<InvoiceModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.invoices)
      .orderBy('created_at', descending: true)
      .limit(200)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => InvoiceModel.fromJson(d.data(), d.id)).toList());
});

/// Seller-scoped: only invoices created by this seller.
final sellerInvoicesProvider =
    StreamProvider.family<List<InvoiceModel>, String>((ref, sellerId) {
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
final roleAwareInvoicesProvider = StreamProvider<List<InvoiceModel>>((ref) {
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
    StreamProvider.family<InvoiceModel?, String>((ref, invoiceId) {
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

  /// Generates the next invoice number: INV-YYYY-NNNN using a Firestore
  /// counter stored in settings/global.lastInvoiceNumber.
  Future<String> _nextInvoiceNumber() async {
    final db = FirebaseFirestore.instance;
    final settingsRef = db.collection(Collections.settings).doc('global');
    final doc = await settingsRef.get();
    final currentNum = (doc.data()?['last_invoice_number'] as int?) ?? 0;
    final next = currentNum + 1;
    await settingsRef.update({'last_invoice_number': next});
    return 'INV-${DateTime.now().year}-${next.toString().padLeft(4, '0')}';
  }

  /// Creates a sale invoice with atomic customer balance update and stock deduction.
  ///
  /// Payment scenarios handled via [amountReceived]:
  /// - 0 → full credit (status: issued)
  /// - > 0 and < total → partial payment (status: partial)
  /// - >= total → full payment (status: paid); excess reduces old balance
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
  }) async {
    final normalizedCreatedBy = createdBy.trim();
    if (normalizedCreatedBy.isEmpty) {
      throw ArgumentError('createdBy must not be empty');
    }
    if (customerId.trim().isEmpty) {
      throw ArgumentError('customerId must not be empty');
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
    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    final now = Timestamp.now();

    // Create invoice doc
    final invRef = db.collection(Collections.invoices).doc();
    batch.set(invRef, {
      'invoice_number': invoiceNumber,
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
      'sale_type': saleType,
      'amount_received': amountReceived,
      'status': invoiceStatus,
      'notes': notes,
      'linked_invoice_id': null,
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
      });
    }

    // Customer balance: net change = sale total − amount received
    // e.g. sale 5000, received 2000 → balance +3000
    // e.g. sale 5000, received 8000 → balance −3000 (pays off old debt)
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

    final invoiceNumber = await _nextInvoiceNumber();
    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    final now = Timestamp.now();

    final invRef = db.collection(Collections.invoices).doc();
    batch.set(invRef, {
      'invoice_number': invoiceNumber,
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

    await batch.commit();
    return invRef.id;
  }

  /// Voids an invoice — admin only, reverses balance impact.
  Future<void> voidInvoice({
    required String invoiceId,
    required String customerId,
    required double total,
    required String type,
  }) async {
    if (invoiceId.trim().isEmpty) {
      throw ArgumentError('invoiceId must not be empty');
    }

    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    final now = Timestamp.now();

    batch.update(db.collection(Collections.invoices).doc(invoiceId), {
      'status': 'void',
      'updated_at': now,
    });

    // Reverse balance: sale added, so subtract; return subtracted, so add
    if (customerId.isNotEmpty) {
      final reversalDelta = type == InvoiceModel.typeSale ? -total : total;
      batch.update(db.collection(Collections.customers).doc(customerId), {
        'balance': FieldValue.increment(reversalDelta),
        'updated_at': now,
      });
    }

    await batch.commit();
  }

  /// Marks an invoice as paid.
  Future<void> markAsPaid({required String invoiceId}) async {
    if (invoiceId.trim().isEmpty) {
      throw ArgumentError('invoiceId must not be empty');
    }
    await FirebaseFirestore.instance
        .collection(Collections.invoices)
        .doc(invoiceId)
        .update({
      'status': InvoiceModel.statusPaid,
      'updated_at': Timestamp.now(),
    });
  }
}

final invoiceNotifierProvider =
    AsyncNotifierProvider<InvoiceNotifier, void>(InvoiceNotifier.new);
