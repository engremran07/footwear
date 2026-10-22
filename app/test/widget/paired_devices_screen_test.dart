import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/device_registration_model.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/tenant_provider.dart';
import 'package:footwear_erp/screens/paired_devices_screen.dart';

void main() {
  testWidgets('paired device row shows account and device metadata', (
    tester,
  ) async {
    final timestamp = Timestamp.fromDate(DateTime(2026, 10, 18, 9));
    final admin = UserModel(
      id: 'tenant-admin-1',
      email: 'admin@example.com',
      displayName: 'Workspace Admin',
      role: UserRole.tenantAdmin,
      tenantId: 'workspace-1',
      active: true,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    final device = DeviceRegistrationModel(
      id: 'device_installation-id-1234',
      userId: admin.id,
      tenantId: 'workspace-1',
      slotNumber: 0,
      deviceId: 'installation-id-1234',
      brand: 'Samsung',
      model: 'SM-A576B',
      platform: 'android',
      osVersion: '16',
      appVersion: '3.9.79+705',
      status: 'active',
      registeredAt: timestamp,
      lastSeenAt: timestamp,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(admin)),
          tenantDeviceRegistryProvider.overrideWith(
            (ref, tenantId) => Stream.value([device]),
          ),
          tenantAccessRegistryUsersProvider.overrideWith(
            (ref, tenantId) => Stream.value([admin]),
          ),
        ],
        child: const MaterialApp(
          home: PairedDevicesScreen(tenantId: 'workspace-1'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Samsung SM-A576B'), findsOneWidget);
    expect(find.textContaining('Workspace Admin'), findsOneWidget);
    expect(find.textContaining('admin@example.com'), findsOneWidget);
    expect(find.textContaining('3.9.79+705'), findsOneWidget);
    expect(find.textContaining('16'), findsOneWidget);
  });
}
