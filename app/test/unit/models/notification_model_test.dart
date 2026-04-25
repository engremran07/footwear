import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/notification_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(1_000_000);

  final baseJson = <String, dynamic>{
    'type': 'transaction',
    'shop_id': 'shop1',
    'shop_name': 'Al-Noor Store',
    'route_id': 'route1',
    'seller_id': 'seller1',
    'seller_name': 'Ahmed',
    'amount': 1500.0,
    'transaction_type': 'cash_out',
    'invoice_number': null,
    'ref_id': 'tx1',
    'target_role': 'admin',
    'read': false,
    'created_by': 'seller1',
    'created_at': ts,
  };

  group('NotificationModel.fromJson', () {
    test('parses all fields correctly', () {
      final m = NotificationModel.fromJson(baseJson, 'n1');
      expect(m.id, 'n1');
      expect(m.type, 'transaction');
      expect(m.shopId, 'shop1');
      expect(m.shopName, 'Al-Noor Store');
      expect(m.routeId, 'route1');
      expect(m.sellerId, 'seller1');
      expect(m.sellerName, 'Ahmed');
      expect(m.amount, 1500.0);
      expect(m.transactionType, 'cash_out');
      expect(m.invoiceNumber, isNull);
      expect(m.refId, 'tx1');
      expect(m.targetRole, 'admin');
      expect(m.read, isFalse);
      expect(m.readAt, isNull);
      expect(m.createdBy, 'seller1');
      expect(m.createdAt, ts);
    });

    test('read defaults to false when absent', () {
      final json = Map<String, dynamic>.from(baseJson)..remove('read');
      final m = NotificationModel.fromJson(json, 'n2');
      expect(m.read, isFalse);
    });

    test('invoiceNumber is populated for invoice type', () {
      final json = Map<String, dynamic>.from(baseJson)
        ..['type'] = 'invoice'
        ..['invoice_number'] = 'INV-042';
      final m = NotificationModel.fromJson(json, 'n3');
      expect(m.type, 'invoice');
      expect(m.invoiceNumber, 'INV-042');
    });

    test('missing fields use defaults', () {
      final m = NotificationModel.fromJson({}, 'n4');
      expect(m.type, 'transaction');
      expect(m.shopId, '');
      expect(m.amount, 0.0);
      expect(m.read, isFalse);
      expect(m.targetRole, 'admin');
    });
  });

  group('NotificationModel.toJson', () {
    test('round-trips all core fields', () {
      final m = NotificationModel.fromJson(baseJson, 'n5');
      final json = m.toJson();
      expect(json['type'], 'transaction');
      expect(json['shop_id'], 'shop1');
      expect(json['amount'], 1500.0);
      expect(json['read'], isFalse);
      expect(json['target_role'], 'admin');
      expect(json['invoice_number'], isNull);
    });

    test('invoice_number is included when set', () {
      final json = Map<String, dynamic>.from(baseJson)
        ..['type'] = 'invoice'
        ..['invoice_number'] = 'INV-099';
      final m = NotificationModel.fromJson(json, 'n6');
      final out = m.toJson();
      expect(out['invoice_number'], 'INV-099');
    });
  });

  group('NotificationModel equality + hashCode', () {
    test('two instances with same fields are equal', () {
      final a = NotificationModel.fromJson(baseJson, 'n7');
      final b = NotificationModel.fromJson(baseJson, 'n7');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different ids are not equal', () {
      final a = NotificationModel.fromJson(baseJson, 'n7');
      final b = NotificationModel.fromJson(baseJson, 'n8');
      expect(a, isNot(equals(b)));
    });

    test('same id with different read state are equal (id-based equality)', () {
      final a = NotificationModel.fromJson(baseJson, 'n9');
      final json2 = Map<String, dynamic>.from(baseJson)..['read'] = true;
      final b = NotificationModel.fromJson(json2, 'n9');
      // Equality is id-based — same doc, different in-memory state = same identity
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      // But the fields differ
      expect(a.read, isFalse);
      expect(b.read, isTrue);
    });
  });
}
