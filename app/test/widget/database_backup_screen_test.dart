import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/models/tenant_model.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/database_backup_provider.dart';
import 'package:footwear_erp/providers/tenant_provider.dart';
import 'package:footwear_erp/screens/database_backup_screen.dart';

void main() {
  late Directory archiveDirectory;
  late LocalBackupFile archive;
  late LocalBackupFile legacyArchive;
  late _FakeDatabaseBackupNotifier backupNotifier;

  setUp(() async {
    archiveDirectory = await Directory.systemTemp.createTemp('shoeserp-backup');
    final file = File('${archiveDirectory.path}/test.shoesbackup');
    await file.writeAsBytes([1, 2, 3]);
    archive = LocalBackupFile(file: file, modifiedAt: DateTime.utc(2026));
    final legacyFile = File('${archiveDirectory.path}/legacy.json');
    await legacyFile.writeAsString('{"metadata":{},"shops":[]}');
    legacyArchive = LocalBackupFile(
      file: legacyFile,
      modifiedAt: DateTime.utc(2026),
    );
    backupNotifier = _FakeDatabaseBackupNotifier(
      archive,
      additionalArchives: [legacyArchive],
    );
  });

  tearDown(() async {
    await archiveDirectory.delete(recursive: true);
  });

  testWidgets('local archive can be deleted from the shared backup picker', (
    tester,
  ) async {
    final now = Timestamp.now();
    final user = UserModel(
      id: 'tenant-admin-1',
      email: 'admin@example.com',
      displayName: 'Workspace Admin',
      role: UserRole.tenantAdmin,
      tenantId: 'tenant-1',
      active: true,
      createdAt: now,
      updatedAt: now,
    );
    final tenant = TenantModel(
      id: 'tenant-1',
      name: 'Workspace One',
      slug: 'workspace-one',
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(user)),
          tenantProvider(tenant.id).overrideWith((ref) => Stream.value(tenant)),
          databaseBackupProvider.overrideWith(() => backupNotifier),
        ],
        child: const MaterialApp(home: DatabaseBackupScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Save backup to phone storage'),
      300,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    final createBackup = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save backup to phone storage'),
    );
    expect(createBackup.onPressed, isNotNull);
    expect(find.text('Save backup to phone storage'), findsOneWidget);
    expect(find.text('Backup Now'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Financial precision migration'),
      300,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('Financial precision migration'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Restore from app backup'),
      300,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('Restore from app backup'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Restore from phone storage'),
      300,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('Restore from phone storage'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Restore from Google Drive'),
      300,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('Restore from Google Drive'), findsOneWidget);
    expect(
      find.text(
        'Automatic Google Drive backup is unavailable until this build is configured.',
      ),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.text('Restore from app backup'),
      -300,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore from app backup'));
    await tester.pumpAndSettle();
    expect(find.text('test.shoesbackup'), findsOneWidget);
    expect(find.text('legacy.json'), findsOneWidget);
    final legacyTile = find.ancestor(
      of: find.text('legacy.json'),
      matching: find.byType(ListTile),
    );
    expect(
      tester
          .widgetList<IconButton>(
            find.descendant(of: legacyTile, matching: find.byType(IconButton)),
          )
          .first
          .onPressed,
      isNull,
    );

    await tester.tap(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    expect(
      find.text('Permanently delete "test.shoesbackup" from this device?'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(backupNotifier.deleted, isTrue);
    expect(find.text('Device backup deleted'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unscoped super-admin cannot start workspace backup actions', (
    tester,
  ) async {
    final now = Timestamp.now();
    final user = UserModel(
      id: 'platform-admin-1',
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
          authUserProvider.overrideWith((ref) => Stream.value(user)),
          databaseBackupProvider.overrideWith(() => backupNotifier),
        ],
        child: const MaterialApp(home: DatabaseBackupScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final createBackup = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save backup to phone storage'),
    );
    expect(createBackup.onPressed, isNull);

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    final restoreLocal = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Restore from app backup'),
    );
    expect(restoreLocal.onPressed, isNull);
    final restorePhone = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Restore from phone storage'),
    );
    expect(restorePhone.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected super-admin can use workspace backup controls', (
    tester,
  ) async {
    final now = Timestamp.now();
    final user = UserModel(
      id: 'platform-admin-1',
      email: 'admin@example.com',
      displayName: 'Platform Admin',
      role: UserRole.superAdmin,
      activeWorkspaceId: 'tenant-1',
      activeWorkspaceReason: 'Support backup verification',
      active: true,
      createdAt: now,
      updatedAt: now,
    );
    final tenant = TenantModel(
      id: 'tenant-1',
      name: 'Workspace One',
      slug: 'workspace-one',
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(user)),
          tenantProvider(tenant.id).overrideWith((ref) => Stream.value(tenant)),
          databaseBackupProvider.overrideWith(() => backupNotifier),
        ],
        child: const MaterialApp(home: DatabaseBackupScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save backup to phone storage'),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Restore from phone storage'),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      find.text(
        'Only the selected workspace profile and its user profiles are included. Business records are excluded.',
      ),
      findsOneWidget,
    );
    expect(find.text('Routes'), findsNothing);
    expect(find.text('Financial precision migration'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('seller can access route backup and limited restore controls', (
    tester,
  ) async {
    final now = Timestamp.now();
    final user = UserModel(
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
    final tenant = TenantModel(
      id: 'tenant-1',
      name: 'Workspace One',
      slug: 'workspace-one',
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(user)),
          tenantProvider(tenant.id).overrideWith((ref) => Stream.value(tenant)),
          databaseBackupProvider.overrideWith(() => backupNotifier),
        ],
        child: const MaterialApp(home: DatabaseBackupScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Includes assigned routes, shops, your inventory, transactions, and invoices. Restore imports only your unlinked cash transactions.',
      ),
      findsOneWidget,
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await tester.pumpAndSettle();

    final localBackup = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save backup to phone storage'),
    );
    expect(localBackup.onPressed, isNotNull);
    expect(find.text('Routes'), findsOneWidget);
    expect(find.text('Shops'), findsOneWidget);
    expect(find.text('Transactions'), findsOneWidget);
    expect(find.text('Invoices'), findsOneWidget);
    expect(find.text('Products & Variants'), findsNothing);
    expect(find.text('Workspace settings'), findsNothing);

    final localRestore = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Restore from phone storage'),
    );
    expect(localRestore.onPressed, isNotNull);
    expect(find.text('Restore from app backup'), findsOneWidget);
    expect(find.text('Financial precision migration'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selected workspace metadata error retries before backup is enabled',
    (tester) async {
      var tenantAttempts = 0;
      final now = Timestamp.now();
      final user = UserModel(
        id: 'tenant-admin-1',
        email: 'admin@example.com',
        displayName: 'Workspace Admin',
        role: UserRole.tenantAdmin,
        tenantId: 'tenant-1',
        active: true,
        createdAt: now,
        updatedAt: now,
      );
      final tenant = TenantModel(
        id: 'tenant-1',
        name: 'Workspace One',
        slug: 'workspace-one',
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith((ref) => Stream.value(user)),
            tenantProvider(tenant.id).overrideWith((ref) {
              tenantAttempts += 1;
              return tenantAttempts == 1
                  ? Stream.error(StateError('workspace unavailable'))
                  : Stream.value(tenant);
            }),
            databaseBackupProvider.overrideWith(() => backupNotifier),
          ],
          child: const MaterialApp(home: DatabaseBackupScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Something went wrong. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Workspace One'), findsNothing);
      await tester.drag(find.byType(ListView).first, const Offset(0, -700));
      await tester.pumpAndSettle();
      final backupButton = find.widgetWithText(
        FilledButton,
        'Save backup to phone storage',
      );
      expect(tester.widget<FilledButton>(backupButton).onPressed, isNull);

      await tester.drag(find.byType(ListView).first, const Offset(0, 700));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(tenantAttempts, greaterThan(1));
      expect(find.text('Workspace One'), findsNothing);
      expect(find.text('Workspace backup scope is ready.'), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(backupButton).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );
}

class _FakeDatabaseBackupNotifier extends DatabaseBackupNotifier {
  final LocalBackupFile archive;
  final List<LocalBackupFile> additionalArchives;
  bool deleted = false;
  bool listed = false;

  _FakeDatabaseBackupNotifier(
    this.archive, {
    this.additionalArchives = const [],
  });

  @override
  void build() {}

  @override
  Future<bool> getAutoEnabled() async => false;

  @override
  Future<int> getIntervalMinutes() async => 1440;

  @override
  Future<DateTime?> getLastBackupAt() async => null;

  @override
  Future<DateTime?> getLastDriveBackupAt() async => null;

  @override
  Future<DateTime?> getLastRestoreAt() async => null;

  @override
  Future<String?> getLastRestoreBy() async => null;

  @override
  Future<List<LocalBackupFile>> listLocalBackups({
    required String tenantId,
    required String creatorUid,
  }) async {
    listed = true;
    return [archive, ...additionalArchives];
  }

  @override
  Future<void> deleteLocalBackup(
    LocalBackupFile backup, {
    required String tenantId,
    required String creatorUid,
  }) async {
    deleted = true;
  }
}
