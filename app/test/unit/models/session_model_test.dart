import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/session_model.dart';

void main() {
  test('session model round-trips its registered device slot', () {
    final timestamp = Timestamp.fromMillisecondsSinceEpoch(1234);
    final session = SessionModel(
      id: 'slot_0',
      sessionId: 'session-1',
      slotNumber: 0,
      userId: 'user-1',
      tenantId: 'workspace-1',
      deviceId: 'installation-1',
      deviceSlotId: 'slot_1',
      platform: 'android',
      status: 'active',
      createdAt: timestamp,
      lastSeenAt: timestamp,
    );

    final restored = SessionModel.fromJson(session.toJson(), session.id);

    expect(restored.deviceSlotId, 'slot_1');
    expect(restored.copyWith(deviceSlotId: 'slot_2').deviceSlotId, 'slot_2');
  });
}
