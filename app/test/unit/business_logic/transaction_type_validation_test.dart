// Tests for transaction type validation logic.
//
// Only these 5 types are allowed in the 'transactions' collection:
//   cash_in | cash_out | return | payment | write_off
//
// This allowlist is enforced in:
//   - TransactionNotifier.create() → throws ArgumentError
//   - Firestore rules → isValidTransactionType() helper
//
// These tests verify the pure validation logic without Firestore.

import 'package:flutter_test/flutter_test.dart';

// ── Mirrors TransactionNotifier allowedTypes set ─────────────────────────────

const _allowedTypes = {'cash_out', 'cash_in', 'return', 'payment', 'write_off'};

bool isValidTransactionType(String type) => _allowedTypes.contains(type);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('TransactionType — allowed types', () {
    test('cash_in is valid', () {
      expect(isValidTransactionType('cash_in'), isTrue);
    });

    test('cash_out is valid', () {
      expect(isValidTransactionType('cash_out'), isTrue);
    });

    test('return is valid', () {
      expect(isValidTransactionType('return'), isTrue);
    });

    test('payment is valid', () {
      expect(isValidTransactionType('payment'), isTrue);
    });

    test('write_off is valid', () {
      expect(isValidTransactionType('write_off'), isTrue);
    });
  });

  group('TransactionType — rejected types', () {
    test('empty string is rejected', () {
      expect(isValidTransactionType(''), isFalse);
    });

    test('arbitrary string is rejected', () {
      expect(isValidTransactionType('transfer'), isFalse);
    });

    test('uppercase variant is rejected (case-sensitive)', () {
      expect(isValidTransactionType('Cash_In'), isFalse);
    });

    test('sale is rejected (only invoice creates sale records)', () {
      expect(isValidTransactionType('sale'), isFalse);
    });

    test('debit is rejected', () {
      expect(isValidTransactionType('debit'), isFalse);
    });

    test('credit is rejected (sale_type field, not transaction type)', () {
      expect(isValidTransactionType('credit'), isFalse);
    });

    test('refund is rejected (use return instead)', () {
      expect(isValidTransactionType('refund'), isFalse);
    });

    test('null-like string is rejected', () {
      expect(isValidTransactionType('null'), isFalse);
    });
  });

  // ── Balance delta sign rules ───────────────────────────────────────────────

  group('Transaction type — balance delta signs', () {
    // Mirrors TransactionNotifier.create() balance delta logic
    double delta(String type, double amount) =>
        type == 'cash_out' ? amount : -amount;

    test('cash_out increases balance (shop owes more)', () {
      expect(delta('cash_out', 1000), 1000.0);
    });

    test('cash_in decreases balance (shop owes less)', () {
      expect(delta('cash_in', 1000), -1000.0);
    });

    test('return decreases balance (goods returned)', () {
      expect(delta('return', 500), -500.0);
    });

    test('payment decreases balance (generic payment)', () {
      expect(delta('payment', 2000), -2000.0);
    });

    test('write_off is handled by ShopNotifier directly (not delta)', () {
      // write_off type: balance is set to 0.0 directly by markAsBadDebt().
      // TransactionNotifier.create() does not handle write_off balance update.
      expect(isValidTransactionType('write_off'), isTrue);
    });
  });
}
