class AccessUsageSummary {
  static const int maximumSlotsPerUser = 10;

  final int maxDevicesAllowed;
  final int registeredDevices;
  final int maxActiveSessionsAllowed;
  final int activeSessions;

  factory AccessUsageSummary({
    required int maxDevicesAllowed,
    required int registeredDevices,
    required int maxActiveSessionsAllowed,
    required int activeSessions,
  }) {
    if (maxDevicesAllowed < 1 ||
        maxDevicesAllowed > maximumSlotsPerUser ||
        maxActiveSessionsAllowed < 1 ||
        maxActiveSessionsAllowed > maximumSlotsPerUser) {
      throw ArgumentError('Access limits must be between 1 and 10.');
    }
    if (registeredDevices < 0 || activeSessions < 0) {
      throw ArgumentError('Access usage counts cannot be negative.');
    }
    return AccessUsageSummary._(
      maxDevicesAllowed: maxDevicesAllowed,
      registeredDevices: registeredDevices,
      maxActiveSessionsAllowed: maxActiveSessionsAllowed,
      activeSessions: activeSessions,
    );
  }

  const AccessUsageSummary._({
    required this.maxDevicesAllowed,
    required this.registeredDevices,
    required this.maxActiveSessionsAllowed,
    required this.activeSessions,
  });

  int get availableDeviceSlots =>
      (maxDevicesAllowed - registeredDevices).clamp(0, maxDevicesAllowed);

  int get availableSessionSlots => (maxActiveSessionsAllowed - activeSessions)
      .clamp(0, maxActiveSessionsAllowed);

  int get overLimitDeviceCount =>
      (registeredDevices - maxDevicesAllowed).clamp(0, registeredDevices);

  int get overLimitSessionCount =>
      (activeSessions - maxActiveSessionsAllowed).clamp(0, activeSessions);
}
