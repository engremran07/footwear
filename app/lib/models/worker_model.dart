import 'package:cloud_firestore/cloud_firestore.dart';

class WorkerModel {
  final String id;
  final String name;
  final String type;
  final double ratePerPair;
  final String currency;
  final double totalEarned;
  final int pairsProduced;
  final bool active;
  final Timestamp joinedAt;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const WorkerModel({
    required this.id,
    required this.name,
    required this.type,
    required this.ratePerPair,
    required this.currency,
    required this.totalEarned,
    required this.pairsProduced,
    required this.active,
    required this.joinedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WorkerModel.fromJson(Map<String, dynamic> json, String docId) {
    return WorkerModel(
      id: docId,
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'pk',
      ratePerPair: (json['rate_per_pair'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'PKR',
      totalEarned: (json['total_earned'] as num?)?.toDouble() ?? 0.0,
      pairsProduced: json['pairs_produced'] as int? ?? 0,
      active: json['active'] as bool? ?? true,
      joinedAt: json['joined_at'] as Timestamp? ?? Timestamp.now(),
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'rate_per_pair': ratePerPair,
        'currency': currency,
        'total_earned': totalEarned,
        'pairs_produced': pairsProduced,
        'active': active,
        'joined_at': joinedAt,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  WorkerModel copyWith({
    String? id,
    String? name,
    String? type,
    double? ratePerPair,
    String? currency,
    double? totalEarned,
    int? pairsProduced,
    bool? active,
    Timestamp? joinedAt,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return WorkerModel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      ratePerPair: ratePerPair ?? this.ratePerPair,
      currency: currency ?? this.currency,
      totalEarned: totalEarned ?? this.totalEarned,
      pairsProduced: pairsProduced ?? this.pairsProduced,
      active: active ?? this.active,
      joinedAt: joinedAt ?? this.joinedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
