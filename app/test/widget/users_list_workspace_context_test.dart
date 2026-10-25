import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/tenant_provider.dart';
import 'package:footwear_erp/screens/users_list_screen.dart';

void main() {
  testWidgets('root super-admin must select a workspace before user actions', (
    tester,
  ) async {
    final now = Timestamp.now();
    final superAdmin = UserModel(
      id: 'super-admin',
      email: 'admin@example.com',
      displayName: 'Platform Admin',
      role: UserRole.superAdmin,
      active: true,
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(superAdmin)),
        ],
        child: const MaterialApp(home: UsersListScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Select workspace'), findsOneWidget);
    expect(find.text('Workspaces'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy admin receives the active workspace user stream', (
    tester,
  ) async {
    final now = Timestamp.now();
    final admin = UserModel(
      id: 'admin-1',
      email: 'admin@example.com',
      displayName: 'Legacy Admin',
      role: UserRole.admin,
      tenantId: 'tenant-1',
      active: true,
      createdAt: now,
      updatedAt: now,
    );
    final seller = UserModel(
      id: 'seller-1',
      email: 'seller@example.com',
      displayName: 'Seller One',
      role: UserRole.seller,
      tenantId: 'tenant-1',
      assignedRouteIds: const ['route-1'],
      active: true,
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(admin)),
          tenantUsersProvider(
            'tenant-1',
          ).overrideWith((ref) => Stream.value([seller])),
        ],
        child: const MaterialApp(home: UsersListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Seller One'), findsOneWidget);
    expect(find.text('seller@example.com'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
