enum SessionAccessErrorCode {
  devicePairingPending,
  deviceBlocked,
  deviceAdminResetRequired,
  deviceSessionRevoked,
  sessionRevoked,
}

class SessionAccessException implements Exception {
  const SessionAccessException(this.code);

  final SessionAccessErrorCode code;

  bool get shouldTerminateSessionOnRenewal => switch (code) {
    SessionAccessErrorCode.deviceBlocked ||
    SessionAccessErrorCode.deviceAdminResetRequired ||
    SessionAccessErrorCode.deviceSessionRevoked ||
    SessionAccessErrorCode.sessionRevoked => true,
    SessionAccessErrorCode.devicePairingPending => false,
  };
}
