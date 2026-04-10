import 'package:cloud_firestore/cloud_firestore.dart';
import 'transaction_model.dart';

// =============================================================================
// InvoiceModel — sale invoice or credit note for a shop.
//
// WHEN TO CREATE AN INVOICE (vs ledger-only):
//   Invoice required  → seller makes a sale AND stock deduction from
//                        seller_inventory is needed.
//   Ledger only       → collecting cash from existing debt (cash_in transaction
//                        only via TransactionNotifier — no invoice created).
//
// FIELD SEMANTICS:
//   shopId / shop_id   → the shop's Firestore document ID (sole identifier).
//   routeId / route_id → the route this invoice belongs to.
//
// LIFECYCLE (state machine):
//   draft → issued → partial → paid
//                  → void (terminal, never re-opened)
//   credit_note is a separate document (type=credit_note) linked via
//   linkedInvoiceId. Credit notes must be created within 30 days of original.
//
// INVOICE NUMBER:
//   Format INV-YYYY-NNNN. Counter in settings/global.last_invoice_number.
//   Incremented atomically via Firestore Transaction to prevent duplicates.
// =============================================================================
class InvoiceModel {
  final String id;
  final String invoiceNumber; // INV-YYYY-NNNN
  final String type; // sale | return | credit_note
  static const String typeSale = 'sale';
  static const String typeReturn = 'return';
  static const String typeCreditNote = 'credit_note';
  final String shopId;
  final String shopName;
  final String routeId;
  final String sellerId;
  final String sellerName;
  final List<TransactionItem> items;
  final double subtotal;
  final double discount;
  final double total;
  final String saleType; // cash | credit
  final double amountReceived; // cash collected at time of invoice
  final double outstandingAmount; // amount still owed = total - amountReceived
  final String status; // draft | issued | paid | partial | void
  static const String statusDraft = 'draft';
  static const String statusIssued = 'issued';
  static const String statusPaid = 'paid';
  static const String statusPartial = 'partial';
  static const String statusVoid = 'void';
  final String? notes;
  final String? linkedInvoiceId; // for credit notes referencing original
  final String? idempotencyKey;
  final Map<String, int> sellerInventoryDeductions;
  final String createdBy;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const InvoiceModel({
    required this.id,
    required this.invoiceNumber,
    required this.type,
    required this.shopId,
    required this.shopName,
    this.routeId = '',
    this.sellerId = '',
    this.sellerName = '',
    this.items = const [],
    required this.subtotal,
    this.discount = 0,
    required this.total,
    this.saleType = 'credit',
    this.amountReceived = 0,
    this.outstandingAmount = 0,
    required this.status,
    this.notes,
    this.linkedInvoiceId,
    this.idempotencyKey,
    this.sellerInventoryDeductions = const {},
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isSale => type == typeSale;
  bool get isReturn => type == typeReturn;
  bool get isCreditNote => type == typeCreditNote;
  bool get isDraft => status == statusDraft;
  bool get isIssued => status == statusIssued;
  bool get isPaid => status == statusPaid;
  bool get isPartial => status == statusPartial;
  bool get isVoid => status == statusVoid;

  factory InvoiceModel.fromJson(Map<String, dynamic> json, String docId) {
    final rawItems = json['items'] as List<dynamic>?;
    final total = (json['total'] as num?)?.toDouble() ?? 0;
    final amountReceived = (json['amount_received'] as num?)?.toDouble() ?? 0;
    final rawDeductions =
        (json['seller_inventory_deductions'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final shopId = (json['shop_id'] as String?)?.trim() ?? '';
    final shopName = (json['shop_name'] as String?)?.trim() ?? '';
    return InvoiceModel(
      id: docId,
      invoiceNumber: json['invoice_number'] as String? ?? '',
      type: json['type'] as String? ?? typeSale,
      shopId: shopId,
      shopName: shopName,
      routeId: json['route_id'] as String? ?? '',
      sellerId: json['seller_id'] as String? ?? '',
      sellerName: json['seller_name'] as String? ?? '',
      items:
          rawItems
              ?.map((e) => TransactionItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      discount: (json['discount'] as num?)?.toDouble() ?? 0,
      total: total,
      saleType: json['sale_type'] as String? ?? 'credit',
      amountReceived: amountReceived,
      outstandingAmount:
          (json['outstanding_amount'] as num?)?.toDouble() ??
          (total - amountReceived),
      status: json['status'] as String? ?? statusDraft,
      notes: json['notes'] as String?,
      linkedInvoiceId: json['linked_invoice_id'] as String?,
      idempotencyKey: json['idempotency_key'] as String?,
      sellerInventoryDeductions: {
        for (final entry in rawDeductions.entries)
          entry.key: (entry.value as num?)?.toInt() ?? 0,
      },
      createdBy: json['created_by'] as String? ?? '',
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'invoice_number': invoiceNumber,
    'type': type,
    'shop_id': shopId,
    'shop_name': shopName,
    'route_id': routeId,
    'seller_id': sellerId,
    'seller_name': sellerName,
    'items': items.map((e) => e.toJson()).toList(),
    'subtotal': subtotal,
    'discount': discount,
    'total': total,
    'sale_type': saleType,
    'amount_received': amountReceived,
    'outstanding_amount': outstandingAmount,
    'status': status,
    'notes': notes,
    'linked_invoice_id': linkedInvoiceId,
    if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
    if (sellerInventoryDeductions.isNotEmpty)
      'seller_inventory_deductions': sellerInventoryDeductions,
    'created_by': createdBy,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}
