import 'package:cloud_firestore/cloud_firestore.dart';

class CustomerModel {
  final String id;
  final String name;
  final String? phone;
  final String? city;
  final double balance;
  final bool active;
  final String createdBy;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const CustomerModel({
    required this.id,
    required this.name,
    this.phone,
    this.city,
    required this.balance,
    required this.active,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get hasOutstanding => balance > 0;

  factory CustomerModel.fromJson(Map<String, dynamic> json, String docId) {
    return CustomerModel(
      id: docId,
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String?,
      city: json['city'] as String?,
      balance: (json['balance'] as num?)?.toDouble() ?? 0,
      active: json['active'] as bool? ?? true,
      createdBy: json['created_by'] as String? ?? '',
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'city': city,
        'balance': balance,
        'active': active,
        'created_by': createdBy,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}
