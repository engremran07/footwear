import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/constants/collections.dart';
import 'package:footwear_erp/core/utils/financial_minor_unit_migration.dart';
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
    final cleanPlan = _plan();
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
            .backfillFinancialMinorUnits(plan: cleanPlan),
        throwsStateError,
      );
    }
  });

  test('administrator backfill rejects a preview with exceptions', () async {
    final user = _user(role: UserRole.admin, now: now);
    final container = _container(user);
    addTearDown(container.dispose);
    final authSubscription = container.listen(authUserProvider, (_, _) {});
    addTearDown(authSubscription.close);
    final blockedPlan = FinancialMinorUnitMigration.preview(
      tenantId: 'tenant-1',
      collections: {
        'shops': [
          {'__id': 'shop-1', 'tenant_id': 'tenant-1', 'balance': 4.251},
        ],
        'transactions': <Map<String, dynamic>>[],
        'invoices': <Map<String, dynamic>>[],
      },
    );

    await expectLater(
      container
          .read(databaseBackupProvider.notifier)
          .backfillFinancialMinorUnits(plan: blockedPlan),
      throwsStateError,
    );
  });

  test(
    'financial backfill limits transactional pages to 100 documents',
    () async {
      final container = _container(_user(role: UserRole.admin, now: now));
      addTearDown(container.dispose);
      final authSubscription = container.listen(authUserProvider, (_, _) {});
      addTearDown(authSubscription.close);

      await expectLater(
        container
            .read(databaseBackupProvider.notifier)
            .backfillFinancialMinorUnits(plan: _plan(), pageSize: 101),
        throwsArgumentError,
      );
    },
  );

  test(
    'backfill transaction uses current values and preserves legacy fields',
    () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection(Collections.tenants).doc('tenant-1').set({
        'active': true,
      });
      await firestore.collection(Collections.shops).doc('shop-1').set({
        'tenant_id': 'tenant-1',
        'balance': 14.25,
        'financial_minor_units': {'balance': 999},
      });
      final container = _container(
        _user(role: UserRole.admin, now: now),
        firestore: firestore,
      );
      addTearDown(container.dispose);
      final authSubscription = container.listen(authUserProvider, (_, _) {});
      addTearDown(authSubscription.close);

      final updatedCount = await container
          .read(databaseBackupProvider.notifier)
          .backfillFinancialMinorUnits(plan: _plan(), pageSize: 1);
      final shop = await firestore
          .collection(Collections.shops)
          .doc('shop-1')
          .get();

      expect(updatedCount, 1);
      expect(shop.data()?['balance'], 14.25);
      expect(shop.data()?['financial_minor_units'], {'balance': 1425});
    },
  );

  test(
    'backfill rejects an inactive workspace before changing records',
    () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection(Collections.tenants).doc('tenant-1').set({
        'active': false,
      });
      await firestore.collection(Collections.shops).doc('shop-1').set({
        'tenant_id': 'tenant-1',
        'balance': 12.5,
      });
      final container = _container(
        _user(role: UserRole.admin, now: now),
        firestore: firestore,
      );
      addTearDown(container.dispose);
      final authSubscription = container.listen(authUserProvider, (_, _) {});
      addTearDown(authSubscription.close);

      await expectLater(
        container
            .read(databaseBackupProvider.notifier)
            .backfillFinancialMinorUnits(plan: _plan(), pageSize: 1),
        throwsStateError,
      );
      final shop = await firestore
          .collection(Collections.shops)
          .doc('shop-1')
          .get();

      expect(shop.data()?['balance'], 12.5);
      expect(shop.data(), isNot(contains('financial_minor_units')));
    },
  );
}

ProviderContainer _container(UserModel user, {FirebaseFirestore? firestore}) =>
    ProviderContainer(
      overrides: [
        authUserProvider.overrideWith((ref) => Stream.value(user)),
        if (firestore != null)
          databaseBackupFirestoreProvider.overrideWithValue(firestore),
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

FinancialMinorUnitMigrationPlan _plan() => FinancialMinorUnitMigration.preview(
  tenantId: 'tenant-1',
  collections: {
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
