import 'package:cloud_firestore/cloud_firestore.dart';

class WasteRecordModel {
  final String id;
  final String qcRecordId;
  final String batchId;
  final String? productId;
  final String? size;
  final String? inventoryItemId;
  final String? workerId;
  final String reason;
  final bool disposed;
  final Timestamp? disposedAt;
  final Timestamp createdAt;

  const WasteRecordModel({
    required this.id,
    required this.qcRecordId,
    required this.batchId,
    this.productId,
    this.size,
    this.inventoryItemId,
    this.workerId,
    required this.reason,
    required this.disposed,
    this.disposedAt,
    required this.createdAt,
  });

  factory WasteRecordModel.fromJson(Map<String, dynamic> json, String docId) {
    return WasteRecordModel(
      id: docId,
      qcRecordId: json['qc_record_id'] as String? ?? '',
      batchId: json['batch_id'] as String? ?? '',
      productId: json['product_id'] as String?,
      size: json['size'] as String?,
      inventoryItemId: json['inventory_item_id'] as String?,
      workerId: json['worker_id'] as String?,
      reason: json['reason'] as String? ?? '',
      disposed: json['disposed'] as bool? ?? false,
      disposedAt: json['disposed_at'] as Timestamp?,
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'qc_record_id': qcRecordId,
    'batch_id': batchId,
    'product_id': productId,
    'size': size,
    'inventory_item_id': inventoryItemId,
    'worker_id': workerId,
    'reason': reason,
    'disposed': disposed,
    'disposed_at': disposedAt,
    'created_at': createdAt,
  };

  WasteRecordModel copyWith({
    String? id,
    String? qcRecordId,
    String? batchId,
    String? productId,
    String? size,
    String? inventoryItemId,
    String? workerId,
    String? reason,
    bool? disposed,
    Timestamp? disposedAt,
    Timestamp? createdAt,
  }) {
    return WasteRecordModel(
      id: id ?? this.id,
      qcRecordId: qcRecordId ?? this.qcRecordId,
      batchId: batchId ?? this.batchId,
      productId: productId ?? this.productId,
      size: size ?? this.size,
      inventoryItemId: inventoryItemId ?? this.inventoryItemId,
      workerId: workerId ?? this.workerId,
      reason: reason ?? this.reason,
      disposed: disposed ?? this.disposed,
      disposedAt: disposedAt ?? this.disposedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
