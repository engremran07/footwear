import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/utils/tenant_scope.dart';

void main() {
  group('TenantScope', () {
    test('normalizes blank tenant ids to null', () {
      expect(TenantScope.normalize('   '), isNull);
      expect(TenantScope.normalize(null), isNull);
    });

    test('applies tenant_id to data payloads', () {
      final data = TenantScope.applyToData({
        'name': 'Demo',
      }, tenantId: 'tenant-1');
      expect(data['tenant_id'], 'tenant-1');
      expect(data['name'], 'Demo');
    });

    test('extracts tenant_id from user data', () {
      final tenantId = TenantScope.fromUserData({'tenant_id': 'tenant-2'});
      expect(tenantId, 'tenant-2');
    });

    test('matches tenant ids for provider filtering', () {
      final data = {'tenant_id': 'tenant-2'};
      expect(TenantScope.matchesTenant(data, 'tenant-2'), isTrue);
      expect(TenantScope.matchesTenant(data, 'tenant-3'), isFalse);
      expect(
        TenantScope.matchesTenant({'tenant_id': ' '}, 'tenant-2'),
        isFalse,
      );
    });
  });
}
