import 'package:cloud_firestore/cloud_firestore.dart';

class CashApprovalModel {
  final String id;
  final String transactionId;
  final double amount;
  final String type;
  final String reference;
  final String status;
  final String? approvedBy;
  final String? notes;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const CashApprovalModel({
    required this.id,
    required this.transactionId,
    required this.amount,
    required this.type,
    required this.reference,
    required this.status,
    this.approvedBy,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CashApprovalModel.fromJson(Map<String, dynamic> json, String docId) {
    return CashApprovalModel(
      id: docId,
      transactionId: json['transaction_id'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      type: json['type'] as String? ?? '',
      reference: json['reference'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      approvedBy: json['approved_by'] as String?,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'transaction_id': transactionId,
    'amount': amount,
    'type': type,
    'reference': reference,
    'status': status,
    'approved_by': approvedBy,
    'notes': notes,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  CashApprovalModel copyWith({
    String? id,
    String? transactionId,
    double? amount,
    String? type,
    String? reference,
    String? status,
    String? approvedBy,
    String? notes,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return CashApprovalModel(
      id: id ?? this.id,
      transactionId: transactionId ?? this.transactionId,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      reference: reference ?? this.reference,
      status: status ?? this.status,
      approvedBy: approvedBy ?? this.approvedBy,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
