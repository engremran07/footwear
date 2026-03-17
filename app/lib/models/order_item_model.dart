import 'package:cloud_firestore/cloud_firestore.dart';

class OrderItemModel {
  final String id;
  final String orderId;
  final String productId;
  final String productName;
  final String size;
  final int qty;
  final double unitPrice;
  final double subtotal;
  final String? inventoryBatchId;
  final String status;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const OrderItemModel({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.productName,
    required this.size,
    required this.qty,
    required this.unitPrice,
    required this.subtotal,
    this.inventoryBatchId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory OrderItemModel.fromJson(Map<String, dynamic> json, String docId) {
    return OrderItemModel(
      id: docId,
      orderId: json['order_id'] as String? ?? '',
      productId: json['product_id'] as String? ?? '',
      productName: json['product_name'] as String? ?? '',
      size: json['size'] as String? ?? '',
      qty: json['qty'] as int? ?? 0,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      inventoryBatchId: json['inventory_batch_id'] as String?,
      status: json['status'] as String? ?? 'pending',
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'order_id': orderId,
        'product_id': productId,
        'product_name': productName,
        'size': size,
        'qty': qty,
        'unit_price': unitPrice,
        'subtotal': subtotal,
        'inventory_batch_id': inventoryBatchId,
        'status': status,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  OrderItemModel copyWith({
    String? id,
    String? orderId,
    String? productId,
    String? productName,
    String? size,
    int? qty,
    double? unitPrice,
    double? subtotal,
    String? inventoryBatchId,
    String? status,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return OrderItemModel(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      size: size ?? this.size,
      qty: qty ?? this.qty,
      unitPrice: unitPrice ?? this.unitPrice,
      subtotal: subtotal ?? this.subtotal,
      inventoryBatchId: inventoryBatchId ?? this.inventoryBatchId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
