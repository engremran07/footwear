// Tests for markAsPaid outstanding amount fallback logic (M-025, audit v6).
//
// These tests verify the exact fallback calculation used in markAsPaid:
//   outstanding = stored_outstanding ?? (total - amountReceived).clamp(0, ∞)
//
// This ensures that invoices lacking an explicit outstanding_amount field
// are handled correctly and never produce negative outstanding values.

import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/invoice_model.dart';

// ── tests ──────────────────────────────────────────────────────────────────

void main() {
  group('markAsPaid — outstanding resolution', () {
    test('uses stored outstanding when present', () {
      expect(
        invoiceOutstandingAfterCredits(
          total: 1000,
          amountReceived: 700,
          creditNoteTotal: 0,
        ),
        equals(300),
      );
    });

    test('credit notes reduce the outstanding amount before settlement', () {
      expect(
        invoiceOutstandingAfterCredits(
          total: 1000,
          amountReceived: 0,
          creditNoteTotal: 300,
        ),
        equals(700),
      );
    });

    test('partial payments and credit notes both reduce outstanding', () {
      expect(
        invoiceOutstandingAfterCredits(
          total: 1000,
          amountReceived: 500,
          creditNoteTotal: 300,
        ),
        equals(200),
      );
    });

    test('credit notes cannot make outstanding negative', () {
      expect(
        invoiceOutstandingAfterCredits(
          total: 1000,
          amountReceived: 0,
          creditNoteTotal: 1200,
        ),
        equals(0),
      );
    });

    test('legacy invoices without credit notes retain full outstanding', () {
      expect(
        invoiceOutstandingAfterCredits(
          total: 1500,
          amountReceived: 0,
          creditNoteTotal: 0,
        ),
        equals(1500),
      );
    });

    test('full payment returns zero outstanding', () {
      expect(
        invoiceOutstandingAfterCredits(
          total: 1000,
          amountReceived: 1000,
          creditNoteTotal: 0,
        ),
        equals(0),
      );
    });

    test('credit balances settle an invoice without collecting twice', () {
      expect(
        invoiceStatusAfterCredits(
          total: 1000,
          amountReceived: 0,
          creditNoteTotal: 1000,
        ),
        InvoiceModel.statusPaid,
      );
      expect(
        invoiceStatusAfterCredits(
          total: 1000,
          amountReceived: 500,
          creditNoteTotal: 200,
        ),
        InvoiceModel.statusPartial,
      );
    });
  });
}
