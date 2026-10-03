import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/utils/role_names.dart';

void main() {
  test('canonicalizes accepted legacy and tenant-aware roles', () {
    expect(canonicalRoleName(' Manager '), 'admin');
    expect(canonicalRoleName('tenant-admin'), 'tenant_admin');
    expect(canonicalRoleName('SuperAdmin'), 'super_admin');
    expect(canonicalRoleName('seller'), 'seller');
  });

  test('keeps unknown and empty role values explicit', () {
    expect(canonicalRoleName('workspace_owner'), 'unknown');
    expect(canonicalRoleName('  '), 'unknown');
  });
}
