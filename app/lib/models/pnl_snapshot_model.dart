import 'package:cloud_firestore/cloud_firestore.dart';

/// Read-only from Flutter. Written exclusively by Cloud Functions.
class PnlSnapshotModel {
  final String id; // == period (YYYY-MM)
  final String period;
  final double revenue;
  final double cogs;
  final double grossProfit;
  final double expenses;
  final double workerCost;
  final double netProfit;
  final Timestamp updatedAt;

  const PnlSnapshotModel({
    required this.id,
    required this.period,
    required this.revenue,
    required this.cogs,
    required this.grossProfit,
    required this.expenses,
    required this.workerCost,
    required this.netProfit,
    required this.updatedAt,
  });

  factory PnlSnapshotModel.fromJson(Map<String, dynamic> json, String docId) {
    return PnlSnapshotModel(
      id: docId,
      period: json['period'] as String? ?? docId,
      revenue: (json['revenue'] as num?)?.toDouble() ?? 0.0,
      cogs: (json['cogs'] as num?)?.toDouble() ?? 0.0,
      grossProfit: (json['gross_profit'] as num?)?.toDouble() ?? 0.0,
      expenses: (json['expenses'] as num?)?.toDouble() ?? 0.0,
      workerCost: (json['worker_cost'] as num?)?.toDouble() ?? 0.0,
      netProfit: (json['net_profit'] as num?)?.toDouble() ?? 0.0,
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  /// Flutter never writes to pnl_snapshots — Cloud Functions own this collection.
  Map<String, dynamic> toJson() => {};

  PnlSnapshotModel copyWith({
    String? id,
    String? period,
    double? revenue,
    double? cogs,
    double? grossProfit,
    double? expenses,
    double? workerCost,
    double? netProfit,
    Timestamp? updatedAt,
  }) {
    return PnlSnapshotModel(
      id: id ?? this.id,
      period: period ?? this.period,
      revenue: revenue ?? this.revenue,
      cogs: cogs ?? this.cogs,
      grossProfit: grossProfit ?? this.grossProfit,
      expenses: expenses ?? this.expenses,
      workerCost: workerCost ?? this.workerCost,
      netProfit: netProfit ?? this.netProfit,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
