import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

enum UserRole { admin, seller, tenantAdmin, superAdmin }

/// P1-8 FIX: Convert role string to UserRole enum with explicit defaulting and logging.
/// Vibe Debt Signal: empty or null role strings should be logged to surface data quality issues.
UserRole _roleFromString(String s) {
  if (s.isEmpty) {
    debugPrint('[VIB] P1-8 Signal: Empty role string; defaulting to seller');
    return UserRole.seller;
  }

  final role = s.trim().toLowerCase();
  
  if (role.isEmpty) {
    debugPrint('[VIB] P1-8 Signal: Whitespace-only role string; defaulting to seller');
    return UserRole.seller;
  }

  switch (role) {
    case 'admin':
    case 'manager':
      return UserRole.admin;
    case 'tenant_admin':
    case 'tenant-admin':
    case 'tenantadmin':
      return UserRole.tenantAdmin;
    case 'super_admin':
    case 'super-admin':
    case 'superadmin':
      return UserRole.superAdmin;
    case 'seller':
      return UserRole.seller;
    default:
      // Unknown role: log and default to seller (safest)
      debugPrint('[VIB] P1-8 Signal: Unknown role "$s"; defaulting to seller');
      return UserRole.seller;
  }
}

String _roleToString(UserRole r) {
  switch (r) {
    case UserRole.admin:
      return 'admin';
    case UserRole.seller:
      return 'seller';
    case UserRole.tenantAdmin:
      return 'tenant_admin';
    case UserRole.superAdmin:
      return 'super_admin';
  }
}

class UserModel {
  final String id;
  final String email;
  final String displayName;
  final UserRole role;
  final String? phone;
  final String? tenantId;
  final bool devicePairingEnabled;
  final String? devicePairingId;
  final List<String> pairedDeviceIds;
  final String? devicePairingResetBy;

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
    this.tenantId,
    this.devicePairingEnabled = false,
    this.devicePairingId,
    this.pairedDeviceIds = const [],
    this.devicePairingResetBy,
    this.assignedRouteIds = const [],
    this.assignedRouteNames = const [],
    required this.active,
    this.emailVerified = false,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isAdmin =>
      role == UserRole.admin ||
      role == UserRole.tenantAdmin ||
      role == UserRole.superAdmin;
  bool get isSeller => role == UserRole.seller;
  bool get isTenantAdmin => role == UserRole.tenantAdmin;
  bool get isSuperAdmin => role == UserRole.superAdmin;

  /// True for any user who can carry vehicle (seller) inventory.
  /// Admin is warehouse owner + field seller simultaneously — no assigned_route_id,
  /// services all routes. Admin owns seller_inventory docs (seller_id = adminUid)
  /// loaded via the Inventory Transfer screen. isAdmin() in Firestore rules covers
  /// all admin writes including self-allocation without a route constraint.
  bool get canHaveSellerInventory => true;

  factory UserModel.fromJson(Map<String, dynamic> json, String docId) {
    final rawRouteIds = json['assigned_route_ids'] as List<dynamic>?;
    final rawRouteNames = json['assigned_route_names'] as List<dynamic>?;
    final rawPairedDevices =
        json['device_pairing_ids'] as List<dynamic>? ??
        ((json['device_pairing_id'] == null)
            ? const <dynamic>[]
            : <dynamic>[json['device_pairing_id']]);

    final routeIds = rawRouteIds?.cast<String>().toList() ?? const <String>[];
    final routeNames =
        rawRouteNames?.cast<String>().toList() ?? const <String>[];
    final pairedDeviceIds = rawPairedDevices.cast<String>().toList();

    return UserModel(
      id: docId,
      email: json['email'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      role: _roleFromString(json['role'] as String? ?? 'seller'),
      phone: json['phone'] as String?,
      tenantId: json['tenant_id'] as String?,
      devicePairingEnabled: json['device_pairing_enabled'] as bool? ?? false,
      devicePairingId: json['device_pairing_id'] as String?,
      pairedDeviceIds: pairedDeviceIds,
      devicePairingResetBy: json['device_pairing_reset_by'] as String?,
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
    'tenant_id': tenantId,
    'device_pairing_enabled': devicePairingEnabled,
    'device_pairing_id': devicePairingId,
    'device_pairing_ids': pairedDeviceIds,
    'device_pairing_reset_by': devicePairingResetBy,
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
    String? tenantId,
    bool? devicePairingEnabled,
    String? devicePairingId,
    List<String>? pairedDeviceIds,
    String? devicePairingResetBy,
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
      tenantId: tenantId ?? this.tenantId,
      devicePairingEnabled: devicePairingEnabled ?? this.devicePairingEnabled,
      devicePairingId: devicePairingId ?? this.devicePairingId,
      pairedDeviceIds: pairedDeviceIds ?? this.pairedDeviceIds,
      devicePairingResetBy: devicePairingResetBy ?? this.devicePairingResetBy,
      assignedRouteIds: assignedRouteIds ?? this.assignedRouteIds,
      assignedRouteNames: assignedRouteNames ?? this.assignedRouteNames,
      active: active ?? this.active,
      emailVerified: emailVerified ?? this.emailVerified,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
