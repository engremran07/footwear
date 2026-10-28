import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/route_provider.dart';
import 'package:footwear_erp/providers/tenant_provider.dart';
import 'package:footwear_erp/providers/user_provider.dart';
import 'package:footwear_erp/screens/users_list_screen.dart';
import 'package:footwear_erp/widgets/error_state.dart';
import 'package:footwear_erp/widgets/shimmer_loading.dart';

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
          authStateProvider.overrideWith(
            (ref) => Stream.value(_TestFirebaseUser(superAdmin.id)),
          ),
          authUserProvider.overrideWith((ref) => Stream.value(superAdmin)),
        ],
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: UsersListScreen(),
          ),
        ),
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
          authStateProvider.overrideWith(
            (ref) => Stream.value(_TestFirebaseUser(admin.id)),
          ),
          authUserProvider.overrideWith((ref) => Stream.value(admin)),
          tenantUsersProvider(
            'tenant-1',
          ).overrideWith((ref) => Stream.value([seller])),
        ],
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: UsersListScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Seller One'), findsOneWidget);
    expect(find.text('seller@example.com'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('user creation errors remain visible inside the dialog', (
    tester,
  ) async {
    final createGate = Completer<void>();
    final notifier = _DuplicateEmailUserManagementNotifier(createGate);
    final now = Timestamp.now();
    final tenantAdmin = UserModel(
      id: 'tenant-admin',
      email: 'admin@example.com',
      displayName: 'Workspace Admin',
      role: UserRole.tenantAdmin,
      tenantId: 'tenant-1',
      active: true,
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(_TestFirebaseUser(tenantAdmin.id)),
          ),
          authUserProvider.overrideWith((ref) => Stream.value(tenantAdmin)),
          tenantUsersProvider('tenant-1').overrideWith(
            (ref) => Stream.value([tenantAdmin]),
          ),
          routesProvider.overrideWith((ref) => Stream.value(const [])),
          userManagementNotifierProvider.overrideWith(() => notifier),
        ],
        child: const MaterialApp(home: UsersListScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Workspace Admin — workspace access'), findsNothing);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('user_create_name')),
      'Second Workspace User',
    );
    await tester.enterText(
      find.byKey(const Key('user_create_email')),
      'existing@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('user_create_password')),
      'secure-pass-123',
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supervisor — business operations').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create'));
    await tester.pump();

    expect(notifier.createCalls, 1);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton).last).onPressed,
      isNull,
    );
    createGate.complete();
    await tester.pumpAndSettle();

    final duplicateEmailMessage = find.text(
      'This email is already registered.',
    );
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: duplicateEmailMessage,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('user profile stream failure shows mapped retry state', (
    tester,
  ) async {
    var profileSubscriptions = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(_TestFirebaseUser('admin-1')),
          ),
          authUserProvider.overrideWith((ref) {
            profileSubscriptions++;
            return Stream<UserModel?>.error(
              FirebaseException(
                plugin: 'cloud_firestore',
                code: 'permission-denied',
              ),
            );
          }),
        ],
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: UsersListScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final subscriptionsBeforeRetry = profileSubscriptions;
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(ShimmerLoading), findsNothing);
    expect(subscriptionsBeforeRetry, greaterThan(0));

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(profileSubscriptions, greaterThan(subscriptionsBeforeRetry));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'missing user profile shows access feedback, not endless loading',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(
              (ref) => Stream.value(_TestFirebaseUser('admin-1')),
            ),
            authUserProvider.overrideWith((ref) => Stream.value(null)),
          ],
          child: const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: UsersListScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Access Denied'), findsOneWidget);
      expect(find.byType(ShimmerLoading), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

class _TestFirebaseUser implements User {
  @override
  final String uid;

  _TestFirebaseUser(this.uid);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DuplicateEmailUserManagementNotifier extends UserManagementNotifier {
  final Completer<void> createGate;
  var createCalls = 0;

  _DuplicateEmailUserManagementNotifier(this.createGate);

  @override
  Future<String> createUser({
    required String email,
    required String password,
    required String displayName,
    required String role,
    String? phone,
    List<String> assignedRouteIds = const [],
    List<String> assignedRouteNames = const [],
    String? tenantId,
  }) async {
    createCalls++;
    await createGate.future;
    throw FirebaseAuthException(code: 'email-already-in-use');
  }
}
