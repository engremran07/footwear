import 'package:cloud_firestore/cloud_firestore.dart';

class SupplierModel {
  final String id;
  final String name;
  final String contactName;
  final String phone;
  final String? email;
  final String? address;
  final String paymentTerms;
  final double totalPurchased;
  final Timestamp? lastOrderAt;
  final bool active;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const SupplierModel({
    required this.id,
    required this.name,
    required this.contactName,
    required this.phone,
    this.email,
    this.address,
    required this.paymentTerms,
    required this.totalPurchased,
    this.lastOrderAt,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SupplierModel.fromJson(Map<String, dynamic> json, String docId) {
    return SupplierModel(
      id: docId,
      name: json['name'] as String? ?? '',
      contactName: json['contact_name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String?,
      address: json['address'] as String?,
      paymentTerms: json['payment_terms'] as String? ?? '',
      totalPurchased: (json['total_purchased'] as num?)?.toDouble() ?? 0.0,
      lastOrderAt: json['last_order_at'] as Timestamp?,
      active: json['active'] as bool? ?? true,
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'contact_name': contactName,
    'phone': phone,
    'email': email,
    'address': address,
    'payment_terms': paymentTerms,
    'total_purchased': totalPurchased,
    'last_order_at': lastOrderAt,
    'active': active,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  SupplierModel copyWith({
    String? id,
    String? name,
    String? contactName,
    String? phone,
    String? email,
    String? address,
    String? paymentTerms,
    double? totalPurchased,
    Timestamp? lastOrderAt,
    bool? active,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return SupplierModel(
      id: id ?? this.id,
      name: name ?? this.name,
      contactName: contactName ?? this.contactName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      paymentTerms: paymentTerms ?? this.paymentTerms,
      totalPurchased: totalPurchased ?? this.totalPurchased,
      lastOrderAt: lastOrderAt ?? this.lastOrderAt,
      active: active ?? this.active,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
