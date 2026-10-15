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
  }) => pairingRequired && !hasActiveDevice;

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
  }) => isRenewal && hasRevokedRecord;

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
        !RegExp(r'^slot_[0-9]$').hasMatch(session.deviceSlotId)) {
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
