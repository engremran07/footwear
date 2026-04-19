import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole { admin, seller }

UserRole _roleFromString(String s) {
  final role = s.trim().toLowerCase();
  switch (role) {
    case 'admin':
    case 'manager':
      return UserRole.admin;
    default:
      return UserRole.seller;
  }
}

String _roleToString(UserRole r) {
  switch (r) {
    case UserRole.admin:
      return 'admin';
    case UserRole.seller:
      return 'seller';
  }
}

class UserModel {
  final String id;
  final String email;
  final String displayName;
  final UserRole role;
  final String? phone;

  /// Multi-route assignment (many-to-many). Each seller can serve multiple routes.
  final List<String> assignedRouteIds;
  final List<String> assignedRouteNames;

  final bool active;
  final bool emailVerified;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const UserModel({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    this.phone,
    this.assignedRouteIds = const [],
    this.assignedRouteNames = const [],
    required this.active,
    this.emailVerified = false,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isAdmin => role == UserRole.admin;
  bool get isSeller => role == UserRole.seller;

  /// True for any user who can carry vehicle (seller) inventory.
  /// Admin is warehouse owner + field seller simultaneously — no assigned_route_id,
  /// services all routes. Admin owns seller_inventory docs (seller_id = adminUid)
  /// loaded via the Inventory Transfer screen. isAdmin() in Firestore rules covers
  /// all admin writes including self-allocation without a route constraint.
  bool get canHaveSellerInventory => true;

  factory UserModel.fromJson(Map<String, dynamic> json, String docId) {
    final rawRouteIds = json['assigned_route_ids'] as List<dynamic>?;
    final rawRouteNames = json['assigned_route_names'] as List<dynamic>?;

    final routeIds = rawRouteIds?.cast<String>().toList() ?? const <String>[];
    final routeNames = rawRouteNames?.cast<String>().toList() ?? const <String>[];

    return UserModel(
      id: docId,
      email: json['email'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      role: _roleFromString(json['role'] as String? ?? 'seller'),
      phone: json['phone'] as String?,
      assignedRouteIds: routeIds,
      assignedRouteNames: routeNames,
      active: json['active'] as bool? ?? true,
      emailVerified: json['email_verified'] as bool? ?? false,
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'email': email,
    'display_name': displayName,
    'role': _roleToString(role),
    'phone': phone,
    'assigned_route_ids': assignedRouteIds,
    'assigned_route_names': assignedRouteNames,
    'active': active,
    'email_verified': emailVerified,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  UserModel copyWith({
    String? id,
    String? email,
    String? displayName,
    UserRole? role,
    String? phone,
    List<String>? assignedRouteIds,
    List<String>? assignedRouteNames,
    bool? active,
    bool? emailVerified,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      phone: phone ?? this.phone,
      assignedRouteIds: assignedRouteIds ?? this.assignedRouteIds,
      assignedRouteNames: assignedRouteNames ?? this.assignedRouteNames,
      active: active ?? this.active,
      emailVerified: emailVerified ?? this.emailVerified,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
