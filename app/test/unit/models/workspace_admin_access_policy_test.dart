import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/models/workspace_admin_access_policy.dart';

void main() {
  group('WorkspaceAdminAccessPolicy', () {
    test('uses the default active-session cap when policy is absent', () {
      final policy = WorkspaceAdminAccessPolicy.fromJson(null);

      expect(policy.maxActiveSessionsAllowed, 2);
    });

    test('round-trips the platform-wide workspace-admin session limit', () {
      const policy = WorkspaceAdminAccessPolicy(maxActiveSessionsAllowed: 3);

      expect(WorkspaceAdminAccessPolicy.fromJson(policy.toJson()), policy);
    });

    test('ignores the legacy workspace-admin device limit', () {
      final policy = WorkspaceAdminAccessPolicy.fromJson({
        'workspace_admin_max_devices_allowed': 3,
        'workspace_admin_max_active_sessions_allowed': 4,
      });

      expect(policy.maxActiveSessionsAllowed, 4);
    });

    test('rejects limits outside the supported slot range', () {
      expect(
        () => WorkspaceAdminAccessPolicy.fromJson({
          'workspace_admin_max_active_sessions_allowed': 11,
        }),
        throwsFormatException,
      );
    });
  });
}
