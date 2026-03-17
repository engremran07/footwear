import 'package:cloud_firestore/cloud_firestore.dart';

class PurchaseOrderModel {
  final String id;
  final String supplierId;
  final String supplierName;
  final List<Map<String, dynamic>> items;
  final double total;
  final String status;
  final Timestamp? expectedDelivery;
  final String? inventoryBatchId;
  final Timestamp? receivedAt;
  final String? notes;
  final String createdBy;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const PurchaseOrderModel({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    required this.items,
    required this.total,
    required this.status,
    this.expectedDelivery,
    this.inventoryBatchId,
    this.receivedAt,
    this.notes,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PurchaseOrderModel.fromJson(Map<String, dynamic> json, String docId) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    return PurchaseOrderModel(
      id: docId,
      supplierId: json['supplier_id'] as String? ?? '',
      supplierName: json['supplier_name'] as String? ?? '',
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String? ?? 'draft',
      expectedDelivery: json['expected_delivery'] as Timestamp?,
      inventoryBatchId: json['inventory_batch_id'] as String?,
      receivedAt: json['received_at'] as Timestamp?,
      notes: json['notes'] as String?,
      createdBy: json['created_by'] as String? ?? '',
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'supplier_id': supplierId,
        'supplier_name': supplierName,
        'items': items,
        'total': total,
        'status': status,
        'expected_delivery': expectedDelivery,
        'inventory_batch_id': inventoryBatchId,
        'received_at': receivedAt,
        'notes': notes,
        'created_by': createdBy,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  PurchaseOrderModel copyWith({
    String? id,
    String? supplierId,
    String? supplierName,
    List<Map<String, dynamic>>? items,
    double? total,
    String? status,
    Timestamp? expectedDelivery,
    String? inventoryBatchId,
    Timestamp? receivedAt,
    String? notes,
    String? createdBy,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return PurchaseOrderModel(
      id: id ?? this.id,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      items: items ?? this.items,
      total: total ?? this.total,
      status: status ?? this.status,
      expectedDelivery: expectedDelivery ?? this.expectedDelivery,
      inventoryBatchId: inventoryBatchId ?? this.inventoryBatchId,
      receivedAt: receivedAt ?? this.receivedAt,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
