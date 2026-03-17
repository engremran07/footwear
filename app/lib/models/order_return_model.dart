import 'package:cloud_firestore/cloud_firestore.dart';

class ReturnItem {
  final String orderItemId;
  final String productId;
  final String productName;
  final String size;
  final int qtyReturned;
  final String condition; // good | damaged
  final String reason; // wrong_size | stitching_issue | sole_defect | wrong_item | cosmetic | other

  const ReturnItem({
    required this.orderItemId,
    required this.productId,
    required this.productName,
    required this.size,
    required this.qtyReturned,
    required this.condition,
    required this.reason,
  });

  factory ReturnItem.fromMap(Map<String, dynamic> map) {
    return ReturnItem(
      orderItemId: map['order_item_id'] as String? ?? '',
      productId: map['product_id'] as String? ?? '',
      productName: map['product_name'] as String? ?? '',
      size: map['size'] as String? ?? '',
      qtyReturned: (map['qty_returned'] as num?)?.toInt() ?? 0,
      condition: map['condition'] as String? ?? 'good',
      reason: map['reason'] as String? ?? 'other',
    );
  }

  Map<String, dynamic> toMap() => {
        'order_item_id': orderItemId,
        'product_id': productId,
        'product_name': productName,
        'size': size,
        'qty_returned': qtyReturned,
        'condition': condition,
        'reason': reason,
      };

  ReturnItem copyWith({
    String? orderItemId,
    String? productId,
    String? productName,
    String? size,
    int? qtyReturned,
    String? condition,
    String? reason,
  }) {
    return ReturnItem(
      orderItemId: orderItemId ?? this.orderItemId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      size: size ?? this.size,
      qtyReturned: qtyReturned ?? this.qtyReturned,
      condition: condition ?? this.condition,
      reason: reason ?? this.reason,
    );
  }
}

class OrderReturnModel {
  final String id;
  final String orderId;
  final String customerId;
  final String customerName;
  final String type; // full_return | partial_return | replacement | damage_claim
  final List<ReturnItem> items;
  final int totalQtyReturned;
  final double refundAmount;
  final String? replacementOrderId;
  final String? notes;
  final String status; // pending | approved | rejected | completed
  final String? approvedBy;
  final Timestamp? approvedAt;
  final String createdBy;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const OrderReturnModel({
    required this.id,
    required this.orderId,
    required this.customerId,
    required this.customerName,
    required this.type,
    required this.items,
    required this.totalQtyReturned,
    required this.refundAmount,
    this.replacementOrderId,
    this.notes,
    required this.status,
    this.approvedBy,
    this.approvedAt,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory OrderReturnModel.fromJson(Map<String, dynamic> json, String docId) {
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map<String, dynamic>>()
            .map(ReturnItem.fromMap)
            .toList()
        : <ReturnItem>[];

    return OrderReturnModel(
      id: docId,
      orderId: json['order_id'] as String? ?? '',
      customerId: json['customer_id'] as String? ?? '',
      customerName: json['customer_name'] as String? ?? '',
      type: json['type'] as String? ?? 'partial_return',
      items: items,
      totalQtyReturned: (json['total_qty_returned'] as num?)?.toInt() ?? 0,
      refundAmount: (json['refund_amount'] as num?)?.toDouble() ?? 0.0,
      replacementOrderId: json['replacement_order_id'] as String?,
      notes: json['notes'] as String?,
      status: json['status'] as String? ?? 'pending',
      approvedBy: json['approved_by'] as String?,
      approvedAt: json['approved_at'] as Timestamp?,
      createdBy: json['created_by'] as String? ?? '',
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'order_id': orderId,
        'customer_id': customerId,
        'customer_name': customerName,
        'type': type,
        'items': items.map((i) => i.toMap()).toList(),
        'total_qty_returned': totalQtyReturned,
        'refund_amount': refundAmount,
        'replacement_order_id': replacementOrderId,
        'notes': notes,
        'status': status,
        'approved_by': approvedBy,
        'approved_at': approvedAt,
        'created_by': createdBy,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  OrderReturnModel copyWith({
    String? id,
    String? orderId,
    String? customerId,
    String? customerName,
    String? type,
    List<ReturnItem>? items,
    int? totalQtyReturned,
    double? refundAmount,
    String? replacementOrderId,
    String? notes,
    String? status,
    String? approvedBy,
    Timestamp? approvedAt,
    String? createdBy,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return OrderReturnModel(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      type: type ?? this.type,
      items: items ?? this.items,
      totalQtyReturned: totalQtyReturned ?? this.totalQtyReturned,
      refundAmount: refundAmount ?? this.refundAmount,
      replacementOrderId: replacementOrderId ?? this.replacementOrderId,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      approvedBy: approvedBy ?? this.approvedBy,
      approvedAt: approvedAt ?? this.approvedAt,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isCompleted => status == 'completed';
  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
}
