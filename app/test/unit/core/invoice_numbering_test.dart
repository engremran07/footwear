import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/utils/invoice_numbering.dart';

void main() {
  group('InvoiceNumbering', () {
    test('rejects malformed sequence counters', () {
      expect(
        () => InvoiceNumbering.nextSequence({'last_invoice_number': -1}),
        throwsStateError,
      );
      expect(
        () => InvoiceNumbering.nextSequence({'last_cash_receipt_number': 1.5}),
        throwsStateError,
      );
      expect(
        () => InvoiceNumbering.nextSequence({'last_invoice_number': null}),
        throwsStateError,
      );
    });

    test('uses a non-resetting sale sequence without the device year', () {
      expect(InvoiceNumbering.sale(1), 'INV-0001');
      expect(InvoiceNumbering.sale(10000), 'INV-10000');
    });

    test('distinguishes credit notes and receipts by prefix', () {
      expect(InvoiceNumbering.creditNote(2), 'CN-0002');
      expect(InvoiceNumbering.receipt(3), 'REC-0003');
    });

    test('continues from the highest legacy invoice or receipt counter', () {
      expect(
        InvoiceNumbering.nextSequence({
          'last_invoice_number': 4,
          'last_cash_receipt_number': 7,
        }),
        8,
      );
      expect(
        InvoiceNumbering.nextSequence({
          'last_invoice_number': 9,
          'last_cash_receipt_number': 2,
        }),
        10,
      );
      expect(InvoiceNumbering.nextSequence({'last_invoice_number': 3}), 4);
    });

    test('rejects non-positive sequence values', () {
      expect(() => InvoiceNumbering.sale(0), throwsArgumentError);
      expect(() => InvoiceNumbering.receipt(-1), throwsArgumentError);
    });
  });
}
