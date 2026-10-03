import 'package:cloud_firestore/cloud_firestore.dart';

class SessionModel {
  final String id;
  final String sessionId;
  final int slotNumber;
  final String userId;
  final String tenantId;
  final String deviceId;
  final String deviceSlotId;
  final String? deviceBrand;
  final String? deviceModel;
  final String platform;
  final String status;
  final Timestamp createdAt;
  final Timestamp lastSeenAt;
  final Timestamp? expiresAt;
  final Timestamp? revokedAt;
  final String? terminationReason;
  final bool isCurrentDevice;

  const SessionModel({
    required this.id,
    this.sessionId = '',
    this.slotNumber = 0,
    required this.userId,
    required this.tenantId,
    required this.deviceId,
    this.deviceSlotId = '',
    this.deviceBrand,
    this.deviceModel,
    required this.platform,
    required this.status,
    required this.createdAt,
    required this.lastSeenAt,
    this.expiresAt,
    this.revokedAt,
    this.terminationReason,
    this.isCurrentDevice = false,
  });

  factory SessionModel.fromJson(Map<String, dynamic> json, String docId) {
    return SessionModel(
      id: docId,
      sessionId: json['session_id'] as String? ?? docId,
      slotNumber: (json['slot_number'] as num?)?.toInt() ?? 0,
      userId: json['user_id'] as String? ?? '',
      tenantId: json['tenant_id'] as String? ?? '',
      deviceId: json['device_id'] as String? ?? '',
      deviceSlotId: json['device_slot_id'] as String? ?? '',
      deviceBrand: json['device_brand'] as String?,
      deviceModel: json['device_model'] as String?,
      platform: json['platform'] as String? ?? 'android',
      status: json['status'] as String? ?? 'active',
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      lastSeenAt: json['last_seen_at'] as Timestamp? ?? Timestamp.now(),
      expiresAt: json['expires_at'] as Timestamp?,
      revokedAt: json['revoked_at'] as Timestamp?,
      terminationReason: json['termination_reason'] as String?,
      isCurrentDevice: json['is_current_device'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'slot_number': slotNumber,
    'user_id': userId,
    'tenant_id': tenantId,
    'device_id': deviceId,
    'device_slot_id': deviceSlotId,
    'device_brand': deviceBrand,
    'device_model': deviceModel,
    'platform': platform,
    'status': status,
    'created_at': createdAt,
    'last_seen_at': lastSeenAt,
    'expires_at': expiresAt,
    'revoked_at': revokedAt,
    'termination_reason': terminationReason,
    'is_current_device': isCurrentDevice,
  };

  SessionModel copyWith({
    String? id,
    String? sessionId,
    int? slotNumber,
    String? userId,
    String? tenantId,
    String? deviceId,
    String? deviceSlotId,
    String? deviceBrand,
    String? deviceModel,
    String? platform,
    String? status,
    Timestamp? createdAt,
    Timestamp? lastSeenAt,
    Timestamp? expiresAt,
    Timestamp? revokedAt,
    String? terminationReason,
    bool? isCurrentDevice,
  }) {
    return SessionModel(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      slotNumber: slotNumber ?? this.slotNumber,
      userId: userId ?? this.userId,
      tenantId: tenantId ?? this.tenantId,
      deviceId: deviceId ?? this.deviceId,
      deviceSlotId: deviceSlotId ?? this.deviceSlotId,
      deviceBrand: deviceBrand ?? this.deviceBrand,
      deviceModel: deviceModel ?? this.deviceModel,
      platform: platform ?? this.platform,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      expiresAt: expiresAt ?? this.expiresAt,
      revokedAt: revokedAt ?? this.revokedAt,
      terminationReason: terminationReason ?? this.terminationReason,
      isCurrentDevice: isCurrentDevice ?? this.isCurrentDevice,
    );
  }
}
