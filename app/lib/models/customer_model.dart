import 'package:cloud_firestore/cloud_firestore.dart';

class CustomerModel {
  final String id;
  final String name;
  final String? routeId;
  final String? phone;
  final String? city;
  final double balance;
  final bool active;
  final bool badDebt;
  final double badDebtAmount;
  final Timestamp? badDebtDate;
  final String createdBy;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const CustomerModel({
    required this.id,
    required this.name,
    this.routeId,
    this.phone,
    this.city,
    required this.balance,
    required this.active,
    this.badDebt = false,
    this.badDebtAmount = 0,
    this.badDebtDate,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get hasOutstanding => balance > 0;

  factory CustomerModel.fromJson(Map<String, dynamic> json, String docId) {
    return CustomerModel(
      id: docId,
      name: json['name'] as String? ?? '',
      routeId: json['route_id'] as String?,
      phone: json['phone'] as String?,
      city: json['city'] as String?,
      balance: (json['balance'] as num?)?.toDouble() ?? 0,
      active: json['active'] as bool? ?? true,
      badDebt: json['bad_debt'] as bool? ?? false,
      badDebtAmount: (json['bad_debt_amount'] as num?)?.toDouble() ?? 0,
      badDebtDate: json['bad_debt_date'] as Timestamp?,
      createdBy: json['created_by'] as String? ?? '',
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
      if (routeId != null) 'route_id': routeId,
        'phone': phone,
        'city': city,
        'balance': balance,
        'active': active,
        'bad_debt': badDebt,
        'bad_debt_amount': badDebtAmount,
        if (badDebtDate != null) 'bad_debt_date': badDebtDate,
        'created_by': createdBy,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}
