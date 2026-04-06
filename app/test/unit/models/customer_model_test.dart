import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/customer_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);
  final baseJson = <String, dynamic>{
    'name': 'Hassan Traders',
    'route_id': 'route-7',
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
      expect(m.routeId, 'route-7');
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
      expect(m.routeId, isNull);
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
      expect(restored.routeId, original.routeId);
      expect(restored.phone, original.phone);
      expect(restored.balance, original.balance);
      expect(restored.badDebt, original.badDebt);
    });

    test('omits route_id when null', () {
      final json =
          CustomerModel.fromJson({...baseJson, 'route_id': null}, 'c11')
              .toJson();
      expect(json.containsKey('route_id'), isFalse);
    });
  });

  group('CustomerModel balance edge cases', () {
    test('hasOutstanding is false for negative balance', () {
      final m = CustomerModel.fromJson({...baseJson, 'balance': -100.0}, 'c6');
      expect(m.hasOutstanding, isFalse);
    });

    test('balance can be negative (overpayment scenario)', () {
      final m = CustomerModel.fromJson({...baseJson, 'balance': -50.0}, 'c7');
      expect(m.balance, -50.0);
    });

    test('active defaults to true when missing', () {
      final m = CustomerModel.fromJson({'name': 'Test'}, 'c8');
      expect(m.active, isTrue);
    });

    test('active can be false', () {
      final m = CustomerModel.fromJson({...baseJson, 'active': false}, 'c9');
      expect(m.active, isFalse);
    });

    test('bad_debt amount round-trips for non-zero value', () {
      final m = CustomerModel.fromJson({
        ...baseJson,
        'bad_debt': true,
        'bad_debt_amount': 3500.75,
        'bad_debt_date': ts,
      }, 'c10');
      final json = m.toJson();
      final restored = CustomerModel.fromJson(json, 'c10');
      expect(restored.badDebt, isTrue);
      expect(restored.badDebtAmount, 3500.75);
      expect(restored.badDebtDate, ts);
    });
  });
}
