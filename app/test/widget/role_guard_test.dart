import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/utils/role_names.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/widgets/error_state.dart';
import 'package:footwear_erp/widgets/role_guard.dart';
import 'package:footwear_erp/widgets/shimmer_loading.dart';

void main() {
  testWidgets('role guard shows loading feedback while profile is unresolved', (
    tester,
  ) async {
    final profile = StreamController<UserModel?>();
    addTearDown(profile.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authUserProvider.overrideWith((ref) => profile.stream)],
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: RoleGuard(
              capability: AppCapability.manageBackup,
              child: Text('Backup content'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ShimmerLoading), findsOneWidget);
    expect(find.text('Backup content'), findsNothing);

    profile.add(_workspaceAdmin());
    await tester.pump();
    await tester.pump();

    expect(find.text('Backup content'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('role guard shows mapped profile errors with retry feedback', (
    tester,
  ) async {
    final profile = StreamController<UserModel?>();
    addTearDown(profile.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authUserProvider.overrideWith((ref) => profile.stream)],
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: RoleGuard(
              capability: AppCapability.manageBackup,
              child: Text('Backup content'),
            ),
          ),
        ),
      ),
    );
    profile.addError(
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Backup content'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('role guard keeps explicit fallback for denied roles', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(_seller())),
        ],
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: RoleGuard(
              capability: AppCapability.manageBackup,
              fallback: Text('Access denied'),
              child: Text('Backup content'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Access denied'), findsOneWidget);
    expect(find.text('Backup content'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

UserModel _workspaceAdmin() {
  final now = Timestamp.now();
  return UserModel(
    id: 'admin-1',
    email: 'admin@example.com',
    displayName: 'Workspace Admin',
    role: UserRole.admin,
    tenantId: 'tenant-1',
    active: true,
    createdAt: now,
    updatedAt: now,
  );
}

UserModel _seller() {
  final now = Timestamp.now();
  return UserModel(
    id: 'seller-1',
    email: 'seller@example.com',
    displayName: 'Seller',
    role: UserRole.seller,
    tenantId: 'tenant-1',
    active: true,
    createdAt: now,
    updatedAt: now,
  );
}
