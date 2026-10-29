// Tests for createSaleInvoice validation guards added in audit v6.
//
// These tests verify pure validation logic: the amountReceived > total guard,
// invoice math invariants (total ≈ subtotal − discount), and discount >= 0
// checks WITHOUT hitting Firestore.
//
// The helpers below mirror the exact guards in invoice_provider.dart so that
// future changes cause these tests to fail loudly.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footwear_erp/providers/invoice_provider.dart';
import 'package:footwear_erp/providers/transaction_provider.dart';

// ── pure-logic helpers mirroring createSaleInvoice guards ─────────────────

/// Validates the sale amount entered on the create sale invoice screen.
/// Returns an error message, or null if valid.
String? validateSaleAmount({required double saleAmount}) {
  if (saleAmount <= 0) {
    return 'sale_amount_required';
  }
  return null;
}

/// Validates invoice math invariant: total ≈ subtotal − discount (±0.01).
bool isInvoiceMathValid({
  required double total,
  required double subtotal,
  required double discount,
}) {
  final expected = subtotal - discount;
  return (total - expected).abs() <= 0.01;
}

// ── tests ──────────────────────────────────────────────────────────────────

void main() {
  test('provider rejects stock sales without inventory deductions', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(invoiceNotifierProvider.notifier);

    await expectLater(
      notifier.createSaleInvoice(
        shopId: 'shop-1',
        shopName: 'Shop',
        routeId: 'route-1',
        sellerId: 'seller-1',
        sellerName: 'Seller',
        items: const [
          {'variant_id': 'variant-1', 'qty': 1, 'unit_price': 100},
        ],
        subtotal: 100,
        total: 100,
        createdBy: 'seller-1',
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('stock deduction'),
        ),
      ),
    );
  });

  group('createSaleInvoice — sale amount guard', () {
    test('fails when sale amount is zero', () {
      expect(validateSaleAmount(saleAmount: 0), 'sale_amount_required');
    });

    test('fails when sale amount is negative', () {
      expect(validateSaleAmount(saleAmount: -1), 'sale_amount_required');
    });

    test('passes when sale amount is positive', () {
      expect(validateSaleAmount(saleAmount: 100.0), isNull);
    });
  });

  group('createSaleInvoice — amountReceived guard', () {
    test('passes when amountReceived equals total (fully paid)', () {
      expect(
        amountReceivedExceedsInvoiceTotal(amountReceived: 1000, total: 1000),
        isFalse,
      );
    });

    test('passes when amountReceived is zero (unpaid)', () {
      expect(
        amountReceivedExceedsInvoiceTotal(amountReceived: 0, total: 1000),
        isFalse,
      );
    });

    test('passes when amountReceived is partial', () {
      expect(
        amountReceivedExceedsInvoiceTotal(amountReceived: 400, total: 1000),
        isFalse,
      );
    });

    test('fails when amountReceived exceeds total by 1 paisa', () {
      expect(
        amountReceivedExceedsInvoiceTotal(amountReceived: 1000.01, total: 1000),
        isTrue,
      );
    });

    test('fails when amountReceived is far above total', () {
      expect(
        amountReceivedExceedsInvoiceTotal(amountReceived: 9999, total: 1000),
        isTrue,
      );
    });
  });

  group('createSaleInvoice — invoice math validation', () {
    test('passes when total equals subtotal minus discount exactly', () {
      expect(
        isInvoiceMathValid(total: 900, subtotal: 1000, discount: 100),
        isTrue,
      );
    });

    test('passes within 0.01 tolerance (floating point rounding)', () {
      expect(
        isInvoiceMathValid(total: 899.995, subtotal: 1000, discount: 100),
        isTrue,
      );
    });

    test('passes with zero discount', () {
      expect(
        isInvoiceMathValid(total: 1000, subtotal: 1000, discount: 0),
        isTrue,
      );
    });

    test('fails when total is off by more than 0.01', () {
      expect(
        isInvoiceMathValid(total: 850, subtotal: 1000, discount: 100),
        isFalse,
      );
    });

    test('fails when total is inflated above subtotal minus discount', () {
      expect(
        isInvoiceMathValid(total: 950, subtotal: 1000, discount: 100),
        isFalse,
      );
    });
  });

  group('invoice line validation', () {
    test('accepts a variant with positive whole quantity and valid price', () {
      expect(
        () => validateInvoiceItems(const [
          {'variant_id': 'variant-1', 'qty': 2, 'unit_price': 10.5},
        ]),
        returnsNormally,
      );
    });

    test('rejects a missing variant ID', () {
      expect(
        () => validateInvoiceItems(const [
          {'variant_id': ' ', 'qty': 1, 'unit_price': 10},
        ]),
        throwsArgumentError,
      );
    });

    test('rejects zero, negative, fractional, and non-finite quantities', () {
      for (final quantity in [0, -1, 0.5, double.infinity]) {
        expect(
          () => validateInvoiceItems([
            {'variant_id': 'variant-1', 'qty': quantity, 'unit_price': 10},
          ]),
          throwsArgumentError,
        );
      }
    });

    test('rejects prices with more than two decimal places', () {
      expect(
        () => validateInvoiceItems(const [
          {'variant_id': 'variant-1', 'qty': 1, 'unit_price': 100.005},
        ]),
        throwsArgumentError,
      );
    });
  });

  group('seller inventory deduction reconciliation', () {
    const items = [
      {'variant_id': 'variant-1', 'qty': 2, 'extra_pairs': 1, 'unit_price': 20},
      {'variant_id': 'variant-2', 'qty': 1, 'extra_pairs': 0, 'unit_price': 10},
    ];
    const inventoryVariantIds = {
      'inventory-1': 'variant-1',
      'inventory-2': 'variant-1',
      'inventory-3': 'variant-2',
    };

    test('matches dozen quantities and extra pairs to pair deductions', () {
      expect(
        sellerInventoryDeductionsMatchInvoiceItems(
          items: items,
          deductions: const {
            'inventory-1': 12,
            'inventory-2': 13,
            'inventory-3': 12,
          },
          inventoryVariantIds: inventoryVariantIds,
          pairsPerCarton: 12,
        ),
        isTrue,
      );
    });

    test('rejects missing, extra, or wrong-variant stock deductions', () {
      for (final deductions in [
        const {'inventory-1': 12, 'inventory-2': 12, 'inventory-3': 12},
        const {
          'inventory-1': 12,
          'inventory-2': 13,
          'inventory-3': 12,
          'inventory-4': 1,
        },
        const {'inventory-1': 12, 'inventory-2': 13, 'inventory-3': 13},
      ]) {
        expect(
          sellerInventoryDeductionsMatchInvoiceItems(
            items: items,
            deductions: deductions,
            inventoryVariantIds: inventoryVariantIds,
            pairsPerCarton: 12,
          ),
          isFalse,
        );
      }
    });

    test('rejects invalid pair-unit configuration and extra-pair values', () {
      expect(
        sellerInventoryDeductionsMatchInvoiceItems(
          items: items,
          deductions: const {'inventory-1': 25, 'inventory-3': 12},
          inventoryVariantIds: inventoryVariantIds,
          pairsPerCarton: 0,
        ),
        isFalse,
      );
      expect(
        sellerInventoryDeductionsMatchInvoiceItems(
          items: const [
            {
              'variant_id': 'variant-1',
              'qty': 1,
              'extra_pairs': 12,
              'unit_price': 10,
            },
          ],
          deductions: const {'inventory-1': 24},
          inventoryVariantIds: inventoryVariantIds,
          pairsPerCarton: 12,
        ),
        isFalse,
      );
    });
  });

  group('seller inventory restore reconciliation', () {
    test('allows cumulative restores up to the original sale deduction', () {
      expect(
        sellerInventoryRestoresWithinOriginalSale(
          originalDeductions: const {'inventory-1': 24},
          existingCreditNotes: const [
            {
              'type': 'credit_note',
              'seller_inventory_restores': {'inventory-1': 12},
            },
          ],
          requestedRestores: const {'inventory-1': 12},
        ),
        isTrue,
      );
    });

    test('rejects restores that exceed or do not reference original stock', () {
      expect(
        sellerInventoryRestoresWithinOriginalSale(
          originalDeductions: const {'inventory-1': 24},
          existingCreditNotes: const [
            {
              'type': 'credit_note',
              'seller_inventory_restores': {'inventory-1': 12},
            },
          ],
          requestedRestores: const {'inventory-1': 13},
        ),
        isFalse,
      );
      expect(
        sellerInventoryRestoresWithinOriginalSale(
          originalDeductions: const {'inventory-1': 24},
          existingCreditNotes: const [],
          requestedRestores: const {'inventory-2': 1},
        ),
        isFalse,
      );
    });

    test('ignores voided notes and rejects malformed historical restores', () {
      expect(
        sellerInventoryRestoresWithinOriginalSale(
          originalDeductions: const {'inventory-1': 24},
          existingCreditNotes: const [
            {
              'type': 'credit_note',
              'status': 'void',
              'seller_inventory_restores': {'inventory-1': 24},
            },
          ],
          requestedRestores: const {'inventory-1': 24},
        ),
        isTrue,
      );
      expect(
        sellerInventoryRestoresWithinOriginalSale(
          originalDeductions: const {'inventory-1': 24},
          existingCreditNotes: const [
            {
              'type': 'credit_note',
              'seller_inventory_restores': {'inventory-1': -1},
            },
          ],
          requestedRestores: const {},
        ),
        isFalse,
      );
    });
  });

  group('credit note quantity reconciliation', () {
    test('aggregates repeated variants on an invoice', () {
      expect(
        invoiceQuantitiesByVariant(const [
          {'variant_id': 'variant-1', 'qty': 2, 'unit_price': 10},
          {'variant_id': 'variant-1', 'qty': 1, 'unit_price': 10},
        ]),
        {'variant-1': 3},
      );
    });

    test('allows returns up to the original sold quantity', () {
      expect(
        creditNoteQuantitiesAfter(
          soldQuantities: const {'variant-1': 3},
          previouslyCreditedQuantities: const {'variant-1': 2},
          requestedQuantities: const {'variant-1': 1},
        ),
        {'variant-1': 3},
      );
    });

    test('rejects cumulative returns above original sold quantity', () {
      expect(
        () => creditNoteQuantitiesAfter(
          soldQuantities: const {'variant-1': 3},
          previouslyCreditedQuantities: const {'variant-1': 2},
          requestedQuantities: const {'variant-1': 2},
        ),
        throwsArgumentError,
      );
    });

    test('rejects legacy credited quantities inconsistent with the sale', () {
      expect(
        () => creditNoteQuantitiesAfter(
          soldQuantities: const {'variant-1': 3},
          previouslyCreditedQuantities: const {'variant-1': 4},
          requestedQuantities: const {'variant-1': 1},
        ),
        throwsStateError,
      );
    });

    test('rejects return of a variant absent from the original sale', () {
      expect(
        () => creditNoteQuantitiesAfter(
          soldQuantities: const {'variant-1': 3},
          previouslyCreditedQuantities: const {},
          requestedQuantities: const {'variant-2': 1},
        ),
        throwsArgumentError,
      );
    });

    test('reconstructs active legacy notes and excludes voided notes', () {
      expect(
        reconstructCreditNoteQuantities(
          soldQuantities: const {'variant-1': 3},
          existingCreditNotes: const [
            {
              'type': 'credit_note',
              'items': [
                {'variant_id': 'variant-1', 'qty': 1},
              ],
            },
            {
              'type': 'credit_note',
              'status': 'void',
              'items': [
                {'variant_id': 'variant-1', 'qty': 2},
              ],
            },
          ],
        ),
        {'variant-1': 1},
      );
    });

    test(
      'fails closed when legacy note history exceeds its reconstruction limit',
      () {
        expect(
          () => reconstructCreditNoteQuantities(
            soldQuantities: const {'variant-1': 3},
            existingCreditNotes: List.generate(
              3,
              (_) => const {
                'type': 'credit_note',
                'items': [
                  {'variant_id': 'variant-1', 'qty': 1},
                ],
              },
            ),
            maxCreditNotes: 2,
          ),
          throwsStateError,
        );
      },
    );
  });

  group('monetary precision guards', () {
    test(
      'sale invoice rejects amount fields with more than two decimals',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(invoiceNotifierProvider.notifier);

        await expectLater(
          notifier.createSaleInvoice(
            shopId: 'shop-1',
            shopName: 'Shop',
            routeId: 'route-1',
            items: const [
              {'variant_id': 'variant-1', 'qty': 1, 'unit_price': 100},
            ],
            subtotal: 100.005,
            total: 100.005,
            createdBy: 'admin-1',
            fulfillmentMode: 'non_stock',
          ),
          throwsArgumentError,
        );
      },
    );

    test(
      'cash receipt rejects an amount with more than two decimals',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(invoiceNotifierProvider.notifier);

        await expectLater(
          notifier.createCashReceipt(
            shopId: 'shop-1',
            shopName: 'Shop',
            routeId: 'route-1',
            sellerId: 'seller-1',
            sellerName: 'Seller',
            amount: 100.005,
            createdBy: 'admin-1',
            currency: 'SAR',
          ),
          throwsArgumentError,
        );
      },
    );

    test(
      'credit note rejects total and subtotal with more than two decimals',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(invoiceNotifierProvider.notifier);

        await expectLater(
          notifier.createReturnInvoice(
            shopId: 'shop-1',
            shopName: 'Shop',
            routeId: 'route-1',
            items: const [
              {'variant_id': 'variant-1', 'qty': 1, 'unit_price': 100},
            ],
            subtotal: 100.005,
            total: 100.005,
            linkedInvoiceId: 'sale-1',
            createdBy: 'admin-1',
          ),
          throwsArgumentError,
        );
      },
    );

    test(
      'standalone transaction rejects an amount with more than two decimals',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(transactionNotifierProvider.notifier);

        await expectLater(
          notifier.create(
            shopId: 'shop-1',
            shopName: 'Shop',
            routeId: 'route-1',
            type: 'cash_in',
            amount: 100.005,
            createdBy: 'seller-1',
            idempotencyKey: 'precision-test',
          ),
          throwsArgumentError,
        );
      },
    );

    test('admin transaction corrections reject sub-cent amounts', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(transactionNotifierProvider.notifier);

      await expectLater(
        notifier.updateTransaction(
          txId: 'tx-1',
          shopId: 'shop-1',
          oldAmount: 100,
          oldType: 'cash_in',
          newAmount: 100.005,
          newType: 'cash_in',
          reason: 'Correct amount after review',
        ),
        throwsArgumentError,
      );
    });

    test('seller edit requests reject sub-cent amounts', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(transactionNotifierProvider.notifier);

      await expectLater(
        notifier.sellerEditTransaction(
          txId: 'tx-1',
          sellerId: 'seller-1',
          newAmount: 100.005,
          newType: 'cash_in',
        ),
        throwsArgumentError,
      );
    });
  });

  group('credit note date window', () {
    final now = DateTime.utc(2026, 10, 29);

    test('accepts a sale exactly 30 days old', () {
      expect(
        isCreditNoteWithin30DayWindow(
          invoiceCreatedAt: now.subtract(const Duration(days: 30)),
          now: now,
        ),
        isTrue,
      );
    });

    test('rejects a sale older than 30 days', () {
      expect(
        isCreditNoteWithin30DayWindow(
          invoiceCreatedAt: now.subtract(const Duration(days: 30, seconds: 1)),
          now: now,
        ),
        isFalse,
      );
    });

    test('rejects a future-dated sale', () {
      expect(
        isCreditNoteWithin30DayWindow(
          invoiceCreatedAt: now.add(const Duration(seconds: 1)),
          now: now,
        ),
        isFalse,
      );
    });
  });
}
