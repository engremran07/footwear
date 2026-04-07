import 'package:cloud_firestore/cloud_firestore.dart';

// =============================================================================
// TransactionModel — single ledger entry for a shop's account.
//
// TYPES (canonical — mirrors Firestore rules allowlist):
//   cash_in   → cash collected from shop (reduces shop.balance)
//               Use case: collecting outstanding debt, standalone payment
//   cash_out  → goods delivered / sale recorded (increases shop.balance)
//               Created with every invoice; also used for quick manual entry
//   return    → goods returned by shop (reduces shop.balance)
//               Always linked to InvoiceNotifier.createReturnInvoice()
//   payment   → standalone payment not tied to a specific invoice
//   write_off → bad debt: balance zeroed, created by ShopNotifier.markAsBadDebt()
//
// FIELD SEMANTICS:
//   shopId / shop_id     → the retail shop's Firestore document ID
//   customerId / customer_id → SAME value as shopId (legacy alias, kept for
//                              backward compatibility with index queries)
//   invoiceId            → populated when transaction originates from an invoice
//
// SOFT DELETE (DI-01):
//   deleted=true records are excluded client-side (!=true) — never server-side
//   isEqualTo:false, because pre-DI-01 docs lack the field entirely.
// =============================================================================
class TransactionItem {
  final String variantId;
  final String sku;
  final String productName;
  final String size;
  final String color;
  final int qty;
  final double unitPrice;
  final double subtotal;

  const TransactionItem({
    required this.variantId,
    required this.sku,
    required this.productName,
    required this.size,
    required this.color,
    required this.qty,
    required this.unitPrice,
    required this.subtotal,
  });

  factory TransactionItem.fromJson(Map<String, dynamic> json) {
    return TransactionItem(
      variantId: json['variant_id'] as String? ?? '',
      sku: json['sku'] as String? ?? '',
      productName: json['product_name'] as String? ?? '',
      size: json['size'] as String? ?? '',
      color: json['color'] as String? ?? '',
      qty: json['qty'] as int? ?? 0,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'variant_id': variantId,
    'sku': sku,
    'product_name': productName,
    'size': size,
    'color': color,
    'qty': qty,
    'unit_price': unitPrice,
    'subtotal': subtotal,
  };
}

class TransactionModel {
  final String id;
  final String shopId;
  final String shopName;
  final String routeId;
  final String? customerId;
  final String? customerName;
  final String type; // cash_in | cash_out | return
  static const String typeCashIn = 'cash_in';
  static const String typeCashOut = 'cash_out';
  static const String typeReturn = 'return';
  final String? saleType; // cash | credit
  final double amount;
  final String? description;
  final List<TransactionItem> items;
  final String? invoiceId;
  final String? invoiceNumber;
  final String createdBy;
  final Timestamp createdAt;
  final bool deleted;
  final Timestamp? deletedAt;
  final String? deletedBy;

  const TransactionModel({
    required this.id,
    required this.shopId,
    required this.shopName,
    required this.routeId,
    this.customerId,
    this.customerName,
    required this.type,
    this.saleType,
    required this.amount,
    this.description,
    this.items = const [],
    this.invoiceId,
    this.invoiceNumber,
    required this.createdBy,
    required this.createdAt,
    this.deleted = false,
    this.deletedAt,
    this.deletedBy,
  });

  bool get isCashIn => type == 'cash_in';
  bool get isCashOut => type == 'cash_out';
  bool get isReturn => type == 'return';
  bool get hasItems => items.isNotEmpty;

  factory TransactionModel.fromJson(Map<String, dynamic> json, String docId) {
    final rawItems = json['items'] as List<dynamic>?;
    return TransactionModel(
      id: docId,
      shopId: json['shop_id'] as String? ?? '',
      shopName: json['shop_name'] as String? ?? '',
      routeId: json['route_id'] as String? ?? '',
      customerId: json['customer_id'] as String?,
      customerName: json['customer_name'] as String?,
      type: json['type'] as String? ?? 'cash_out',
      saleType: json['sale_type'] as String?,
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      description: json['description'] as String?,
      items:
          rawItems
              ?.map((e) => TransactionItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      invoiceId: json['invoice_id'] as String?,
      invoiceNumber: json['invoice_number'] as String?,
      createdBy: json['created_by'] as String? ?? '',
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      deleted: json['deleted'] as bool? ?? false,
      deletedAt: json['deleted_at'] as Timestamp?,
      deletedBy: json['deleted_by'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
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
    if (invoiceId != null) 'invoice_id': invoiceId,
    if (invoiceNumber != null) 'invoice_number': invoiceNumber,
    'created_by': createdBy,
    'created_at': createdAt,
    'deleted': deleted,
    if (deletedAt != null) 'deleted_at': deletedAt,
    if (deletedBy != null) 'deleted_by': deletedBy,
  };
}
