import 'package:cloud_firestore/cloud_firestore.dart';

class ExpenseApprovalModel {
  final String id;
  final String expenseId;
  final double amount;
  final String category;
  final String description;
  final String status;
  final String? approvedBy;
  final String? notes;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const ExpenseApprovalModel({
    required this.id,
    required this.expenseId,
    required this.amount,
    required this.category,
    required this.description,
    required this.status,
    this.approvedBy,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ExpenseApprovalModel.fromJson(Map<String, dynamic> json, String docId) {
    return ExpenseApprovalModel(
      id: docId,
      expenseId: json['expense_id'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      category: json['category'] as String? ?? '',
      description: json['description'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      approvedBy: json['approved_by'] as String?,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'expense_id': expenseId,
    'amount': amount,
    'category': category,
    'description': description,
    'status': status,
    'approved_by': approvedBy,
    'notes': notes,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  ExpenseApprovalModel copyWith({
    String? id,
    String? expenseId,
    double? amount,
    String? category,
    String? description,
    String? status,
    String? approvedBy,
    String? notes,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return ExpenseApprovalModel(
      id: id ?? this.id,
      expenseId: expenseId ?? this.expenseId,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      description: description ?? this.description,
      status: status ?? this.status,
      approvedBy: approvedBy ?? this.approvedBy,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
