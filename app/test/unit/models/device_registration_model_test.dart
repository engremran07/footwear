import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/device_registration_model.dart';

void main() {
  test('device registration round-trips descriptive metadata', () {
    final timestamp = Timestamp.fromMillisecondsSinceEpoch(1234);
    final original = DeviceRegistrationModel(
      id: 'slot_0',
      userId: 'user-1',
      tenantId: 'workspace-1',
      slotNumber: 0,
      deviceId: 'installation-1',
      brand: 'Samsung',
      model: 'SM-A576B',
      platform: 'android',
      osVersion: '16',
      appVersion: '3.9.57+96',
      status: 'active',
      registeredAt: timestamp,
      lastSeenAt: timestamp,
    );

    final restored = DeviceRegistrationModel.fromJson(
      original.toJson(),
      original.id,
    );

    expect(restored.userId, original.userId);
    expect(restored.tenantId, original.tenantId);
    expect(restored.deviceId, original.deviceId);
    expect(restored.displayName, 'Samsung SM-A576B');
    expect(restored.registeredAt, timestamp);
  });

  test('missing legacy metadata uses safe display defaults', () {
    final model = DeviceRegistrationModel.fromJson({}, 'slot_0');

    expect(model.brand, isEmpty);
    expect(model.model, isEmpty);
    expect(model.platform, 'unknown');
    expect(model.displayName, isEmpty);
  });

  test('deduplicate keeps the strongest latest record per user and device', () {
    DeviceRegistrationModel registration({
      required String id,
      required String status,
      required int lastSeen,
    }) => DeviceRegistrationModel(
      id: id,
      userId: 'user-1',
      tenantId: 'workspace-1',
      slotNumber: 0,
      deviceId: 'same-installation-id',
      brand: 'Samsung',
      model: 'SM-A576B',
      platform: 'android',
      osVersion: '16',
      appVersion: '3.9.79+705',
      status: status,
      registeredAt: Timestamp.fromMillisecondsSinceEpoch(0),
      lastSeenAt: Timestamp.fromMillisecondsSinceEpoch(lastSeen),
    );

    final devices = DeviceRegistrationModel.deduplicate([
      registration(id: 'slot_0', status: 'active', lastSeen: 100),
      registration(id: 'device_same', status: 'active', lastSeen: 200),
      registration(id: 'device_blocked', status: 'blocked', lastSeen: 50),
    ]);

    expect(devices, hasLength(1));
    expect(devices.single.id, 'device_blocked');
  });
}
