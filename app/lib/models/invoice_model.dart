import 'package:cloud_firestore/cloud_firestore.dart';
import 'transaction_model.dart';

class InvoiceModel {
  final String id;
  final String invoiceNumber; // INV-YYYY-NNNN
  final String type; // sale | return | credit_note
  static const String typeSale = 'sale';
  static const String typeReturn = 'return';
  static const String typeCreditNote = 'credit_note';
  final String customerId;
  final String customerName;
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
  final String status; // draft | issued | paid | partial | void
  static const String statusDraft = 'draft';
  static const String statusIssued = 'issued';
  static const String statusPaid = 'paid';
  static const String statusPartial = 'partial';
  static const String statusVoid = 'void';
  final String? notes;
  final String? linkedInvoiceId; // for credit notes referencing original
  final String createdBy;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const InvoiceModel({
    required this.id,
    required this.invoiceNumber,
    required this.type,
    required this.customerId,
    required this.customerName,
    this.shopId = '',
    this.shopName = '',
    this.routeId = '',
    this.sellerId = '',
    this.sellerName = '',
    this.items = const [],
    required this.subtotal,
    this.discount = 0,
    required this.total,
    this.saleType = 'credit',
    this.amountReceived = 0,
    required this.status,
    this.notes,
    this.linkedInvoiceId,
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
    return InvoiceModel(
      id: docId,
      invoiceNumber: json['invoice_number'] as String? ?? '',
      type: json['type'] as String? ?? typeSale,
      customerId: json['customer_id'] as String? ?? '',
      customerName: json['customer_name'] as String? ?? '',
      shopId: json['shop_id'] as String? ?? '',
      shopName: json['shop_name'] as String? ?? '',
      routeId: json['route_id'] as String? ?? '',
      sellerId: json['seller_id'] as String? ?? '',
      sellerName: json['seller_name'] as String? ?? '',
      items: rawItems
              ?.map((e) => TransactionItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      discount: (json['discount'] as num?)?.toDouble() ?? 0,
      total: (json['total'] as num?)?.toDouble() ?? 0,
      saleType: json['sale_type'] as String? ?? 'credit',
      amountReceived: (json['amount_received'] as num?)?.toDouble() ?? 0,
      status: json['status'] as String? ?? statusDraft,
      notes: json['notes'] as String?,
      linkedInvoiceId: json['linked_invoice_id'] as String?,
      createdBy: json['created_by'] as String? ?? '',
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'invoice_number': invoiceNumber,
        'type': type,
        'customer_id': customerId,
        'customer_name': customerName,
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
        'status': status,
        'notes': notes,
        'linked_invoice_id': linkedInvoiceId,
        'created_by': createdBy,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}
