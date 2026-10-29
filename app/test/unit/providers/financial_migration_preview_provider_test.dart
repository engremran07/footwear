import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/database_backup_provider.dart';

void main() {
  final now = Timestamp.fromDate(DateTime.utc(2026, 1, 1));

  test('workspace admin can preview a verified same-tenant backup', () async {
    final user = _user(role: UserRole.tenantAdmin, now: now);
    final container = _container(user);
    addTearDown(container.dispose);
    final authSubscription = container.listen(authUserProvider, (_, _) {});
    addTearDown(authSubscription.close);

    final plan = await container
        .read(databaseBackupProvider.notifier)
        .previewFinancialMinorUnits(_backup());

    expect(plan.tenantId, 'tenant-1');
    expect(plan.documentCount, 1);
    expect(plan.isClean, isTrue);
    expect(plan.documents.single.financialMinorUnits['balance'], 1250);
  });

  test(
    'rejects invalid checksum, wrong scope, and cross-tenant backups',
    () async {
      final user = _user(role: UserRole.admin, now: now);
      final container = _container(user);
      addTearDown(container.dispose);
      final authSubscription = container.listen(authUserProvider, (_, _) {});
      addTearDown(authSubscription.close);
      final notifier = container.read(databaseBackupProvider.notifier);

      await expectLater(
        notifier.previewFinancialMinorUnits(_backup(checksumOk: false)),
        throwsStateError,
      );
      await expectLater(
        notifier.previewFinancialMinorUnits(_backup(scope: 'seller_route')),
        throwsStateError,
      );
      await expectLater(
        notifier.previewFinancialMinorUnits(_backup(tenantId: 'tenant-2')),
        throwsStateError,
      );
    },
  );

  test('rejects incomplete backup counts', () async {
    final user = _user(role: UserRole.admin, now: now);
    final container = _container(user);
    addTearDown(container.dispose);
    final authSubscription = container.listen(authUserProvider, (_, _) {});
    addTearDown(authSubscription.close);

    await expectLater(
      container
          .read(databaseBackupProvider.notifier)
          .previewFinancialMinorUnits(
            _backup(
              counts: const {'shops': 2, 'transactions': 0, 'invoices': 0},
            ),
          ),
      throwsFormatException,
    );
  });

  test('denies sellers and platform super-admins', () async {
    for (final role in [UserRole.seller, UserRole.superAdmin]) {
      final user = _user(role: role, now: now);
      final container = _container(user);
      addTearDown(container.dispose);
      final authSubscription = container.listen(authUserProvider, (_, _) {});
      addTearDown(authSubscription.close);

      await expectLater(
        container
            .read(databaseBackupProvider.notifier)
            .previewFinancialMinorUnits(_backup()),
        throwsStateError,
      );
      await expectLater(
        container
            .read(databaseBackupProvider.notifier)
            .backfillFinancialMinorUnits(),
        throwsStateError,
      );
    }
  });
}

ProviderContainer _container(UserModel user) => ProviderContainer(
  overrides: [
    authUserProvider.overrideWith((ref) => Stream.value(user)),
    databaseBackupProvider.overrideWith(_PreviewNotifier.new),
  ],
);

UserModel _user({required UserRole role, required Timestamp now}) => UserModel(
  id: 'user-1',
  email: 'admin@example.com',
  displayName: 'Workspace Admin',
  role: role,
  tenantId: role == UserRole.superAdmin ? null : 'tenant-1',
  active: true,
  createdAt: now,
  updatedAt: now,
);

BackupPreview _backup({
  bool checksumOk = true,
  String scope = 'workspace',
  String tenantId = 'tenant-1',
  Map<String, int> counts = const {
    'shops': 1,
    'transactions': 0,
    'invoices': 0,
  },
}) => BackupPreview(
  appVersion: 'test',
  createdAt: '2026-01-01',
  tenantId: tenantId,
  scope: scope,
  routeIds: const [],
  counts: counts,
  checksumOk: checksumOk,
  rawData: {
    'shops': [
      {'__id': 'shop-1', 'tenant_id': 'tenant-1', 'balance': 12.5},
    ],
    'transactions': <Map<String, dynamic>>[],
    'invoices': <Map<String, dynamic>>[],
  },
);

class _PreviewNotifier extends DatabaseBackupNotifier {
  @override
  void build() {}
}
