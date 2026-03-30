import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/customer_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);
  final baseJson = <String, dynamic>{
    'name': 'Hassan Traders',
    'phone': '+966509876543',
    'city': 'Dammam',
    'balance': 2500.0,
    'active': true,
    'bad_debt': false,
    'bad_debt_amount': 0,
    'created_by': 'seller1',
    'created_at': ts,
    'updated_at': ts,
  };

  group('CustomerModel.fromJson', () {
    test('parses all fields correctly', () {
      final m = CustomerModel.fromJson(baseJson, 'c1');
      expect(m.id, 'c1');
      expect(m.name, 'Hassan Traders');
      expect(m.phone, '+966509876543');
      expect(m.city, 'Dammam');
      expect(m.balance, 2500.0);
      expect(m.active, isTrue);
      expect(m.badDebt, isFalse);
      expect(m.badDebtAmount, 0);
      expect(m.badDebtDate, isNull);
      expect(m.createdBy, 'seller1');
    });

    test('missing fields use defaults', () {
      final m = CustomerModel.fromJson({}, 'c2');
      expect(m.name, '');
      expect(m.phone, isNull);
      expect(m.city, isNull);
      expect(m.balance, 0);
      expect(m.active, isTrue);
      expect(m.badDebt, isFalse);
      expect(m.badDebtAmount, 0);
    });

    test('hasOutstanding is true when balance > 0', () {
      final m = CustomerModel.fromJson(baseJson, 'c3');
      expect(m.hasOutstanding, isTrue);
    });

    test('hasOutstanding is false when balance is 0', () {
      final m = CustomerModel.fromJson({...baseJson, 'balance': 0}, 'c4');
      expect(m.hasOutstanding, isFalse);
    });

    test('parses bad_debt fields', () {
      final m = CustomerModel.fromJson({
        ...baseJson,
        'bad_debt': true,
        'bad_debt_amount': 1000.0,
        'bad_debt_date': ts,
      }, 'c5');
      expect(m.badDebt, isTrue);
      expect(m.badDebtAmount, 1000.0);
      expect(m.badDebtDate, ts);
    });
  });

  group('CustomerModel.toJson', () {
    test('round-trips through fromJson/toJson', () {
      final original = CustomerModel.fromJson(baseJson, 'c1');
      final json = original.toJson();
      final restored = CustomerModel.fromJson(json, 'c1');
      expect(restored.name, original.name);
      expect(restored.phone, original.phone);
      expect(restored.balance, original.balance);
      expect(restored.badDebt, original.badDebt);
    });
  });
}
