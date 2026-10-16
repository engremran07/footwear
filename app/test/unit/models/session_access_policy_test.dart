import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/utils/session_access_policy.dart';
import 'package:footwear_erp/models/session_model.dart';

void main() {
  group('SessionAccessPolicy.requiresDeviceApproval', () {
    test('requires approval for a seller registering a new device', () {
      expect(
        SessionAccessPolicy.requiresDeviceApproval(
          pairingRequired: true,
          hasActiveDevice: false,
        ),
        isTrue,
      );
    });

    test('does not require approval for an active seller device', () {
      expect(
        SessionAccessPolicy.requiresDeviceApproval(
          pairingRequired: true,
          hasActiveDevice: true,
        ),
        isFalse,
      );
    });

    test('workspace admins are exempt from seller pairing approval', () {
      expect(
        SessionAccessPolicy.requiresDeviceApproval(
          pairingRequired: true,
          hasActiveDevice: false,
          isWorkspaceAdmin: true,
        ),
        isFalse,
      );
    });

    test('sellers still require approval when pairing is enabled', () {
      expect(
        SessionAccessPolicy.requiresDeviceApproval(
          pairingRequired: true,
          hasActiveDevice: false,
          isWorkspaceAdmin: false,
        ),
        isTrue,
      );
    });
  });

  group('SessionAccessPolicy.currentForDevice', () {
    final now = DateTime.utc(2026, 10, 3, 12);

    test('detects clock skew beyond the configured five-minute tolerance', () {
      expect(
        SessionAccessPolicy.isClockSkewed(
          deviceNow: now.add(const Duration(minutes: 4)),
          serverNow: now,
        ),
        isFalse,
      );
      expect(
        SessionAccessPolicy.isClockSkewed(
          deviceNow: now.subtract(const Duration(minutes: 6)),
          serverNow: now,
        ),
        isTrue,
      );
    });

    test('defers missing-session enforcement during access registration', () {
      expect(
        SessionAccessPolicy.shouldDeferMissingSessionEnforcement(
          sessionAge: const Duration(seconds: 3),
        ),
        isTrue,
      );
      expect(
        SessionAccessPolicy.shouldDeferMissingSessionEnforcement(
          sessionAge: const Duration(seconds: 15),
        ),
        isFalse,
      );
      expect(
        SessionAccessPolicy.shouldDeferMissingSessionEnforcement(
          sessionAge: null,
        ),
        isFalse,
      );
    });

    test('discards access checks started before auth state changed', () {
      expect(
        SessionAccessPolicy.shouldDiscardStaleAccessCheck(
          checkGeneration: 2,
          currentGeneration: 2,
        ),
        isFalse,
      );
      expect(
        SessionAccessPolicy.shouldDiscardStaleAccessCheck(
          checkGeneration: 2,
          currentGeneration: 3,
        ),
        isTrue,
      );
    });

    test('does not sign out a different current account', () {
      expect(
        SessionAccessPolicy.shouldSignOutForAccessCheck(
          expectedUid: 'user-a',
          currentUid: 'user-a',
          authOperationInProgress: false,
        ),
        isTrue,
      );
      expect(
        SessionAccessPolicy.shouldSignOutForAccessCheck(
          expectedUid: 'user-a',
          currentUid: 'user-b',
          authOperationInProgress: false,
        ),
        isFalse,
      );
      expect(
        SessionAccessPolicy.shouldSignOutForAccessCheck(
          expectedUid: 'user-a',
          currentUid: 'user-a',
          authOperationInProgress: true,
        ),
        isFalse,
      );
    });

    test('resets session context when role changes for the same user', () {
      expect(
        SessionAccessPolicy.shouldResetSessionContext(
          previousUserId: 'user-a',
          nextUserId: 'user-a',
          previousRole: 'seller',
          nextRole: 'admin',
          previousTenantId: 'tenant-a',
          nextTenantId: 'tenant-a',
        ),
        isTrue,
      );
      expect(
        SessionAccessPolicy.shouldResetSessionContext(
          previousUserId: 'user-a',
          nextUserId: 'user-a',
          previousRole: 'seller',
          nextRole: 'seller',
          previousTenantId: 'tenant-a',
          nextTenantId: 'tenant-a',
        ),
        isFalse,
      );
    });

    test(
      'rejects revoked records during renewal but allows interactive login',
      () {
        expect(
          SessionAccessPolicy.shouldRejectRevokedAccessDuringRenewal(
            isRenewal: true,
            hasRevokedRecord: true,
          ),
          isTrue,
        );
        expect(
          SessionAccessPolicy.shouldRejectRevokedAccessDuringRenewal(
            isRenewal: false,
            hasRevokedRecord: true,
          ),
          isFalse,
        );
        expect(
          SessionAccessPolicy.shouldRejectRevokedAccessDuringRenewal(
            isRenewal: true,
            hasRevokedRecord: false,
          ),
          isFalse,
        );
      },
    );

    test('does not veto renewal for an installation with a live session', () {
      expect(
        SessionAccessPolicy.shouldRejectRevokedAccessDuringRenewal(
          isRenewal: true,
          hasRevokedRecord: true,
          hasLiveRecord: true,
        ),
        isFalse,
      );
    });

    test('does not require device reset when another live slot exists', () {
      expect(
        SessionAccessPolicy.shouldRequireDeviceAdminReset(
          hasRevokedRecord: true,
          hasLiveRecord: true,
          adminResetOnly: true,
          isWorkspaceAdmin: true,
        ),
        isFalse,
      );
    });

    test('requires reset for revoked-only admin device access', () {
      expect(
        SessionAccessPolicy.shouldRequireDeviceAdminReset(
          hasRevokedRecord: true,
          hasLiveRecord: false,
          adminResetOnly: false,
          isWorkspaceAdmin: true,
        ),
        isTrue,
      );
    });

    test('terminates renewal when access is pending', () {
      expect(
        SessionAccessPolicy.shouldTerminatePendingRenewal(
          isRenewal: true,
          accessStatus: 'pending',
        ),
        isTrue,
      );
      expect(
        SessionAccessPolicy.shouldTerminatePendingRenewal(
          isRenewal: true,
          accessStatus: 'active',
        ),
        isFalse,
      );
      expect(
        SessionAccessPolicy.shouldTerminatePendingRenewal(
          isRenewal: false,
          accessStatus: 'pending',
        ),
        isFalse,
      );
    });

    SessionModel session({
      required String id,
      required String status,
      required DateTime lastSeenAt,
      DateTime? expiresAt,
      String deviceId = 'device-a',
      String userId = 'user-a',
      String deviceSlotId = 'slot_0',
      int slotNumber = 0,
    }) {
      return SessionModel(
        id: id,
        sessionId: id,
        slotNumber: slotNumber,
        userId: userId,
        tenantId: 'tenant-a',
        deviceId: deviceId,
        deviceSlotId: deviceSlotId,
        platform: 'web',
        status: status,
        createdAt: Timestamp.fromDate(lastSeenAt),
        lastSeenAt: Timestamp.fromDate(lastSeenAt),
        expiresAt: expiresAt == null ? null : Timestamp.fromDate(expiresAt),
      );
    }

    test('uses the registered device slot independent of session slot', () {
      final registeredSession = session(
        id: 'session-slot-1',
        status: 'active',
        lastSeenAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
        deviceSlotId: 'slot_4',
        slotNumber: 1,
      );

      expect(
        SessionAccessPolicy.deviceSlotIdForSession(
          registeredSession,
          deviceId: 'device-a',
        ),
        'slot_4',
      );
    });

    test('rejects a session with another device or an invalid device slot', () {
      final wrongDevice = session(
        id: 'wrong-device',
        status: 'active',
        lastSeenAt: now,
        deviceId: 'device-b',
      );
      final invalidSlot = session(
        id: 'invalid-slot',
        status: 'active',
        lastSeenAt: now,
        deviceSlotId: 'session-slot-1',
      );

      expect(
        SessionAccessPolicy.deviceSlotIdForSession(
          wrongDevice,
          deviceId: 'device-a',
        ),
        isNull,
      );
      expect(
        SessionAccessPolicy.deviceSlotIdForSession(
          invalidSlot,
          deviceId: 'device-a',
        ),
        isNull,
      );
    });

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
