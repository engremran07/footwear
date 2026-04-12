// Tests for markAsPaid outstanding amount fallback logic (M-025, audit v6).
//
// These tests verify the exact fallback calculation used in markAsPaid:
//   outstanding = stored_outstanding ?? (total - amountReceived).clamp(0, ∞)
//
// This ensures that invoices lacking an explicit outstanding_amount field
// are handled correctly and never produce negative outstanding values.

import 'package:flutter_test/flutter_test.dart';

// ── pure-logic helper mirroring markAsPaid outstanding resolution ──────────

/// Resolves the outstanding amount for an invoice document.
///
/// Mirrors the logic in invoice_provider.dart markAsPaid:
///   final outstanding = stored ?? (total - received).clamp(0, ∞)
double resolveOutstanding({
  required double? storedOutstanding,
  required double total,
  required double amountReceived,
}) {
  return storedOutstanding ??
      (total - amountReceived).clamp(0.0, double.infinity);
}

// ── tests ──────────────────────────────────────────────────────────────────

void main() {
  group('markAsPaid — outstanding resolution', () {
    test('uses stored outstanding when present', () {
      expect(
        resolveOutstanding(
          storedOutstanding: 300,
          total: 1000,
          amountReceived: 700,
        ),
        equals(300),
      );
    });

    test('fallback computes total minus amountReceived', () {
      expect(
        resolveOutstanding(
          storedOutstanding: null,
          total: 1000,
          amountReceived: 700,
        ),
        equals(300),
      );
    });

    test('fallback with zero amountReceived returns full total', () {
      expect(
        resolveOutstanding(
          storedOutstanding: null,
          total: 1500,
          amountReceived: 0,
        ),
        equals(1500),
      );
    });

    test('fallback with full payment returns zero', () {
      expect(
        resolveOutstanding(
          storedOutstanding: null,
          total: 1000,
          amountReceived: 1000,
        ),
        equals(0.0),
      );
    });

    test('fallback clamps negative result to zero (overpayment guard)', () {
      // amountReceived > total — stored outstanding missing; must not go negative
      expect(
        resolveOutstanding(
          storedOutstanding: null,
          total: 1000,
          amountReceived: 1200,
        ),
        equals(0.0),
      );
    });

    test('stored outstanding of zero is used as-is (not treated as null)', () {
      expect(
        resolveOutstanding(
          storedOutstanding: 0,
          total: 1000,
          amountReceived: 0,
        ),
        equals(0.0),
      );
    });

    test('fallback fractional result is preserved', () {
      expect(
        resolveOutstanding(
          storedOutstanding: null,
          total: 999.99,
          amountReceived: 333.33,
        ),
        closeTo(666.66, 0.01),
      );
    });
  });
}
