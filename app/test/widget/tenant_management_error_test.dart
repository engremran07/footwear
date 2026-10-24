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
  testWidgets('new workspace provisions its owner as tenant admin', (
    tester,
  ) async {
    final user = UserModel(
      id: 'platform-admin',
      email: 'platform@example.com',
      displayName: 'Platform Admin',
      role: UserRole.superAdmin,
      active: true,
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    );
    final tenantNotifier = _RecordingTenantManagementNotifier();
    final authNotifier = _RecordingAuthNotifier();
    final ownerNotifier = _RecordingUserManagementNotifier();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(user)),
          tenantsProvider.overrideWith(
            (ref) => Stream.value(const <TenantModel>[]),
          ),
          tenantManagementNotifierProvider.overrideWith(() => tenantNotifier),
          authNotifierProvider.overrideWith(() => authNotifier),
          userManagementNotifierProvider.overrideWith(() => ownerNotifier),
        ],
        child: const MaterialApp(home: TenantManagementScreen()),
      ),
    );

    await tester.pump();
    await tester.tap(find.byIcon(Icons.add_business));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('workspace_name')), 'Alpha');
    await tester.enterText(find.byKey(const Key('workspace_slug')), 'alpha');
    final ownerNameField = find.byKey(const Key('workspace_owner_name'));
    await tester.ensureVisible(ownerNameField);
    await tester.enterText(ownerNameField, 'Workspace Owner');
    final ownerEmailField = find.byKey(const Key('workspace_owner_email'));
    await tester.ensureVisible(ownerEmailField);
    await tester.enterText(ownerEmailField, 'owner@example.com');
    final ownerPasswordField = find.byKey(
      const Key('workspace_owner_password'),
    );
    await tester.ensureVisible(ownerPasswordField);
    await tester.enterText(ownerPasswordField, 'secure-pass-123');
    await tester.tap(find.widgetWithText(FilledButton, 'Create workspace'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(ownerNotifier.createdRole, 'tenant_admin');
    expect(ownerNotifier.createdTenantId, 'alpha');
    expect(tenantNotifier.assignedOwnerId, 'owner-uid');
    expect(authNotifier.selectedWorkspaceId, 'alpha');
    expect(authNotifier.accessEnded, isTrue);
  });

  testWidgets('existing workspace owner selector excludes seller accounts', (
    tester,
  ) async {
    final tenant = TenantModel(
      id: 'alpha',
      name: 'Alpha',
      slug: 'alpha',
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    );
    final user = UserModel(
      id: 'platform-admin',
      email: 'platform@example.com',
      displayName: 'Platform Admin',
      role: UserRole.superAdmin,
      active: true,
      activeWorkspaceId: tenant.id,
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    );
    final owner = UserModel(
      id: 'owner-1',
      email: 'owner@example.com',
      displayName: 'Workspace Owner',
      role: UserRole.tenantAdmin,
      tenantId: tenant.id,
      active: true,
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    );
    final seller = UserModel(
      id: 'seller-1',
      email: 'seller@example.com',
      displayName: 'Seller Account',
      role: UserRole.seller,
      tenantId: tenant.id,
      active: true,
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(user)),
          tenantsProvider.overrideWith((ref) => Stream.value([tenant])),
          tenantUsersProvider.overrideWith(
            (ref, tenantId) => Stream.value([owner, seller]),
          ),
        ],
        child: const MaterialApp(home: TenantManagementScreen()),
      ),
    );

    await tester.pump();
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final ownerSelector = find.byKey(const Key('workspace_owner_selector'));
    await tester.ensureVisible(ownerSelector);
    await tester.tap(ownerSelector);
    await tester.pump();

    expect(find.text('Workspace Owner'), findsOneWidget);
    expect(find.text('Seller Account'), findsNothing);
  });

  testWidgets(
    'tenant admins see only workspace metadata, not platform actions',
    (tester) async {
      final tenant = TenantModel(
        id: 'workspace-1',
        name: 'Workspace One',
        slug: 'workspace-one',
        createdAt: Timestamp.now(),
        updatedAt: Timestamp.now(),
      );
      final tenantAdmin = UserModel(
        id: 'tenant-admin',
        email: 'tenant@example.com',
        displayName: 'Workspace Admin',
        role: UserRole.tenantAdmin,
        tenantId: tenant.id,
        active: true,
        createdAt: Timestamp.now(),
        updatedAt: Timestamp.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith((ref) => Stream.value(tenantAdmin)),
            tenantsProvider.overrideWith((ref) => Stream.value([tenant])),
          ],
          child: const MaterialApp(home: TenantManagementScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Workspace One'), findsOneWidget);
      expect(find.byIcon(Icons.add_business), findsNothing);
      expect(find.byIcon(Icons.edit), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('workspace create does not wait for global owner users', (
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
          tenantsProvider.overrideWith(
            (ref) => Stream.value(const <TenantModel>[]),
          ),
          allUsersProvider.overrideWith((ref) => const Stream.empty()),
        ],
        child: const MaterialApp(home: TenantManagementScreen()),
      ),
    );

    await tester.pump();
    await tester.tap(find.byIcon(Icons.add_business));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);

    final createButton = find.widgetWithText(FilledButton, 'Create workspace');
    await tester.tap(createButton);
    await tester.pump();
    expect(tester.widget<FilledButton>(createButton).onPressed, isNotNull);
  });

  testWidgets(
    'workspace creation shows mapped error instead of silently failing',
    (tester) async {
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
            tenantsProvider.overrideWith(
              (ref) => Stream.value(const <TenantModel>[]),
            ),
            allUsersProvider.overrideWith(
              (ref) => Stream.value(const <UserModel>[]),
            ),
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
      final ownerNameField = find.byKey(const Key('workspace_owner_name'));
      await tester.ensureVisible(ownerNameField);
      await tester.enterText(ownerNameField, 'Workspace Owner');
      final ownerEmailField = find.byKey(const Key('workspace_owner_email'));
      await tester.ensureVisible(ownerEmailField);
      await tester.enterText(ownerEmailField, 'owner@example.com');
      final ownerPasswordField = find.byKey(
        const Key('workspace_owner_password'),
      );
      await tester.ensureVisible(ownerPasswordField);
      await tester.enterText(ownerPasswordField, 'secure-pass-123');
      await tester.tap(find.widgetWithText(FilledButton, 'Create workspace'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('This item already exists.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Create workspace'),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('selected platform admin can archive a workspace', (
    tester,
  ) async {
    final tenant = TenantModel(
      id: 'alpha',
      name: 'Alpha',
      slug: 'alpha',
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    );
    final user = UserModel(
      id: 'platform-admin',
      email: 'platform@example.com',
      displayName: 'Platform Admin',
      role: UserRole.superAdmin,
      active: true,
      activeWorkspaceId: tenant.id,
      activeWorkspaceReason: 'Workspace lifecycle audit',
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    );
    final notifier = _RecordingTenantManagementNotifier();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(user)),
          tenantsProvider.overrideWith((ref) => Stream.value([tenant])),
          tenantManagementNotifierProvider.overrideWith(() => notifier),
        ],
        child: const MaterialApp(home: TenantManagementScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive workspace'));
    await tester.pumpAndSettle();
    expect(find.text('Archive this workspace?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Archive workspace'));
    await tester.pumpAndSettle();

    expect(notifier.archivedTenantId, tenant.id);
    expect(find.text('Workspace archived'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected platform admin can restore an archived workspace', (
    tester,
  ) async {
    final tenant = TenantModel(
      id: 'alpha',
      name: 'Alpha',
      slug: 'alpha',
      active: false,
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    );
    final user = UserModel(
      id: 'platform-admin',
      email: 'platform@example.com',
      displayName: 'Platform Admin',
      role: UserRole.superAdmin,
      active: true,
      activeWorkspaceId: tenant.id,
      activeWorkspaceReason: 'Workspace lifecycle audit',
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    );
    final notifier = _RecordingTenantManagementNotifier();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(user)),
          tenantsProvider.overrideWith((ref) => Stream.value([tenant])),
          tenantManagementNotifierProvider.overrideWith(() => notifier),
        ],
        child: const MaterialApp(home: TenantManagementScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore workspace'));
    await tester.pumpAndSettle();
    expect(find.text('Restore this workspace?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Restore workspace'));
    await tester.pumpAndSettle();

    expect(notifier.restoredTenantId, tenant.id);
    expect(find.text('Workspace restored'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _RecordingTenantManagementNotifier extends TenantManagementNotifier {
  String? assignedOwnerId;
  String? archivedTenantId;
  String? restoredTenantId;

  @override
  Future<String> createTenant({
    required String name,
    required String slug,
    String? ownerUserId,
  }) async => 'alpha';

  @override
  Future<void> updateTenant(
    String tenantId, {
    required String name,
    required String slug,
    String? ownerUserId,
  }) async {}

  @override
  Future<void> assignTenantOwner(String tenantId, String ownerUserId) async {
    assignedOwnerId = ownerUserId;
  }

  @override
  Future<void> archiveTenant(String tenantId) async {
    archivedTenantId = tenantId;
  }

  @override
  Future<void> restoreTenant(String tenantId) async {
    restoredTenantId = tenantId;
  }
}

class _RecordingAuthNotifier extends AuthNotifier {
  String? selectedWorkspaceId;
  bool accessEnded = false;

  @override
  Future<void> selectWorkspace({
    required String workspaceId,
    required String reason,
  }) async {
    selectedWorkspaceId = workspaceId;
  }

  @override
  Future<void> endWorkspaceAccess() async {
    accessEnded = true;
  }
}

class _RecordingUserManagementNotifier extends UserManagementNotifier {
  String? createdRole;
  String? createdTenantId;

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
    createdRole = role;
    createdTenantId = tenantId;
    return 'owner-uid';
  }
}

class _ThrowingTenantManagementNotifier extends TenantManagementNotifier {
  @override
  Future<String> createTenant({
    required String name,
    required String slug,
    String? ownerUserId,
  }) async {
    throw StateError('Workspace slug already exists: alpha');
  }
}
