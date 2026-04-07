// Tests for the two financial pathways in ShoesERP.
//
// PATHWAY 1 — Sale with stock (Invoice):
//   CreateSaleInvoiceScreen → InvoiceNotifier.createSaleInvoice()
//   Creates: invoice doc + cash_out tx + optional cash_in tx + inventory deduction
//
// PATHWAY 2 — Cash collection from existing debt (Ledger only):
//   ShopDetailScreen quick cash_in → TransactionNotifier.create(type: 'cash_in')
//   Creates: cash_in tx only. No invoice. No stock movement.
//
// These pure-logic tests verify the balance delta formulas for both pathways
// without hitting Firestore.

import 'package:flutter_test/flutter_test.dart';

// ── Pathway 1: Invoice balance delta logic ───────────────────────────────────

/// Mirrors createSaleInvoice balance delta:
///   balance += total - amountReceived
double invoiceBalanceDelta({
  required double total,
  required double amountReceived,
}) => total - amountReceived;

/// Mirrors invoice status derivation
String invoiceStatus({required double total, required double amountReceived}) {
  if (amountReceived >= total && total > 0) return 'paid';
  if (amountReceived > 0) return 'partial';
  return 'issued';
}

/// Mirrors sale type derivation
String saleType({required double total, required double amountReceived}) {
  if (amountReceived >= total && total > 0) return 'cash';
  return 'credit';
}

// ── Pathway 2: Cash collection balance delta logic ───────────────────────────

/// Mirrors TransactionNotifier.create() balance delta:
///   cash_in: balance -= amount (reduces debt)
///   cash_out: balance += amount (adds debt)
double transactionBalanceDelta({
  required String type,
  required double amount,
}) => type == 'cash_out' ? amount : -amount;

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── PATHWAY 1: Invoice ─────────────────────────────────────────────────────

  group('Pathway 1 — Invoice: balance delta', () {
    test('full credit sale: full amount added to balance', () {
      expect(invoiceBalanceDelta(total: 5000, amountReceived: 0), 5000.0);
    });

    test('partial payment: partial amount added to balance', () {
      expect(invoiceBalanceDelta(total: 5000, amountReceived: 2000), 3000.0);
    });

    test('full cash sale: no change to balance (paid immediately)', () {
      expect(invoiceBalanceDelta(total: 5000, amountReceived: 5000), 0.0);
    });

    test('over-payment reduces old balance (amountReceived > total)', () {
      // This scenario is blocked by validation guard in createSaleInvoice.
      // Showing the math for documentation: would result in negative delta.
      expect(invoiceBalanceDelta(total: 3000, amountReceived: 5000), -2000.0);
    });
  });

  group('Pathway 1 — Invoice: status derivation', () {
    test('amountReceived=0 → status: issued', () {
      expect(invoiceStatus(total: 5000, amountReceived: 0), 'issued');
    });

    test('amountReceived > 0 and < total → status: partial', () {
      expect(invoiceStatus(total: 5000, amountReceived: 2000), 'partial');
    });

    test('amountReceived == total → status: paid', () {
      expect(invoiceStatus(total: 5000, amountReceived: 5000), 'paid');
    });

    test('amountReceived > total → status: paid (guard blocks this in UI)', () {
      // UI guard prevents amountReceived > total.
      // Math still resolves to paid.
      expect(invoiceStatus(total: 5000, amountReceived: 6000), 'paid');
    });
  });

  group('Pathway 1 — Invoice: sale type derivation', () {
    test('fully paid → sale_type: cash', () {
      expect(saleType(total: 5000, amountReceived: 5000), 'cash');
    });

    test('partial payment → sale_type: credit', () {
      expect(saleType(total: 5000, amountReceived: 2000), 'credit');
    });

    test('unpaid → sale_type: credit', () {
      expect(saleType(total: 5000, amountReceived: 0), 'credit');
    });
  });

  // ── PATHWAY 2: Ledger-only cash collection ─────────────────────────────────

  group('Pathway 2 — Ledger: cash_in reduces balance', () {
    test('cash_in 2000 → balance decreases by 2000', () {
      expect(transactionBalanceDelta(type: 'cash_in', amount: 2000), -2000.0);
    });

    test('large cash_in clears significant debt', () {
      expect(transactionBalanceDelta(type: 'cash_in', amount: 50000), -50000.0);
    });

    test('cash_in with zero amount has zero delta', () {
      expect(transactionBalanceDelta(type: 'cash_in', amount: 0), 0.0);
    });
  });

  group('Pathway 2 — Ledger: cash_out increases balance', () {
    test('cash_out 3000 → balance increases by 3000', () {
      expect(transactionBalanceDelta(type: 'cash_out', amount: 3000), 3000.0);
    });
  });

  group('Pathway 2 — Ledger: return reduces balance', () {
    test('return 1000 → balance decreases by 1000', () {
      expect(transactionBalanceDelta(type: 'return', amount: 1000), -1000.0);
    });
  });

  // ── Combined: running balance after multiple ops ───────────────────────────

  group('Running balance simulation', () {
    test('invoice then partial cash collection reduces balance correctly', () {
      double balance = 0;

      // Sale invoice: total=5000, received=1000 → balance += 4000
      balance += invoiceBalanceDelta(total: 5000, amountReceived: 1000);
      expect(balance, 4000.0);

      // Later cash collection (pathway 2): cash_in 1500
      balance += transactionBalanceDelta(type: 'cash_in', amount: 1500);
      expect(balance, 2500.0);

      // Another cash collection: cash_in 2500 → fully clears
      balance += transactionBalanceDelta(type: 'cash_in', amount: 2500);
      expect(balance, 0.0);
    });

    test('two invoices then full repayment', () {
      double balance = 0;

      // Invoice 1: total=3000, fully on credit
      balance += invoiceBalanceDelta(total: 3000, amountReceived: 0);
      // Invoice 2: total=2000, fully on credit
      balance += invoiceBalanceDelta(total: 2000, amountReceived: 0);
      expect(balance, 5000.0);

      // Full repayment via cash_in
      balance += transactionBalanceDelta(type: 'cash_in', amount: 5000);
      expect(balance, 0.0);
    });
  });
}
