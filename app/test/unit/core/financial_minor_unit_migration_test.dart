import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/constants/collections.dart';
import 'package:footwear_erp/core/utils/financial_minor_unit_migration.dart';

void main() {
  group('FinancialMinorUnitMigration', () {
    test('maps Firestore paths to migration schema keys', () {
      expect(
        FinancialMinorUnitMigration.collectionKeyForFirestorePath(
          Collections.shops,
        ),
        'shops',
      );
      expect(
        FinancialMinorUnitMigration.collectionKeyForFirestorePath(
          Collections.transactions,
        ),
        'transactions',
      );
      expect(
        FinancialMinorUnitMigration.collectionKeyForFirestorePath(
          Collections.invoices,
        ),
        'invoices',
      );
      expect(
        () => FinancialMinorUnitMigration.collectionKeyForFirestorePath(
          Collections.products,
        ),
        throwsArgumentError,
      );
    });

    test('converts exact cent amounts without changing their value', () {
      expect(FinancialMinorUnitMigration.toMinorUnits(125.45), 12545);
      expect(FinancialMinorUnitMigration.toMinorUnits(0.1 + 0.2), 30);
      expect(FinancialMinorUnitMigration.toMinorUnits(-3.25), -325);
    });

    test('attaches minor-unit companions to complete financial documents', () {
      final transaction = FinancialMinorUnitMigration.withMinorUnits(
        'transactions',
        {
          'amount': 10.25,
          'items': [
            {'unit_price': 2.5, 'subtotal': 10.0},
          ],
          'edit_history': [
            {'previous_amount': 9.5, 'new_amount': 10.25},
          ],
        },
      );

      expect(transaction['amount'], 10.25);
      expect(transaction['financial_minor_units'], {
        'amount': 1025,
        'items.0.unit_price': 250,
        'items.0.subtotal': 1000,
        'edit_history.0.previous_amount': 950,
        'edit_history.0.new_amount': 1025,
      });
    });

    test('merges matching companions and rejects conflicting values', () {
      final merged = FinancialMinorUnitMigration.withMinorUnits('shops', {
        'balance': 4.25,
        'bad_debt_amount': 0.0,
        'financial_minor_units': {'bad_debt_amount': 0},
      });
      expect(merged['financial_minor_units'], {
        'balance': 425,
        'bad_debt_amount': 0,
      });

      expect(
        () => FinancialMinorUnitMigration.withMinorUnits('shops', {
          'balance': 4.25,
          'financial_minor_units': {'balance': 426},
        }),
        throwsArgumentError,
      );
    });

    test(
      'rebuilds companions from the authoritative legacy values on update',
      () {
        final companions = FinancialMinorUnitMigration.companionsAfterUpdate(
          'shops',
          {
            'balance': 4.25,
            'bad_debt_amount': 0.0,
            'financial_minor_units': {'balance': 999},
          },
          {'balance': 3.75},
        );

        expect(companions, {'balance': 375, 'bad_debt_amount': 0});
      },
    );

    test('backfill refreshes stale companions from legacy major values', () {
      expect(
        FinancialMinorUnitMigration.companionsForBackfill('transactions', {
          'amount': 10.25,
          'edit_request_new_amount': 12.5,
          'financial_minor_units': {'amount': 999},
        }),
        {'amount': 1025, 'edit_request_new_amount': 1250},
      );
    });

    test('detects only a complete matching companion map', () {
      const expected = {'amount': 1025};

      expect(
        FinancialMinorUnitMigration.hasCurrentCompanions(const {
          'financial_minor_units': {'amount': 1025},
        }, expected),
        isTrue,
      );
      expect(
        FinancialMinorUnitMigration.hasCurrentCompanions(const {
          'financial_minor_units': {'amount': 1024},
        }, expected),
        isFalse,
      );
      expect(
        FinancialMinorUnitMigration.hasCurrentCompanions(const {
          'financial_minor_units': {'amount': 1025, 'extra': 0},
        }, expected),
        isFalse,
      );
    });

    test(
      'uses matching minor units and falls back for older-client writes',
      () {
        expect(
          FinancialMinorUnitMigration.readMajorAmount(10.01, {
            'amount': 1001,
          }, 'amount'),
          10.01,
        );
        expect(
          FinancialMinorUnitMigration.readMajorAmount(10.02, {
            'amount': 1001,
          }, 'amount'),
          10.02,
        );
        expect(
          FinancialMinorUnitMigration.readMajorAmount(10.005, {
            'amount': 1001,
          }, 'amount'),
          10.005,
        );
      },
    );

    test('rejects sub-cent, non-finite, and unsafe magnitudes', () {
      expect(
        () => FinancialMinorUnitMigration.toMinorUnits(1.001),
        throwsArgumentError,
      );
      expect(
        () => FinancialMinorUnitMigration.toMinorUnits(double.infinity),
        throwsArgumentError,
      );
      expect(
        () => FinancialMinorUnitMigration.toMinorUnits(9e13 + 1),
        throwsArgumentError,
      );
    });

    test('plans tenant-scoped shop, transaction, and invoice companions', () {
      final plan = FinancialMinorUnitMigration.preview(
        tenantId: 'tenant-a',
        collections: {
          'shops': [
            {
              '__id': 'shop-1',
              'tenant_id': 'tenant-a',
              'balance': 4.25,
              'last_transaction_amount': 2.5,
            },
          ],
          'transactions': [
            {
              '__id': 'tx-1',
              'tenant_id': 'tenant-a',
              'amount': 10.01,
              'items': [
                {'unit_price': 3.25, 'subtotal': 6.5},
              ],
              'edit_history': [
                {'previous_amount': 9.5, 'new_amount': 10.01},
              ],
            },
          ],
          'invoices': [
            {
              '__id': 'invoice-1',
              'tenant_id': 'tenant-a',
              'total': 10.01,
              'items': [
                {'unit_price': 5.005, 'subtotal': 10.01},
              ],
            },
          ],
        },
      );

      expect(plan.documentCount, 3);
      expect(plan.eligibleDocumentCount, 2);
      expect(plan.companionFieldCount, 7);
      expect(plan.exceptions, hasLength(1));
      expect(plan.exceptions.single.documentId, 'invoice-1');
      expect(plan.exceptions.single.fieldPath, 'items.0.unit_price');
      expect(plan.isClean, isFalse);
      final transactionPlan = plan.documents.singleWhere(
        (document) => document.collection == 'transactions',
      );
      expect(
        transactionPlan.financialMinorUnits,
        containsPair('items.0.subtotal', 650),
      );
    });

    test('backfill requires a clean plan for the same tenant', () {
      final cleanPlan = FinancialMinorUnitMigration.preview(
        tenantId: 'tenant-a',
        collections: {
          'shops': [
            {'__id': 'shop-1', 'tenant_id': 'tenant-a', 'balance': 4.25},
          ],
          'transactions': <Map<String, dynamic>>[],
          'invoices': <Map<String, dynamic>>[],
        },
      );
      final blockedPlan = FinancialMinorUnitMigration.preview(
        tenantId: 'tenant-a',
        collections: {
          'shops': [
            {'__id': 'shop-1', 'tenant_id': 'tenant-a', 'balance': 4.251},
          ],
          'transactions': <Map<String, dynamic>>[],
          'invoices': <Map<String, dynamic>>[],
        },
      );

      expect(
        () => FinancialMinorUnitMigration.validateBackfillPlan(
          plan: cleanPlan,
          tenantId: 'tenant-a',
        ),
        returnsNormally,
      );
      expect(
        () => FinancialMinorUnitMigration.validateBackfillPlan(
          plan: cleanPlan,
          tenantId: 'tenant-b',
        ),
        throwsStateError,
      );
      expect(
        () => FinancialMinorUnitMigration.validateBackfillPlan(
          plan: blockedPlan,
          tenantId: 'tenant-a',
        ),
        throwsStateError,
      );
    });

    test('requires an existing active tenant document for backfill', () {
      expect(
        () => FinancialMinorUnitMigration.validateActiveTenantDocument(
          exists: true,
          data: const {'active': true},
        ),
        returnsNormally,
      );
      for (final (exists, data) in [
        (false, const <String, dynamic>{'active': true}),
        (true, null),
        (true, const <String, dynamic>{'active': false}),
        (true, const <String, dynamic>{}),
      ]) {
        expect(
          () => FinancialMinorUnitMigration.validateActiveTenantDocument(
            exists: exists,
            data: data,
          ),
          throwsStateError,
        );
      }
    });

    test(
      'rejects cross-tenant, malformed, duplicate, and conflicting data',
      () {
        final plan = FinancialMinorUnitMigration.preview(
          tenantId: 'tenant-a',
          collections: {
            'transactions': <Map<String, dynamic>>[],
            'invoices': <Map<String, dynamic>>[],
            'shops': [
              {'__id': 'shop-1', 'tenant_id': 'tenant-b', 'balance': 1},
              {'__id': 'shop-2', 'tenant_id': 'tenant-a', 'balance': '1.00'},
              {'__id': 'shop-2', 'tenant_id': 'tenant-a', 'balance': 1.0},
              {
                '__id': 'shop-3',
                'tenant_id': 'tenant-a',
                'balance': 1,
                'financial_minor_units': {'balance': 200},
              },
            ],
          },
        );

        expect(plan.isClean, isFalse);
        expect(plan.exceptions, hasLength(4));
        expect(
          plan.exceptions.map((exception) => exception.code),
          containsAll([
            FinancialMigrationException.crossTenant,
            FinancialMigrationException.invalidAmount,
            FinancialMigrationException.duplicateDocument,
            FinancialMigrationException.companionConflict,
          ]),
        );
      },
    );
  });
}
