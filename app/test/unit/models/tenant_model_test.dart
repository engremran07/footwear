import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/models/tenant_model.dart';

void main() {
  group('TenantModel', () {
    test('round-trips through fromJson/toJson', () {
      final ts = Timestamp.fromMillisecondsSinceEpoch(1);
      final original = TenantModel(
        id: 'tenant-1',
        name: 'Acme Shoes',
        slug: 'acme',
        plan: 'pro',
        active: true,
        isTrial: false,
        maxDevicesAllowed: 3,
        createdAt: ts,
        updatedAt: ts,
        ownerUserId: 'owner-1',
        primaryColor: '#123456',
        accentColor: '#654321',
      );

      final json = original.toJson();
      final restored = TenantModel.fromJson(json, original.id);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.slug, original.slug);
      expect(restored.plan, original.plan);
      expect(restored.maxDevicesAllowed, original.maxDevicesAllowed);
      expect(restored.ownerUserId, original.ownerUserId);
      expect(restored.primaryColor, original.primaryColor);
      expect(restored.accentColor, original.accentColor);
    });

    test('uses defaults for missing optional fields', () {
      final m = TenantModel.fromJson({
        'name': 'Demo',
        'slug': 'demo',
      }, 'tenant-2');
      expect(m.name, 'Demo');
      expect(m.slug, 'demo');
      expect(m.active, isTrue);
      expect(m.isTrial, isFalse);
      expect(m.plan, isNull);
      expect(m.maxDevicesAllowed, 1);
    });
  });
}
