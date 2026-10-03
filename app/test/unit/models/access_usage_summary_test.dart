import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/models/access_usage_summary.dart';

void main() {
  group('AccessUsageSummary', () {
    test('calculates remaining device and session slots', () {
      final summary = AccessUsageSummary(
        maxDevicesAllowed: 3,
        registeredDevices: 2,
        maxActiveSessionsAllowed: 2,
        activeSessions: 1,
      );

      expect(summary.availableDeviceSlots, 1);
      expect(summary.availableSessionSlots, 1);
      expect(summary.overLimitDeviceCount, 0);
      expect(summary.overLimitSessionCount, 0);
    });

    test('policy reductions preserve existing registrations as over limit', () {
      final summary = AccessUsageSummary(
        maxDevicesAllowed: 3,
        registeredDevices: 4,
        maxActiveSessionsAllowed: 1,
        activeSessions: 2,
      );

      expect(summary.availableDeviceSlots, 0);
      expect(summary.availableSessionSlots, 0);
      expect(summary.overLimitDeviceCount, 1);
      expect(summary.overLimitSessionCount, 1);
    });

    test('rejects invalid policy or negative usage values', () {
      expect(
        () => AccessUsageSummary(
          maxDevicesAllowed: 0,
          registeredDevices: 0,
          maxActiveSessionsAllowed: 1,
          activeSessions: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => AccessUsageSummary(
          maxDevicesAllowed: 1,
          registeredDevices: -1,
          maxActiveSessionsAllowed: 1,
          activeSessions: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}
