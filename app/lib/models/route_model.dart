import 'package:cloud_firestore/cloud_firestore.dart';

class RouteModel {
  final String id;
  final int routeNumber;
  final String name;
  final String? area;
  final String? city;
  final String? description;
  final int totalShops;

  /// Multi-seller assignment (many-to-many).
  final List<String> assignedSellerIds;
  final List<String> assignedSellerNames;

  /// Route-level currency: 'SAR' or 'PKR'. Defaults to 'SAR'.
  final String currency;

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
    this.assignedSellerIds = const [],
    this.assignedSellerNames = const [],
    this.currency = 'SAR',
    required this.active,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  RouteModel copyWith({
    String? id,
    int? routeNumber,
    String? name,
    String? area,
    bool clearArea = false,
    String? city,
    bool clearCity = false,
    String? description,
    bool clearDescription = false,
    int? totalShops,
    List<String>? assignedSellerIds,
    bool clearAssignedSellerIds = false,
    List<String>? assignedSellerNames,
    bool clearAssignedSellerNames = false,
    String? currency,
    bool? active,
    String? createdBy,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return RouteModel(
      id: id ?? this.id,
      routeNumber: routeNumber ?? this.routeNumber,
      name: name ?? this.name,
      area: clearArea ? null : (area ?? this.area),
      city: clearCity ? null : (city ?? this.city),
      description: clearDescription ? null : (description ?? this.description),
      totalShops: totalShops ?? this.totalShops,
      assignedSellerIds: clearAssignedSellerIds
          ? const []
          : (assignedSellerIds ?? this.assignedSellerIds),
      assignedSellerNames: clearAssignedSellerNames
          ? const []
          : (assignedSellerNames ?? this.assignedSellerNames),
      currency: currency ?? this.currency,
      active: active ?? this.active,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory RouteModel.fromJson(Map<String, dynamic> json, String docId) {
    final rawSellerIds = json['assigned_seller_ids'] as List<dynamic>?;
    final rawSellerNames = json['assigned_seller_names'] as List<dynamic>?;

    final sellerIds = rawSellerIds?.cast<String>().toList() ?? const <String>[];
    final sellerNames = rawSellerNames?.cast<String>().toList() ?? const <String>[];

    return RouteModel(
      id: docId,
      routeNumber: json['route_number'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      area: json['area'] as String?,
      city: json['city'] as String?,
      description: json['description'] as String?,
      totalShops: json['total_shops'] as int? ?? 0,
      assignedSellerIds: sellerIds,
      assignedSellerNames: sellerNames,
      currency: json['currency'] as String? ?? 'SAR',
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
    'assigned_seller_ids': assignedSellerIds,
    'assigned_seller_names': assignedSellerNames,
    'currency': currency,
    'active': active,
    'created_by': createdBy,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is RouteModel && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
