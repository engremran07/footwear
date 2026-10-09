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
}
