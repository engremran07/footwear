import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/financial_minor_unit_migration.dart';

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

  TransactionItem copyWith({
    String? variantId,
    String? sku,
    String? productName,
    String? size,
    String? color,
    int? qty,
    double? unitPrice,
    double? subtotal,
  }) {
    return TransactionItem(
      variantId: variantId ?? this.variantId,
      sku: sku ?? this.sku,
      productName: productName ?? this.productName,
      size: size ?? this.size,
      color: color ?? this.color,
      qty: qty ?? this.qty,
      unitPrice: unitPrice ?? this.unitPrice,
      subtotal: subtotal ?? this.subtotal,
    );
  }

  factory TransactionItem.fromJson(
    Map<String, dynamic> json, {
    Map<String, dynamic>? financialMinorUnits,
    String? itemPath,
  }) {
    return TransactionItem(
      variantId: json['variant_id'] as String? ?? '',
      sku: json['sku'] as String? ?? '',
      productName: json['product_name'] as String? ?? '',
      size: json['size'] as String? ?? '',
      color: json['color'] as String? ?? '',
      qty: json['qty'] as int? ?? 0,
      unitPrice: FinancialMinorUnitMigration.readMajorAmount(
        json['unit_price'] as num?,
        financialMinorUnits,
        itemPath == null ? 'unit_price' : '$itemPath.unit_price',
      ),
      subtotal: FinancialMinorUnitMigration.readMajorAmount(
        json['subtotal'] as num?,
        financialMinorUnits,
        itemPath == null ? 'subtotal' : '$itemPath.subtotal',
      ),
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
  static const String typePayment = 'payment';
  static const String typeWriteOff = 'write_off';
  static bool isStandaloneCashType(String type) =>
      type == typeCashIn || type == typeCashOut;
  final String? saleType; // cash | credit
  final double amount;
  final String currency; // SAR | PKR
  final String? description;
  final List<TransactionItem> items;
  final String? invoiceId;
  final String? invoiceNumber;
  final String createdBy;
  final Timestamp createdAt;
  final bool deleted;
  final Timestamp? deletedAt;
  final String? deletedBy;
  final bool voided;
  final String? voidedInvoiceId;
  final Timestamp? voidedAt;
  final String? voidedBy;
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
    this.currency = 'SAR',
    this.description,
    this.items = const [],
    this.invoiceId,
    this.invoiceNumber,
    required this.createdBy,
    required this.createdAt,
    this.deleted = false,
    this.deletedAt,
    this.deletedBy,
    this.voided = false,
    this.voidedInvoiceId,
    this.voidedAt,
    this.voidedBy,
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
  bool get isVisibleInCustomerLedger => !deleted && !voided;
  bool get isPayment => type == typePayment;
  bool get isWriteOff => type == typeWriteOff;
  bool get isStandaloneCashTransaction => isStandaloneCashType(type);
  bool get reducesBalance => isCashIn || isReturn || isPayment || isWriteOff;
  double get balanceImpact => switch (type) {
    typeCashOut => amount,
    typeCashIn || typeReturn || typePayment || typeWriteOff => -amount,
    // Unknown legacy type from Firestore — treat as zero impact.
    // Do NOT throw here: balanceImpact is called in folding over all
    // transactions for PDF export; a throw crashes the entire export.
    _ => 0,
  };
  bool get hasItems => items.isNotEmpty;

  factory TransactionModel.fromJson(Map<String, dynamic> json, String docId) {
    final rawItems = json['items'] as List<dynamic>?;
    final financialMinorUnits =
        json['financial_minor_units'] as Map<String, dynamic>?;
    final shopId = (json['shop_id'] as String?)?.trim() ?? '';
    final shopName = (json['shop_name'] as String?)?.trim() ?? '';
    return TransactionModel(
      id: docId,
      shopId: shopId,
      shopName: shopName,
      routeId: json['route_id'] as String? ?? '',
      type: json['type'] as String? ?? 'cash_out',
      saleType: json['sale_type'] as String?,
      amount: FinancialMinorUnitMigration.readMajorAmount(
        json['amount'] as num?,
        financialMinorUnits,
        'amount',
      ),
      currency: json['currency'] as String? ?? 'SAR',
      description: json['description'] as String?,
      items: rawItems == null
          ? []
          : [
              for (var index = 0; index < rawItems.length; index++)
                TransactionItem.fromJson(
                  rawItems[index] as Map<String, dynamic>,
                  financialMinorUnits: financialMinorUnits,
                  itemPath: 'items.$index',
                ),
            ],
      invoiceId: json['invoice_id'] as String?,
      invoiceNumber: json['invoice_number'] as String?,
      createdBy: json['created_by'] as String? ?? '',
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      deleted: json['deleted'] as bool? ?? false,
      deletedAt: json['deleted_at'] as Timestamp?,
      deletedBy: json['deleted_by'] as String?,
      voided: json['voided'] as bool? ?? false,
      voidedInvoiceId: json['voided_invoice_id'] as String?,
      voidedAt: json['voided_at'] as Timestamp?,
      voidedBy: json['voided_by'] as String?,
      editRequestPending: json['edit_request_pending'] as bool? ?? false,
      editRequestStatus: json['edit_request_status'] as String?,
      editRequestRequestedBy: json['edit_request_requested_by'] as String?,
      editRequestRequestedAt: json['edit_request_requested_at'] as Timestamp?,
      editRequestNewAmount: json['edit_request_new_amount'] == null
          ? null
          : FinancialMinorUnitMigration.readMajorAmount(
              json['edit_request_new_amount'] as num?,
              financialMinorUnits,
              'edit_request_new_amount',
            ),
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

  Map<String, dynamic> toJson() =>
      FinancialMinorUnitMigration.withMinorUnits('transactions', {
        'shop_id': shopId,
        'shop_name': shopName,
        'route_id': routeId,
        'type': type,
        'sale_type': saleType,
        'amount': amount,
        'currency': currency,
        'description': description,
        'items': items.map((e) => e.toJson()).toList(),
        if (invoiceId != null) 'invoice_id': invoiceId,
        if (invoiceNumber != null) 'invoice_number': invoiceNumber,
        'created_by': createdBy,
        'created_at': createdAt,
        'deleted': deleted,
        if (deletedAt != null) 'deleted_at': deletedAt,
        if (deletedBy != null) 'deleted_by': deletedBy,
        'voided': voided,
        if (voidedInvoiceId != null) 'voided_invoice_id': voidedInvoiceId,
        if (voidedAt != null) 'voided_at': voidedAt,
        if (voidedBy != null) 'voided_by': voidedBy,
        'edit_request_pending': editRequestPending,
        if (editRequestStatus != null) 'edit_request_status': editRequestStatus,
        if (editRequestRequestedBy != null)
          'edit_request_requested_by': editRequestRequestedBy,
        if (editRequestRequestedAt != null)
          'edit_request_requested_at': editRequestRequestedAt,
        if (editRequestNewAmount != null)
          'edit_request_new_amount': editRequestNewAmount,
        if (editRequestNewType != null)
          'edit_request_new_type': editRequestNewType,
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
      });

  TransactionModel copyWith({
    String? id,
    String? shopId,
    String? shopName,
    String? routeId,
    String? type,
    String? saleType,
    double? amount,
    String? currency,
    String? description,
    List<TransactionItem>? items,
    String? invoiceId,
    String? invoiceNumber,
    String? createdBy,
    Timestamp? createdAt,
    bool? deleted,
    Timestamp? deletedAt,
    String? deletedBy,
    bool? voided,
    String? voidedInvoiceId,
    Timestamp? voidedAt,
    String? voidedBy,
    bool? editRequestPending,
    String? editRequestStatus,
    String? editRequestRequestedBy,
    Timestamp? editRequestRequestedAt,
    double? editRequestNewAmount,
    String? editRequestNewType,
    String? editRequestNewDescription,
    String? editRequestNewSaleType,
    Timestamp? editRequestNewCreatedAt,
    String? editRequestReviewedBy,
    Timestamp? editRequestReviewedAt,
  }) {
    return TransactionModel(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      shopName: shopName ?? this.shopName,
      routeId: routeId ?? this.routeId,
      type: type ?? this.type,
      saleType: saleType ?? this.saleType,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      description: description ?? this.description,
      items: items ?? this.items,
      invoiceId: invoiceId ?? this.invoiceId,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      deleted: deleted ?? this.deleted,
      deletedAt: deletedAt ?? this.deletedAt,
      deletedBy: deletedBy ?? this.deletedBy,
      voided: voided ?? this.voided,
      voidedInvoiceId: voidedInvoiceId ?? this.voidedInvoiceId,
      voidedAt: voidedAt ?? this.voidedAt,
      voidedBy: voidedBy ?? this.voidedBy,
      editRequestPending: editRequestPending ?? this.editRequestPending,
      editRequestStatus: editRequestStatus ?? this.editRequestStatus,
      editRequestRequestedBy:
          editRequestRequestedBy ?? this.editRequestRequestedBy,
      editRequestRequestedAt:
          editRequestRequestedAt ?? this.editRequestRequestedAt,
      editRequestNewAmount: editRequestNewAmount ?? this.editRequestNewAmount,
      editRequestNewType: editRequestNewType ?? this.editRequestNewType,
      editRequestNewDescription:
          editRequestNewDescription ?? this.editRequestNewDescription,
      editRequestNewSaleType:
          editRequestNewSaleType ?? this.editRequestNewSaleType,
      editRequestNewCreatedAt:
          editRequestNewCreatedAt ?? this.editRequestNewCreatedAt,
      editRequestReviewedBy:
          editRequestReviewedBy ?? this.editRequestReviewedBy,
      editRequestReviewedAt:
          editRequestReviewedAt ?? this.editRequestReviewedAt,
    );
  }
}
