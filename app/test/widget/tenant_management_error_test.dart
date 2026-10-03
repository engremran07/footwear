import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/models/tenant_model.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/tenant_provider.dart';
import 'package:footwear_erp/providers/user_provider.dart';
import 'package:footwear_erp/screens/tenant_management_screen.dart';

void main() {
  testWidgets('workspace creation shows mapped error instead of silently failing', (
    tester,
  ) async {
    final user = UserModel(
      id: 'admin-1',
      email: 'admin@example.com',
      displayName: 'Platform Admin',
      role: UserRole.superAdmin,
      active: true,
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(user)),
          tenantsProvider.overrideWith((ref) => Stream.value(const <TenantModel>[])),
          allUsersProvider.overrideWith((ref) => Stream.value(const <UserModel>[])),
          tenantManagementNotifierProvider.overrideWith(
            () => _ThrowingTenantManagementNotifier(),
          ),
        ],
        child: const MaterialApp(home: TenantManagementScreen()),
      ),
    );

    await tester.pump();
    await tester.tap(find.byIcon(Icons.add_business));
    await tester.pump();

    await tester.enterText(find.byType(TextField).at(0), 'Alpha Workspace');
    await tester.enterText(find.byType(TextField).at(1), 'alpha');
    await tester.tap(find.widgetWithText(FilledButton, 'Create workspace'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('This item already exists.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _ThrowingTenantManagementNotifier extends TenantManagementNotifier {
  @override
  Future<void> createTenant({
    required String name,
    required String slug,
    required bool requireDevicePairing,
    required bool allowAdminResetOnly,
    required int maxDevicesAllowed,
    required int maxActiveSessionsAllowed,
    String? ownerUserId,
  }) async {
    throw StateError('Workspace slug already exists: alpha');
  }
}
