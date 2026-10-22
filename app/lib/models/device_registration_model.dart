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

  static List<DeviceRegistrationModel> deduplicate(
    Iterable<DeviceRegistrationModel> devices,
  ) {
    final unique = <(String, String), DeviceRegistrationModel>{};
    for (final device in devices) {
      final key = (device.userId, device.deviceId);
      final current = unique[key];
      if (current == null || _compareDuplicateCandidate(device, current) > 0) {
        unique[key] = device;
      }
    }
    return unique.values.toList()..sort((left, right) {
      final byUser = left.userId.compareTo(right.userId);
      return byUser != 0 ? byUser : left.deviceId.compareTo(right.deviceId);
    });
  }

  static int _compareDuplicateCandidate(
    DeviceRegistrationModel candidate,
    DeviceRegistrationModel current,
  ) {
    int statusRank(String status) => switch (status) {
      'blocked' => 4,
      'active' => 3,
      'pending' => 2,
      'revoked' => 1,
      _ => 0,
    };
    final byStatus = statusRank(
      candidate.status,
    ).compareTo(statusRank(current.status));
    if (byStatus != 0) return byStatus;
    return candidate.lastSeenAt.compareTo(current.lastSeenAt);
  }

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
