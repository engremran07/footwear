import 'package:cloud_firestore/cloud_firestore.dart';

class CustomerModel {
  final String id;
  final String name;
  final String phone;
  final String? email;
  final String? address;
  final String? area;
  final String? city;
  final String country;
  final double? latitude;
  final double? longitude;
  final String? sellerId;
  final String? sellerName;
  final String? contactName;
  final String type;
  final String? notes;
  final bool active;
  final double balance;
  final int totalOrders;
  final String? createdBy;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const CustomerModel({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    this.address,
    this.area,
    this.city,
    required this.country,
    this.latitude,
    this.longitude,
    this.sellerId,
    this.sellerName,
    this.contactName,
    this.type = 'individual',
    this.notes,
    this.active = true,
    required this.balance,
    required this.totalOrders,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get hasLocation => latitude != null && longitude != null;

  factory CustomerModel.fromJson(Map<String, dynamic> json, String docId) {
    return CustomerModel(
      id: docId,
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String?,
      address: json['address'] as String?,
      area: json['area'] as String?,
      city: json['city'] as String?,
      country: json['country'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      sellerId: json['seller_id'] as String?,
      sellerName: json['seller_name'] as String?,
      contactName: json['contact_name'] as String?,
      type: json['type'] as String? ?? 'individual',
      notes: json['notes'] as String?,
      active: json['active'] as bool? ?? true,
      balance: (json['balance'] as num?)?.toDouble() ?? 0.0,
      totalOrders: json['total_orders'] as int? ?? 0,
      createdBy: json['created_by'] as String?,
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'email': email,
        'address': address,
        'area': area,
        'city': city,
        'country': country,
        'latitude': latitude,
        'longitude': longitude,
        'seller_id': sellerId,
        'seller_name': sellerName,
        'contact_name': contactName,
        'type': type,
        'notes': notes,
        'active': active,
        'balance': balance,
        'total_orders': totalOrders,
        'created_by': createdBy,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  CustomerModel copyWith({
    String? id,
    String? name,
    String? phone,
    String? email,
    String? address,
    String? area,
    String? city,
    String? country,
    double? latitude,
    double? longitude,
    String? sellerId,
    String? sellerName,
    String? contactName,
    String? type,
    String? notes,
    bool? active,
    double? balance,
    int? totalOrders,
    String? createdBy,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return CustomerModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      area: area ?? this.area,
      city: city ?? this.city,
      country: country ?? this.country,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      sellerId: sellerId ?? this.sellerId,
      sellerName: sellerName ?? this.sellerName,
      contactName: contactName ?? this.contactName,
      type: type ?? this.type,
      notes: notes ?? this.notes,
      active: active ?? this.active,
      balance: balance ?? this.balance,
      totalOrders: totalOrders ?? this.totalOrders,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
