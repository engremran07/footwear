// Tests for transaction type validation logic.
//
// Only cash_in/cash_out are valid for standalone transaction creation.
// Return and write-off rows must use their linked invoice or bad-debt paths.
//
// This allowlist is enforced in:
//   - TransactionNotifier.create() → throws ArgumentError
//   - Firestore rules → standaloneTransactionCreateIsLinked() helper
//
// These tests verify the pure validation logic without Firestore.

import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/transaction_model.dart';

bool isValidStandaloneTransactionType(String type) =>
    TransactionModel.isStandaloneCashType(type);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('TransactionType — allowed types', () {
    test('cash_in is valid for standalone entry', () {
      expect(isValidStandaloneTransactionType('cash_in'), isTrue);
    });

    test('cash_out is valid for standalone entry', () {
      expect(isValidStandaloneTransactionType('cash_out'), isTrue);
    });
  });

  group('TransactionType — rejected types', () {
    test('empty string is rejected', () {
      expect(isValidStandaloneTransactionType(''), isFalse);
    });

    test('arbitrary string is rejected', () {
      expect(isValidStandaloneTransactionType('transfer'), isFalse);
    });

    test('uppercase variant is rejected (case-sensitive)', () {
      expect(isValidStandaloneTransactionType('Cash_In'), isFalse);
    });

    test('sale is rejected (only invoice creates sale records)', () {
      expect(isValidStandaloneTransactionType('sale'), isFalse);
    });

    test('debit is rejected', () {
      expect(isValidStandaloneTransactionType('debit'), isFalse);
    });

    test('credit is rejected (sale_type field, not transaction type)', () {
      expect(isValidStandaloneTransactionType('credit'), isFalse);
    });

    test('refund is rejected (use return instead)', () {
      expect(isValidStandaloneTransactionType('refund'), isFalse);
    });

    test('null-like string is rejected', () {
      expect(isValidStandaloneTransactionType('null'), isFalse);
    });

    test('returns, payments, and write-offs require dedicated pathways', () {
      for (final type in [
        TransactionModel.typeReturn,
        TransactionModel.typePayment,
        TransactionModel.typeWriteOff,
      ]) {
        expect(isValidStandaloneTransactionType(type), isFalse);
      }
    });
  });

  // ── Balance delta sign rules ───────────────────────────────────────────────

  group('Transaction type — balance delta signs', () {
    // Mirrors cash-only standalone transaction balance deltas.
    double delta(String type, double amount) =>
        type == 'cash_out' ? amount : -amount;

    test('cash_out increases balance (shop owes more)', () {
      expect(delta('cash_out', 1000), 1000.0);
    });

    test('cash_in decreases balance (shop owes less)', () {
      expect(delta('cash_in', 1000), -1000.0);
    });
  });
}
