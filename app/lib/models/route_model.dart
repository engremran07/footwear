import 'package:cloud_firestore/cloud_firestore.dart';

class RouteModel {
  final String id;
  final int routeNumber;
  final String name;
  final String? area;
  final String? city;
  final String? description;
  final int totalShops;
  final String? assignedSellerId;
  final String? assignedSellerName;
  final bool active;
  final String createdBy;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const RouteModel({
    required this.id,
    required this.routeNumber,
    required this.name,
    this.area,
    this.city,
    this.description,
    required this.totalShops,
    this.assignedSellerId,
    this.assignedSellerName,
    required this.active,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RouteModel.fromJson(Map<String, dynamic> json, String docId) {
    return RouteModel(
      id: docId,
      routeNumber: json['route_number'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      area: json['area'] as String?,
      city: json['city'] as String?,
      description: json['description'] as String?,
      totalShops: json['total_shops'] as int? ?? 0,
      assignedSellerId: json['assigned_seller_id'] as String?,
      assignedSellerName: json['assigned_seller_name'] as String?,
      active: json['active'] as bool? ?? true,
      createdBy: json['created_by'] as String? ?? '',
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'route_number': routeNumber,
    'name': name,
    'area': area,
    'city': city,
    'description': description,
    'total_shops': totalShops,
    'assigned_seller_id': assignedSellerId,
    'assigned_seller_name': assignedSellerName,
    'active': active,
    'created_by': createdBy,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}
