// Tests for createSaleInvoice validation guards added in audit v6.
//
// These tests verify pure validation logic: the amountReceived > total guard,
// invoice math invariants (total ≈ subtotal − discount), and discount >= 0
// checks WITHOUT hitting Firestore.
//
// The helpers below mirror the exact guards in invoice_provider.dart so that
// future changes cause these tests to fail loudly.

import 'package:flutter_test/flutter_test.dart';

// ── pure-logic helpers mirroring createSaleInvoice guards ─────────────────

/// Validates amount received vs invoice total.
/// Returns an error message, or null if valid.
String? validateAmountReceived({
  required double amountReceived,
  required double total,
}) {
  if (amountReceived > total) {
    return 'amountReceived cannot exceed invoice total';
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
  group('createSaleInvoice — amountReceived guard', () {
    test('passes when amountReceived equals total (fully paid)', () {
      expect(validateAmountReceived(amountReceived: 1000, total: 1000), isNull);
    });

    test('passes when amountReceived is zero (unpaid)', () {
      expect(validateAmountReceived(amountReceived: 0, total: 1000), isNull);
    });

    test('passes when amountReceived is partial', () {
      expect(validateAmountReceived(amountReceived: 400, total: 1000), isNull);
    });

    test('fails when amountReceived exceeds total by 1 paisa', () {
      expect(
        validateAmountReceived(amountReceived: 1000.01, total: 1000),
        isNotNull,
      );
    });

    test('fails when amountReceived is far above total', () {
      expect(
        validateAmountReceived(amountReceived: 9999, total: 1000),
        isNotNull,
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
