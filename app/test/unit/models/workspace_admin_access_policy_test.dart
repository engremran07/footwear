import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/models/workspace_admin_access_policy.dart';

void main() {
  group('WorkspaceAdminAccessPolicy', () {
    test('uses conservative defaults when the platform policy is absent', () {
      final policy = WorkspaceAdminAccessPolicy.fromJson(null);

      expect(policy.maxDevicesAllowed, 3);
      expect(policy.maxActiveSessionsAllowed, 2);
    });

    test('round-trips configured platform-wide workspace-admin limits', () {
      const policy = WorkspaceAdminAccessPolicy(
        maxDevicesAllowed: 4,
        maxActiveSessionsAllowed: 3,
      );

      expect(WorkspaceAdminAccessPolicy.fromJson(policy.toJson()), policy);
    });

    test('rejects limits outside the supported slot range', () {
      expect(
        () => WorkspaceAdminAccessPolicy.fromJson({
          'workspace_admin_max_devices_allowed': 11,
        }),
        throwsFormatException,
      );
    });
  });
}
