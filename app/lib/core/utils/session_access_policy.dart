import '../../models/session_model.dart';

class SessionAccessPolicy {
  const SessionAccessPolicy._();

  static const accessRegistrationGracePeriod = Duration(seconds: 15);

  static const deviceClockSkewTolerance = Duration(minutes: 5);

  static const platformMaxDevicesAllowed = 2;

  static const platformMaxActiveSessionsAllowed = 1;

  static bool requiresDeviceApproval({
    required bool pairingRequired,
    required bool hasActiveDevice,
    bool isWorkspaceAdmin = false,
  }) => pairingRequired && !isWorkspaceAdmin && !hasActiveDevice;

  static bool canAutoApprovePendingDevice({
    required bool pairingRequired,
    required int slotNumber,
    required int maxDevicesAllowed,
    required int occupiedDeviceCount,
  }) =>
      !pairingRequired &&
      slotNumber >= 0 &&
      slotNumber < maxDevicesAllowed &&
      occupiedDeviceCount <= maxDevicesAllowed;

  static String deviceRegistrationSlotId({
    required String installationId,
    required int slotNumber,
    required bool isWorkspaceAdmin,
  }) => isWorkspaceAdmin ? 'device_$installationId' : 'slot_$slotNumber';

  static bool isValidDeviceRegistrationSlotId(String slotId) =>
      RegExp(r'^slot_[0-9]$').hasMatch(slotId) ||
      RegExp(r'^device_[A-Za-z0-9_-]{8,128}$').hasMatch(slotId);

  static bool isClockSkewed({
    required DateTime deviceNow,
    required DateTime serverNow,
  }) => deviceNow.difference(serverNow).abs() > deviceClockSkewTolerance;

  static bool shouldDeferMissingSessionEnforcement({
    required Duration? sessionAge,
  }) => sessionAge != null && sessionAge < accessRegistrationGracePeriod;

  static bool shouldDiscardStaleAccessCheck({
    required int checkGeneration,
    required int currentGeneration,
  }) => checkGeneration != currentGeneration;

  static bool shouldSignOutForAccessCheck({
    required String expectedUid,
    required String? currentUid,
    required bool authOperationInProgress,
  }) =>
      expectedUid.isNotEmpty &&
      currentUid == expectedUid &&
      !authOperationInProgress;

  static bool shouldRejectRevokedAccessDuringRenewal({
    required bool isRenewal,
    required bool hasRevokedRecord,
    bool hasLiveRecord = false,
  }) => isRenewal && hasRevokedRecord && !hasLiveRecord;

  static bool shouldRequireDeviceAdminReset({
    required bool hasRevokedRecord,
    required bool hasLiveRecord,
    required bool adminResetOnly,
    required bool isWorkspaceAdmin,
  }) =>
      hasRevokedRecord &&
      !hasLiveRecord &&
      (adminResetOnly || isWorkspaceAdmin);

  static bool shouldTerminatePendingRenewal({
    required bool isRenewal,
    required String accessStatus,
  }) => isRenewal && accessStatus == 'pending';

  static bool shouldResetSessionContext({
    required String? previousUserId,
    required String? nextUserId,
    required String? previousRole,
    required String? nextRole,
    required String? previousTenantId,
    required String? nextTenantId,
  }) =>
      nextUserId != null &&
      (previousUserId != nextUserId ||
          previousRole != nextRole ||
          previousTenantId != nextTenantId);

  static String? deviceSlotIdForSession(
    SessionModel session, {
    required String deviceId,
  }) {
    if (session.deviceId != deviceId ||
        !isValidDeviceRegistrationSlotId(session.deviceSlotId)) {
      return null;
    }
    return session.deviceSlotId;
  }

  static SessionModel? currentForDevice(
    Iterable<SessionModel> sessions, {
    required String deviceId,
    required DateTime now,
    String? userId,
  }) {
    final activeSessions =
        sessions.where((session) {
            if (session.deviceId != deviceId) return false;
            if (session.status != 'active') return false;
            if (userId != null && session.userId != userId) return false;
            return session.expiresAt?.toDate().isAfter(now) ?? false;
          }).toList()
          ..sort((left, right) => right.lastSeenAt.compareTo(left.lastSeenAt));
    return activeSessions.isEmpty ? null : activeSessions.first;
  }
}
