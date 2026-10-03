import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/utils/session_access_policy.dart';
import 'package:footwear_erp/models/session_model.dart';

void main() {
  group('SessionAccessPolicy.currentForDevice', () {
    final now = DateTime.utc(2026, 10, 3, 12);

    SessionModel session({
      required String id,
      required String status,
      required DateTime lastSeenAt,
      DateTime? expiresAt,
      String deviceId = 'device-a',
      String userId = 'user-a',
    }) {
      return SessionModel(
        id: id,
        sessionId: id,
        userId: userId,
        tenantId: 'tenant-a',
        deviceId: deviceId,
        platform: 'web',
        status: status,
        createdAt: Timestamp.fromDate(lastSeenAt),
        lastSeenAt: Timestamp.fromDate(lastSeenAt),
        expiresAt: expiresAt == null ? null : Timestamp.fromDate(expiresAt),
      );
    }

    test(
      'prefers a valid session over a stale revoked record for same device',
      () {
        final active = session(
          id: 'active-slot',
          status: 'active',
          lastSeenAt: now,
          expiresAt: now.add(const Duration(hours: 1)),
        );
        final revoked = session(
          id: 'revoked-slot',
          status: 'revoked',
          lastSeenAt: now.subtract(const Duration(days: 1)),
          expiresAt: now.add(const Duration(hours: 1)),
        );

        final selected = SessionAccessPolicy.currentForDevice(
          [revoked, active],
          deviceId: 'device-a',
          now: now,
        );

        expect(selected?.id, 'active-slot');
      },
    );

    test('chooses the most recently seen active session', () {
      final older = session(
        id: 'older-slot',
        status: 'active',
        lastSeenAt: now.subtract(const Duration(minutes: 5)),
        expiresAt: now.add(const Duration(minutes: 30)),
      );
      final newer = session(
        id: 'newer-slot',
        status: 'active',
        lastSeenAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
      );

      final selected = SessionAccessPolicy.currentForDevice(
        [older, newer],
        deviceId: 'device-a',
        now: now,
      );

      expect(selected?.id, 'newer-slot');
    });

    test('ignores expired or different-device records', () {
      final expired = session(
        id: 'expired-slot',
        status: 'active',
        lastSeenAt: now,
        expiresAt: now,
      );
      final otherDevice = session(
        id: 'other-device-slot',
        status: 'active',
        lastSeenAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
        deviceId: 'device-b',
      );

      final selected = SessionAccessPolicy.currentForDevice(
        [expired, otherDevice],
        deviceId: 'device-a',
        now: now,
      );

      expect(selected, isNull);
    });

    test('ignores active sessions from another user on the same device', () {
      final otherUser = session(
        id: 'other-user-slot',
        status: 'active',
        lastSeenAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
        userId: 'user-b',
      );
      final currentUser = session(
        id: 'current-user-slot',
        status: 'active',
        lastSeenAt: now.subtract(const Duration(minutes: 5)),
        expiresAt: now.add(const Duration(hours: 1)),
        userId: 'user-a',
      );

      final selected = SessionAccessPolicy.currentForDevice(
        [otherUser, currentUser],
        deviceId: 'device-a',
        now: now,
        userId: 'user-a',
      );

      expect(selected?.userId, 'user-a');
      expect(selected?.id, 'current-user-slot');
    });
  });
}
