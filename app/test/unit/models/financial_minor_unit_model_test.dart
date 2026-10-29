import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/invoice_model.dart';
import 'package:footwear_erp/models/shop_model.dart';
import 'package:footwear_erp/models/transaction_model.dart';

void main() {
  final timestamp = Timestamp.fromMillisecondsSinceEpoch(0);

  test('shop model reads matching minor units and dual-writes companions', () {
    final source = {
      'name': 'Shop',
      'route_id': 'route-1',
      'balance': 12.5,
      'bad_debt_amount': 0.0,
      'active': true,
      'created_by': 'admin-1',
      'created_at': timestamp,
      'updated_at': timestamp,
      'financial_minor_units': {'balance': 1250, 'bad_debt_amount': 0},
    };
    final model = ShopModel.fromJson(source, 'shop-1');

    expect(model.balance, 12.5);
    expect(model.toJson()['financial_minor_units'], {
      'balance': 1250,
      'bad_debt_amount': 0,
    });
  });

  test('transaction model dual-reads with older-client fallback', () {
    final matching = TransactionModel.fromJson({
      'amount': 10.01,
      'items': [
        {'unit_price': 2.5, 'subtotal': 10.0},
      ],
      'financial_minor_units': {
        'amount': 1001,
        'items.0.unit_price': 250,
        'items.0.subtotal': 1000,
      },
      'created_at': timestamp,
    }, 'tx-1');
    final stale = TransactionModel.fromJson({
      'amount': 10.02,
      'financial_minor_units': {'amount': 1001},
      'created_at': timestamp,
    }, 'tx-2');

    expect(matching.amount, 10.01);
    expect(matching.items.single.unitPrice, 2.5);
    expect(stale.amount, 10.02);
    expect(matching.toJson()['financial_minor_units'], {
      'amount': 1001,
      'items.0.unit_price': 250,
      'items.0.subtotal': 1000,
    });
  });

  test('invoice model reads and writes invoice minor-unit companions', () {
    final model = InvoiceModel.fromJson({
      'invoice_number': 'INV-1',
      'type': InvoiceModel.typeSale,
      'shop_id': 'shop-1',
      'shop_name': 'Shop',
      'items': [
        {'unit_price': 5.25, 'subtotal': 10.5},
      ],
      'subtotal': 10.5,
      'discount': 0,
      'total': 10.5,
      'amount_received': 2.5,
      'outstanding_amount': 7,
      'credit_note_total': 1.0,
      'status': InvoiceModel.statusPartial,
      'created_by': 'admin-1',
      'created_at': timestamp,
      'updated_at': timestamp,
      'financial_minor_units': {
        'total': 1050,
        'subtotal': 1050,
        'discount': 0,
        'amount_received': 250,
        'outstanding_amount': 700,
        'credit_note_total': 0,
        'items.0.unit_price': 525,
        'items.0.subtotal': 1050,
      },
    }, 'invoice-1');

    expect(model.total, 10.5);
    expect(model.amountReceived, 2.5);
    expect(model.creditNoteTotal, 1.0);
    expect(model.items.single.unitPrice, 5.25);
    expect(model.toJson()['financial_minor_units'], {
      'total': 1050,
      'subtotal': 1050,
      'discount': 0,
      'amount_received': 250,
      'outstanding_amount': 700,
      'credit_note_total': 100,
      'items.0.unit_price': 525,
      'items.0.subtotal': 1050,
    });
  });
}
