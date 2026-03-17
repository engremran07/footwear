import 'package:cloud_firestore/cloud_firestore.dart';

class ExpenseModel {
  final String id;
  final String category;
  final double amount;
  final String description;
  final String? receiptUrl;
  final String status;
  final String createdBy;
  final String? approvedBy;
  final Timestamp? approvedAt;
  final String? rejectedBy;
  final Timestamp? rejectedAt;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const ExpenseModel({
    required this.id,
    required this.category,
    required this.amount,
    required this.description,
    this.receiptUrl,
    required this.status,
    required this.createdBy,
    this.approvedBy,
    this.approvedAt,
    this.rejectedBy,
    this.rejectedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ExpenseModel.fromJson(Map<String, dynamic> json, String docId) {
    return ExpenseModel(
      id: docId,
      category: json['category'] as String? ?? 'other',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      description: json['description'] as String? ?? '',
      receiptUrl: json['receipt_url'] as String?,
      status: json['status'] as String? ?? 'draft',
      createdBy: json['created_by'] as String? ?? '',
      approvedBy: json['approved_by'] as String?,
      approvedAt: json['approved_at'] as Timestamp?,
      rejectedBy: json['rejected_by'] as String?,
      rejectedAt: json['rejected_at'] as Timestamp?,
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'category': category,
        'amount': amount,
        'description': description,
        'receipt_url': receiptUrl,
        'status': status,
        'created_by': createdBy,
        'approved_by': approvedBy,
        'approved_at': approvedAt,
        'rejected_by': rejectedBy,
        'rejected_at': rejectedAt,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  ExpenseModel copyWith({
    String? id,
    String? category,
    double? amount,
    String? description,
    String? receiptUrl,
    String? status,
    String? createdBy,
    String? approvedBy,
    Timestamp? approvedAt,
    String? rejectedBy,
    Timestamp? rejectedAt,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return ExpenseModel(
      id: id ?? this.id,
      category: category ?? this.category,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      receiptUrl: receiptUrl ?? this.receiptUrl,
      status: status ?? this.status,
      createdBy: createdBy ?? this.createdBy,
      approvedBy: approvedBy ?? this.approvedBy,
      approvedAt: approvedAt ?? this.approvedAt,
      rejectedBy: rejectedBy ?? this.rejectedBy,
      rejectedAt: rejectedAt ?? this.rejectedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
