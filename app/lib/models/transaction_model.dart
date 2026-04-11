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
//   shopId / shop_id → the retail shop's Firestore document ID (sole truth)
//   invoiceId        → populated when transaction originates from an invoice
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
  final bool editRequestPending;
  final String? editRequestStatus;
  final String? editRequestRequestedBy;
  final Timestamp? editRequestRequestedAt;
  final double? editRequestNewAmount;
  final String? editRequestNewType;
  final String? editRequestNewDescription;
  final String? editRequestNewSaleType;
  final Timestamp? editRequestNewCreatedAt;
  final String? editRequestReviewedBy;
  final Timestamp? editRequestReviewedAt;

  const TransactionModel({
    required this.id,
    required this.shopId,
    required this.shopName,
    required this.routeId,
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
    this.editRequestPending = false,
    this.editRequestStatus,
    this.editRequestRequestedBy,
    this.editRequestRequestedAt,
    this.editRequestNewAmount,
    this.editRequestNewType,
    this.editRequestNewDescription,
    this.editRequestNewSaleType,
    this.editRequestNewCreatedAt,
    this.editRequestReviewedBy,
    this.editRequestReviewedAt,
  });

  bool get isCashIn => type == 'cash_in';
  bool get isCashOut => type == 'cash_out';
  bool get isReturn => type == 'return';
  bool get isPayment => type == 'payment';
  bool get isWriteOff => type == 'write_off';
  bool get reducesBalance => isCashIn || isReturn || isPayment || isWriteOff;
  double get balanceImpact => switch (type) {
    typeCashOut => amount,
    typeCashIn || typeReturn || 'payment' => -amount,
    'write_off' => 0,
    _ => 0,
  };
  bool get hasItems => items.isNotEmpty;

  factory TransactionModel.fromJson(Map<String, dynamic> json, String docId) {
    final rawItems = json['items'] as List<dynamic>?;
    final shopId = (json['shop_id'] as String?)?.trim() ?? '';
    final shopName = (json['shop_name'] as String?)?.trim() ?? '';
    return TransactionModel(
      id: docId,
      shopId: shopId,
      shopName: shopName,
      routeId: json['route_id'] as String? ?? '',
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
      editRequestPending: json['edit_request_pending'] as bool? ?? false,
      editRequestStatus: json['edit_request_status'] as String?,
      editRequestRequestedBy: json['edit_request_requested_by'] as String?,
      editRequestRequestedAt: json['edit_request_requested_at'] as Timestamp?,
      editRequestNewAmount: (json['edit_request_new_amount'] as num?)
          ?.toDouble(),
      editRequestNewType: json['edit_request_new_type'] as String?,
      editRequestNewDescription:
          json['edit_request_new_description'] as String?,
      editRequestNewSaleType: json['edit_request_new_sale_type'] as String?,
      editRequestNewCreatedAt:
          json['edit_request_new_created_at'] as Timestamp?,
      editRequestReviewedBy: json['edit_request_reviewed_by'] as String?,
      editRequestReviewedAt: json['edit_request_reviewed_at'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() => {
    'shop_id': shopId,
    'shop_name': shopName,
    'route_id': routeId,
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
    'edit_request_pending': editRequestPending,
    if (editRequestStatus != null) 'edit_request_status': editRequestStatus,
    if (editRequestRequestedBy != null)
      'edit_request_requested_by': editRequestRequestedBy,
    if (editRequestRequestedAt != null)
      'edit_request_requested_at': editRequestRequestedAt,
    if (editRequestNewAmount != null)
      'edit_request_new_amount': editRequestNewAmount,
    if (editRequestNewType != null) 'edit_request_new_type': editRequestNewType,
    if (editRequestNewDescription != null)
      'edit_request_new_description': editRequestNewDescription,
    if (editRequestNewSaleType != null)
      'edit_request_new_sale_type': editRequestNewSaleType,
    if (editRequestNewCreatedAt != null)
      'edit_request_new_created_at': editRequestNewCreatedAt,
    if (editRequestReviewedBy != null)
      'edit_request_reviewed_by': editRequestReviewedBy,
    if (editRequestReviewedAt != null)
      'edit_request_reviewed_at': editRequestReviewedAt,
  };
}
