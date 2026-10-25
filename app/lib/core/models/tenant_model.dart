import 'package:cloud_firestore/cloud_firestore.dart';

class TenantModel {
  static const freeSeatLimit = 10;

  final String id;
  final String name;
  final String slug;
  final String? plan;
  final int? activeUserCount;
  final int maxActiveUsers;
  final bool active;
  final bool isTrial;
  final Timestamp createdAt;
  final Timestamp updatedAt;
  final String? ownerUserId;
  final Timestamp? archivedAt;
  final String? archivedBy;
  final String? primaryColor;
  final String? accentColor;

  const TenantModel({
    required this.id,
    required this.name,
    required this.slug,
    this.plan,
    this.activeUserCount,
    this.maxActiveUsers = freeSeatLimit,
    this.active = true,
    this.isTrial = false,
    required this.createdAt,
    required this.updatedAt,
    this.ownerUserId,
    this.archivedAt,
    this.archivedBy,
    this.primaryColor,
    this.accentColor,
  });

  factory TenantModel.fromJson(Map<String, dynamic> json, String docId) {
    return TenantModel(
      id: docId,
      name: json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      plan: json['plan'] as String?,
      activeUserCount: (json['active_user_count'] as num?)?.toInt(),
      maxActiveUsers:
          (json['max_active_users'] as num?)?.toInt() ?? freeSeatLimit,
      active: json['active'] as bool? ?? true,
      isTrial: json['is_trial'] as bool? ?? false,
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
      ownerUserId: json['owner_user_id'] as String?,
      archivedAt: json['archived_at'] as Timestamp?,
      archivedBy: json['archived_by'] as String?,
      primaryColor: json['primary_color'] as String?,
      accentColor: json['accent_color'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'slug': slug,
    'plan': plan,
    if (activeUserCount != null) 'active_user_count': activeUserCount,
    'max_active_users': maxActiveUsers,
    'active': active,
    'is_trial': isTrial,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'owner_user_id': ownerUserId,
    if (archivedAt != null) 'archived_at': archivedAt,
    if (archivedBy != null) 'archived_by': archivedBy,
    'primary_color': primaryColor,
    'accent_color': accentColor,
  };
}
