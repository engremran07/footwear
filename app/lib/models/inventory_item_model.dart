import 'package:cloud_firestore/cloud_firestore.dart';

class InventoryItemModel {
  final String id;
  final String productId;
  final String productName;
  final String? sku;
  final String? size;
  final String inventoryBatchId;
  final String? purchaseOrderId;
  final double costPerPair;
  final String status;
  final String? orderId;
  final String? orderItemId;
  final String? qcRecordId;
  final String? sellerId;
  final String? sellerName;
  final Timestamp? assignedAt;
  final Timestamp? reservedAt;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const InventoryItemModel({
    required this.id,
    required this.productId,
    required this.productName,
    this.sku,
    this.size,
    required this.inventoryBatchId,
    this.purchaseOrderId,
    required this.costPerPair,
    required this.status,
    this.orderId,
    this.orderItemId,
    this.qcRecordId,
    this.sellerId,
    this.sellerName,
    this.assignedAt,
    this.reservedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory InventoryItemModel.fromJson(Map<String, dynamic> json, String docId) {
    return InventoryItemModel(
      id: docId,
      productId: json['product_id'] as String? ?? '',
      productName: json['product_name'] as String? ?? '',
      sku: json['sku'] as String?,
      size: json['size'] as String?,
      inventoryBatchId: json['inventory_batch_id'] as String? ?? '',
      purchaseOrderId: json['purchase_order_id'] as String?,
      costPerPair: (json['cost_per_pair'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String? ?? 'available',
      orderId: json['order_id'] as String?,
      orderItemId: json['order_item_id'] as String?,
      qcRecordId: json['qc_record_id'] as String?,
      sellerId: json['seller_id'] as String?,
      sellerName: json['seller_name'] as String?,
      assignedAt: json['assigned_at'] as Timestamp?,
      reservedAt: json['reserved_at'] as Timestamp?,
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'product_name': productName,
        'sku': sku,
        'size': size,
        'inventory_batch_id': inventoryBatchId,
        'purchase_order_id': purchaseOrderId,
        'cost_per_pair': costPerPair,
        'status': status,
        'order_id': orderId,
        'order_item_id': orderItemId,
        'qc_record_id': qcRecordId,
        'seller_id': sellerId,
        'seller_name': sellerName,
        'assigned_at': assignedAt,
        'reserved_at': reservedAt,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  InventoryItemModel copyWith({
    String? id,
    String? productId,
    String? productName,
    String? sku,
    String? size,
    String? inventoryBatchId,
    String? purchaseOrderId,
    double? costPerPair,
    String? status,
    String? orderId,
    String? orderItemId,
    String? qcRecordId,
    String? sellerId,
    String? sellerName,
    Timestamp? assignedAt,
    Timestamp? reservedAt,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return InventoryItemModel(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      sku: sku ?? this.sku,
      size: size ?? this.size,
      inventoryBatchId: inventoryBatchId ?? this.inventoryBatchId,
      purchaseOrderId: purchaseOrderId ?? this.purchaseOrderId,
      costPerPair: costPerPair ?? this.costPerPair,
      status: status ?? this.status,
      orderId: orderId ?? this.orderId,
      orderItemId: orderItemId ?? this.orderItemId,
      qcRecordId: qcRecordId ?? this.qcRecordId,
      sellerId: sellerId ?? this.sellerId,
      sellerName: sellerName ?? this.sellerName,
      assignedAt: assignedAt ?? this.assignedAt,
      reservedAt: reservedAt ?? this.reservedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
