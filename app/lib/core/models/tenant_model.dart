import 'package:cloud_firestore/cloud_firestore.dart';

class TenantModel {
  final String id;
  final String name;
  final String slug;
  final String? plan;
  final bool active;
  final bool isTrial;
  final bool requireDevicePairing;
  final bool allowAdminResetOnly;
  final Timestamp createdAt;
  final Timestamp updatedAt;
  final String? ownerUserId;
  final String? primaryColor;
  final String? accentColor;

  const TenantModel({
    required this.id,
    required this.name,
    required this.slug,
    this.plan,
    this.active = true,
    this.isTrial = false,
    this.requireDevicePairing = false,
    this.allowAdminResetOnly = true,
    required this.createdAt,
    required this.updatedAt,
    this.ownerUserId,
    this.primaryColor,
    this.accentColor,
  });

  factory TenantModel.fromJson(Map<String, dynamic> json, String docId) {
    return TenantModel(
      id: docId,
      name: json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      plan: json['plan'] as String?,
      active: json['active'] as bool? ?? true,
      isTrial: json['is_trial'] as bool? ?? false,
      requireDevicePairing: json['require_device_pairing'] as bool? ?? false,
      allowAdminResetOnly: json['allow_admin_reset_only'] as bool? ?? true,
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
      ownerUserId: json['owner_user_id'] as String?,
      primaryColor: json['primary_color'] as String?,
      accentColor: json['accent_color'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'slug': slug,
    'plan': plan,
    'active': active,
    'is_trial': isTrial,
    'require_device_pairing': requireDevicePairing,
    'allow_admin_reset_only': allowAdminResetOnly,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'owner_user_id': ownerUserId,
    'primary_color': primaryColor,
    'accent_color': accentColor,
  };
}
