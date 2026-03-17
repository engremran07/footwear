import 'package:cloud_firestore/cloud_firestore.dart';

class CashTransactionModel {
  final String id;
  final String type;
  final double amount;
  final String reference;
  final String pnlCategory;
  final String? description;
  final String? workerId;
  final String? workerPaymentId;
  final String? createdBy;
  final String status;
  final String? approvedBy;
  final Timestamp? approvedAt;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const CashTransactionModel({
    required this.id,
    required this.type,
    required this.amount,
    required this.reference,
    required this.pnlCategory,
    this.description,
    this.workerId,
    this.workerPaymentId,
    this.createdBy,
    required this.status,
    this.approvedBy,
    this.approvedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CashTransactionModel.fromJson(
      Map<String, dynamic> json, String docId) {
    return CashTransactionModel(
      id: docId,
      type: json['type'] as String? ?? 'cash_in',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      reference: json['reference'] as String? ?? '',
      pnlCategory: json['pnl_category'] as String? ?? 'other',
      description: json['description'] as String?,
      workerId: json['worker_id'] as String?,
      workerPaymentId: json['worker_payment_id'] as String?,
      createdBy: json['created_by'] as String?,
      status: json['status'] as String? ?? 'pending',
      approvedBy: json['approved_by'] as String?,
      approvedAt: json['approved_at'] as Timestamp?,
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'amount': amount,
        'reference': reference,
        'pnl_category': pnlCategory,
        'description': description,
        'worker_id': workerId,
        'worker_payment_id': workerPaymentId,
        'created_by': createdBy,
        'status': status,
        'approved_by': approvedBy,
        'approved_at': approvedAt,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  CashTransactionModel copyWith({
    String? id,
    String? type,
    double? amount,
    String? reference,
    String? pnlCategory,
    String? description,
    String? workerId,
    String? workerPaymentId,
    String? createdBy,
    String? status,
    String? approvedBy,
    Timestamp? approvedAt,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return CashTransactionModel(
      id: id ?? this.id,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      reference: reference ?? this.reference,
      pnlCategory: pnlCategory ?? this.pnlCategory,
      description: description ?? this.description,
      workerId: workerId ?? this.workerId,
      workerPaymentId: workerPaymentId ?? this.workerPaymentId,
      createdBy: createdBy ?? this.createdBy,
      status: status ?? this.status,
      approvedBy: approvedBy ?? this.approvedBy,
      approvedAt: approvedAt ?? this.approvedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
