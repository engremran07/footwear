import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/transaction_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);

  group('TransactionItem', () {
    final itemJson = <String, dynamic>{
      'variant_id': 'v1',
      'sku': 'SKU-001',
      'product_name': 'Sandal',
      'size': '40',
      'color': 'Brown',
      'qty': 6,
      'unit_price': 100.0,
      'subtotal': 600.0,
    };

    test('fromJson parses all fields', () {
      final item = TransactionItem.fromJson(itemJson);
      expect(item.variantId, 'v1');
      expect(item.sku, 'SKU-001');
      expect(item.productName, 'Sandal');
      expect(item.size, '40');
      expect(item.color, 'Brown');
      expect(item.qty, 6);
      expect(item.unitPrice, 100.0);
      expect(item.subtotal, 600.0);
    });

    test('fromJson defaults for missing fields', () {
      final item = TransactionItem.fromJson({});
      expect(item.variantId, '');
      expect(item.sku, '');
      expect(item.productName, '');
      expect(item.qty, 0);
      expect(item.unitPrice, 0);
      expect(item.subtotal, 0);
    });

    test('toJson round-trips', () {
      final original = TransactionItem.fromJson(itemJson);
      final json = original.toJson();
      final restored = TransactionItem.fromJson(json);
      expect(restored.variantId, original.variantId);
      expect(restored.qty, original.qty);
      expect(restored.unitPrice, original.unitPrice);
    });
  });

  group('TransactionModel.fromJson', () {
    final baseJson = <String, dynamic>{
      'shop_id': 's1',
      'shop_name': 'Shop A',
      'route_id': 'r1',
      'type': 'cash_in',
      'sale_type': 'cash',
      'amount': 5000.0,
      'description': 'Cash collection',
      'items': [],
      'invoice_id': 'inv1',
      'invoice_number': 'INV-2026-0001',
      'created_by': 'u1',
      'created_at': ts,
      'deleted': false,
    };

    test('parses all fields correctly', () {
      final m = TransactionModel.fromJson(baseJson, 't1');
      expect(m.id, 't1');
      expect(m.shopId, 's1');
      expect(m.shopName, 'Shop A');
      expect(m.routeId, 'r1');
      expect(m.type, 'cash_in');
      expect(m.saleType, 'cash');
      expect(m.amount, 5000.0);
      expect(m.description, 'Cash collection');
      expect(m.invoiceId, 'inv1');
      expect(m.invoiceNumber, 'INV-2026-0001');
    });

    test('missing fields use defaults', () {
      final m = TransactionModel.fromJson({}, 't2');
      expect(m.shopId, '');
      expect(m.shopName, '');
      expect(m.routeId, '');
      expect(m.type, 'cash_out');
      expect(m.amount, 0);
      expect(m.items, isEmpty);
    });
  });

  group('TransactionModel type helpers', () {
    test('isCashIn', () {
      final m = TransactionModel.fromJson({
        'type': 'cash_in',
        'created_at': ts,
      }, 't1');
      expect(m.isCashIn, isTrue);
      expect(m.isCashOut, isFalse);
      expect(m.isReturn, isFalse);
    });

    test('isCashOut', () {
      final m = TransactionModel.fromJson({
        'type': 'cash_out',
        'created_at': ts,
      }, 't2');
      expect(m.isCashOut, isTrue);
    });

    test('isReturn', () {
      final m = TransactionModel.fromJson({
        'type': 'return',
        'created_at': ts,
      }, 't3');
      expect(m.isReturn, isTrue);
    });

    test('hasItems is false for empty items', () {
      final m = TransactionModel.fromJson({'created_at': ts}, 't4');
      expect(m.hasItems, isFalse);
    });

    test('hasItems is true when items present', () {
      final m = TransactionModel.fromJson({
        'created_at': ts,
        'items': [
          {'variant_id': 'v1', 'qty': 1},
        ],
      }, 't5');
      expect(m.hasItems, isTrue);
    });
  });

  group('TransactionModel.toJson', () {
    test('round-trips through fromJson/toJson', () {
      final original = TransactionModel.fromJson({
        'shop_id': 's1',
        'shop_name': 'Shop A',
        'route_id': 'r1',
        'type': 'cash_in',
        'amount': 3000.0,
        'created_by': 'u1',
        'created_at': ts,
      }, 't1');
      final json = original.toJson();
      final restored = TransactionModel.fromJson(json, 't1');
      expect(restored.shopId, original.shopId);
      expect(restored.type, original.type);
      expect(restored.amount, original.amount);
    });

    test('includes deleted audit fields when present', () {
      final original = TransactionModel.fromJson({
        'shop_id': 's1',
        'shop_name': 'Shop A',
        'route_id': 'r1',
        'type': 'cash_in',
        'sale_type': 'cash',
        'amount': 5000.0,
        'description': 'Cash collection',
        'items': [],
        'invoice_id': 'inv1',
        'invoice_number': 'INV-2026-0001',
        'created_by': 'u1',
        'created_at': ts,
        'deleted': true,
        'deleted_at': ts,
        'deleted_by': 'admin1',
      }, 't9');
      final json = original.toJson();
      expect(json['deleted'], isTrue);
      expect(json['deleted_at'], ts);
      expect(json['deleted_by'], 'admin1');
    });
  });

  group('TransactionModel constants', () {
    test('type constants are correct', () {
      expect(TransactionModel.typeCashIn, 'cash_in');
      expect(TransactionModel.typeCashOut, 'cash_out');
      expect(TransactionModel.typeReturn, 'return');
    });
  });
}
