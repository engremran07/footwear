import 'package:cloud_firestore/cloud_firestore.dart';

class ShopModel {
  final String id;
  final String name;
  final String routeId;
  final int routeNumber;
  final String? phone;
  final String? address;
  final String? area;
  final String? city;
  final String? contactName;
  final double balance;
  final String? notes;
  final double? latitude;
  final double? longitude;
  final bool active;
  final String createdBy;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const ShopModel({
    required this.id,
    required this.name,
    required this.routeId,
    required this.routeNumber,
    this.phone,
    this.address,
    this.area,
    this.city,
    this.contactName,
    required this.balance,
    this.notes,
    this.latitude,
    this.longitude,
    required this.active,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get hasLocation => latitude != null && longitude != null;
  bool get hasOutstanding => balance > 0;

  factory ShopModel.fromJson(Map<String, dynamic> json, String docId) {
    return ShopModel(
      id: docId,
      name: json['name'] as String? ?? '',
      routeId: json['route_id'] as String? ?? '',
      routeNumber: json['route_number'] as int? ?? 0,
      phone: json['phone'] as String?,
      address: json['address'] as String?,
      area: json['area'] as String?,
      city: json['city'] as String?,
      contactName: json['contact_name'] as String?,
      balance: (json['balance'] as num?)?.toDouble() ?? 0,
      notes: json['notes'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      active: json['active'] as bool? ?? true,
      createdBy: json['created_by'] as String? ?? '',
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'route_id': routeId,
        'route_number': routeNumber,
        'phone': phone,
        'address': address,
        'area': area,
        'city': city,
        'contact_name': contactName,
        'balance': balance,
        'notes': notes,
        'latitude': latitude,
        'longitude': longitude,
        'active': active,
        'created_by': createdBy,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ShopModel && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
