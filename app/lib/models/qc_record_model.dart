import 'package:cloud_firestore/cloud_firestore.dart';

/// Immutable after creation — no updated_at field.
class QcRecordModel {
  final String id;
  final String batchId;
  final String productId;
  final int passedQty;
  final int rejectedQty;
  final String? workerId;
  final List<Map<String, dynamic>> rejectedItems;
  final String? notes;
  final String inspector;
  final Timestamp createdAt;

  const QcRecordModel({
    required this.id,
    required this.batchId,
    required this.productId,
    required this.passedQty,
    required this.rejectedQty,
    this.workerId,
    required this.rejectedItems,
    this.notes,
    required this.inspector,
    required this.createdAt,
  });

  factory QcRecordModel.fromJson(Map<String, dynamic> json, String docId) {
    final rawRejected = json['rejected_items'] as List<dynamic>? ?? [];
    return QcRecordModel(
      id: docId,
      batchId: json['batch_id'] as String? ?? '',
      productId: json['product_id'] as String? ?? '',
      passedQty: json['passed_qty'] as int? ?? 0,
      rejectedQty: json['rejected_qty'] as int? ?? 0,
      workerId: json['worker_id'] as String?,
      rejectedItems: rawRejected
          .whereType<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      notes: json['notes'] as String?,
      inspector: json['inspector'] as String? ?? '',
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'batch_id': batchId,
        'product_id': productId,
        'passed_qty': passedQty,
        'rejected_qty': rejectedQty,
        'worker_id': workerId,
        'rejected_items': rejectedItems,
        'notes': notes,
        'inspector': inspector,
        'created_at': createdAt,
      };

  QcRecordModel copyWith({
    String? id,
    String? batchId,
    String? productId,
    int? passedQty,
    int? rejectedQty,
    String? workerId,
    List<Map<String, dynamic>>? rejectedItems,
    String? notes,
    String? inspector,
    Timestamp? createdAt,
  }) {
    return QcRecordModel(
      id: id ?? this.id,
      batchId: batchId ?? this.batchId,
      productId: productId ?? this.productId,
      passedQty: passedQty ?? this.passedQty,
      rejectedQty: rejectedQty ?? this.rejectedQty,
      workerId: workerId ?? this.workerId,
      rejectedItems: rejectedItems ?? this.rejectedItems,
      notes: notes ?? this.notes,
      inspector: inspector ?? this.inspector,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
