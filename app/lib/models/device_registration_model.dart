import 'package:cloud_firestore/cloud_firestore.dart';

class DeviceRegistrationModel {
  final String id;
  final String userId;
  final String tenantId;
  final int slotNumber;
  final String deviceId;
  final String brand;
  final String model;
  final String platform;
  final String osVersion;
  final String appVersion;
  final String status;
  final Timestamp registeredAt;
  final Timestamp lastSeenAt;
  final Timestamp? revokedAt;
  final String? revokedBy;

  const DeviceRegistrationModel({
    required this.id,
    required this.userId,
    required this.tenantId,
    required this.slotNumber,
    required this.deviceId,
    required this.brand,
    required this.model,
    required this.platform,
    required this.osVersion,
    required this.appVersion,
    required this.status,
    required this.registeredAt,
    required this.lastSeenAt,
    this.revokedAt,
    this.revokedBy,
  });

  String get displayName =>
      [brand, model].where((value) => value.trim().isNotEmpty).join(' ');

  factory DeviceRegistrationModel.fromJson(
    Map<String, dynamic> json,
    String docId,
  ) {
    return DeviceRegistrationModel(
      id: docId,
      userId: json['user_id'] as String? ?? '',
      tenantId: json['tenant_id'] as String? ?? '',
      slotNumber: (json['slot_number'] as num?)?.toInt() ?? 0,
      deviceId: json['device_id'] as String? ?? '',
      brand: json['brand'] as String? ?? '',
      model: json['model'] as String? ?? '',
      platform: json['platform'] as String? ?? 'unknown',
      osVersion: json['os_version'] as String? ?? '',
      appVersion: json['app_version'] as String? ?? '',
      status: json['status'] as String? ?? 'active',
      registeredAt: json['registered_at'] as Timestamp? ?? Timestamp.now(),
      lastSeenAt: json['last_seen_at'] as Timestamp? ?? Timestamp.now(),
      revokedAt: json['revoked_at'] as Timestamp?,
      revokedBy: json['revoked_by'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'tenant_id': tenantId,
    'slot_number': slotNumber,
    'device_id': deviceId,
    'brand': brand,
    'model': model,
    'platform': platform,
    'os_version': osVersion,
    'app_version': appVersion,
    'status': status,
    'registered_at': registeredAt,
    'last_seen_at': lastSeenAt,
    'revoked_at': revokedAt,
    'revoked_by': revokedBy,
  };
}
