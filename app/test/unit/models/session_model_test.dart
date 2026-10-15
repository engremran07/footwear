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

  test(
    'local model snapshots replace unresolved server timestamp sentinels',
    () {
      final localTime = Timestamp.fromMillisecondsSinceEpoch(5678);
      final session = SessionModel.fromPendingWriteData(
        {
          'user_id': 'user-1',
          'tenant_id': 'workspace-1',
          'device_id': 'installation-1',
          'device_slot_id': 'slot_0',
          'session_id': 'session-1',
          'slot_number': 0,
          'platform': 'android',
          'status': 'active',
          'created_at': FieldValue.serverTimestamp(),
          'last_seen_at': FieldValue.serverTimestamp(),
          'expires_at': localTime,
        },
        'slot_0',
        createdAt: localTime,
        lastSeenAt: localTime,
      );

      expect(session.createdAt, localTime);
      expect(session.lastSeenAt, localTime);
      expect(session.sessionId, 'session-1');
    },
  );
}
