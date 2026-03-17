import 'package:cloud_firestore/cloud_firestore.dart';

class WorkerPaymentModel {
  final String id;
  final String workerId;
  final String workerName;
  final String workerType;
  final double amount;
  final int pairsCount;
  final String period;
  final String status;
  final String? approvedBy;
  final Timestamp? approvedAt;
  final String? notes;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const WorkerPaymentModel({
    required this.id,
    required this.workerId,
    required this.workerName,
    required this.workerType,
    required this.amount,
    required this.pairsCount,
    required this.period,
    required this.status,
    this.approvedBy,
    this.approvedAt,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WorkerPaymentModel.fromJson(Map<String, dynamic> json, String docId) {
    return WorkerPaymentModel(
      id: docId,
      workerId: json['worker_id'] as String? ?? '',
      workerName: json['worker_name'] as String? ?? '',
      workerType: json['worker_type'] as String? ?? 'pk',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      pairsCount: json['pairs_count'] as int? ?? 0,
      period: json['period'] as String? ?? '',
      status: json['status'] as String? ?? 'draft',
      approvedBy: json['approved_by'] as String?,
      approvedAt: json['approved_at'] as Timestamp?,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'worker_id': workerId,
        'worker_name': workerName,
        'worker_type': workerType,
        'amount': amount,
        'pairs_count': pairsCount,
        'period': period,
        'status': status,
        'approved_by': approvedBy,
        'approved_at': approvedAt,
        'notes': notes,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  WorkerPaymentModel copyWith({
    String? id,
    String? workerId,
    String? workerName,
    String? workerType,
    double? amount,
    int? pairsCount,
    String? period,
    String? status,
    String? approvedBy,
    Timestamp? approvedAt,
    String? notes,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return WorkerPaymentModel(
      id: id ?? this.id,
      workerId: workerId ?? this.workerId,
      workerName: workerName ?? this.workerName,
      workerType: workerType ?? this.workerType,
      amount: amount ?? this.amount,
      pairsCount: pairsCount ?? this.pairsCount,
      period: period ?? this.period,
      status: status ?? this.status,
      approvedBy: approvedBy ?? this.approvedBy,
      approvedAt: approvedAt ?? this.approvedAt,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
