import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/invoice_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);
  final baseJson = <String, dynamic>{
    'invoice_number': 'INV-2026-0001',
    'type': 'sale',
    'customer_id': 'c1',
    'customer_name': 'Test Customer',
    'shop_id': 's1',
    'shop_name': 'Test Shop',
    'route_id': 'r1',
    'seller_id': 'u1',
    'seller_name': 'Seller A',
    'items': [
      {
        'variant_id': 'v1',
        'sku': 'SKU-001',
        'product_name': 'Classic Boot',
        'size': '42',
        'color': 'Black',
        'qty': 12,
        'unit_price': 150.0,
        'subtotal': 1800.0,
      },
    ],
    'subtotal': 1800.0,
    'discount': 100.0,
    'total': 1700.0,
    'sale_type': 'credit',
    'amount_received': 500.0,
    'status': 'issued',
    'notes': 'Urgent order',
    'created_by': 'u1',
    'created_at': ts,
    'updated_at': ts,
  };

  group('InvoiceModel.fromJson', () {
    test('parses all fields correctly', () {
      final m = InvoiceModel.fromJson(baseJson, 'inv1');
      expect(m.id, 'inv1');
      expect(m.invoiceNumber, 'INV-2026-0001');
      expect(m.type, 'sale');
      expect(m.customerId, 'c1');
      expect(m.customerName, 'Test Customer');
      expect(m.shopId, 's1');
      expect(m.shopName, 'Test Shop');
      expect(m.routeId, 'r1');
      expect(m.sellerId, 'u1');
      expect(m.sellerName, 'Seller A');
      expect(m.items, hasLength(1));
      expect(m.subtotal, 1800.0);
      expect(m.discount, 100.0);
      expect(m.total, 1700.0);
      expect(m.saleType, 'credit');
      expect(m.amountReceived, 500.0);
      expect(m.status, 'issued');
      expect(m.notes, 'Urgent order');
    });

    test('missing fields use defaults', () {
      final m = InvoiceModel.fromJson({}, 'inv2');
      expect(m.invoiceNumber, '');
      expect(m.type, InvoiceModel.typeSale);
      expect(m.items, isEmpty);
      expect(m.subtotal, 0);
      expect(m.discount, 0);
      expect(m.total, 0);
      expect(m.saleType, 'credit');
      expect(m.amountReceived, 0);
      expect(m.status, InvoiceModel.statusDraft);
    });

    test('parses items list', () {
      final m = InvoiceModel.fromJson(baseJson, 'inv3');
      final item = m.items.first;
      expect(item.variantId, 'v1');
      expect(item.sku, 'SKU-001');
      expect(item.productName, 'Classic Boot');
      expect(item.size, '42');
      expect(item.color, 'Black');
      expect(item.qty, 12);
      expect(item.unitPrice, 150.0);
      expect(item.subtotal, 1800.0);
    });
  });

  group('InvoiceModel type helpers', () {
    test('isSale is true for sale type', () {
      final m = InvoiceModel.fromJson(baseJson, 'inv1');
      expect(m.isSale, isTrue);
      expect(m.isReturn, isFalse);
      expect(m.isCreditNote, isFalse);
    });

    test('isReturn is true for return type', () {
      final m = InvoiceModel.fromJson({...baseJson, 'type': 'return'}, 'inv2');
      expect(m.isReturn, isTrue);
    });

    test('isCreditNote is true for credit_note type', () {
      final m =
          InvoiceModel.fromJson({...baseJson, 'type': 'credit_note'}, 'inv3');
      expect(m.isCreditNote, isTrue);
    });
  });

  group('InvoiceModel status helpers', () {
    test('isDraft is true for draft status', () {
      final m = InvoiceModel.fromJson({...baseJson, 'status': 'draft'}, 'i1');
      expect(m.isDraft, isTrue);
    });

    test('isIssued is true for issued status', () {
      final m = InvoiceModel.fromJson(baseJson, 'i2');
      expect(m.isIssued, isTrue);
    });

    test('isPaid is true for paid status', () {
      final m = InvoiceModel.fromJson({...baseJson, 'status': 'paid'}, 'i3');
      expect(m.isPaid, isTrue);
    });
  });

  group('InvoiceModel.toJson', () {
    test('round-trips through fromJson/toJson', () {
      final original = InvoiceModel.fromJson(baseJson, 'inv1');
      final json = original.toJson();
      final restored = InvoiceModel.fromJson(json, 'inv1');
      expect(restored.invoiceNumber, original.invoiceNumber);
      expect(restored.type, original.type);
      expect(restored.total, original.total);
      expect(restored.amountReceived, original.amountReceived);
      expect(restored.items, hasLength(original.items.length));
    });
  });

  group('InvoiceModel constants', () {
    test('type constants', () {
      expect(InvoiceModel.typeSale, 'sale');
      expect(InvoiceModel.typeReturn, 'return');
      expect(InvoiceModel.typeCreditNote, 'credit_note');
    });

    test('status constants', () {
      expect(InvoiceModel.statusDraft, 'draft');
      expect(InvoiceModel.statusIssued, 'issued');
      expect(InvoiceModel.statusPaid, 'paid');
      expect(InvoiceModel.statusPartial, 'partial');
    });
  });
}
