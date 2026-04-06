// Tests for ShopModel bad-debt fields added in audit v7 (2026-04-07).
//
// Shops = Customers in this app (unified entity).
// bad_debt / bad_debt_amount / bad_debt_date are set by
// ShopNotifier.markAsBadDebt() — admin only.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/shop_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);

  final baseJson = <String, dynamic>{
    'name': 'Hassan Traders',
    'route_id': 'r1',
    'route_number': 2,
    'balance': 3000.0,
    'active': true,
    'created_by': 'admin1',
    'created_at': ts,
    'updated_at': ts,
  };

  // ── bad_debt field defaults ───────────────────────────────────────────────────

  group('ShopModel — bad debt defaults', () {
    test('bad_debt defaults to false when field absent', () {
      final m = ShopModel.fromJson(baseJson, 's1');
      expect(m.badDebt, isFalse);
    });

    test('bad_debt_amount defaults to 0 when field absent', () {
      final m = ShopModel.fromJson(baseJson, 's1');
      expect(m.badDebtAmount, 0);
    });

    test('bad_debt_date defaults to null when field absent', () {
      final m = ShopModel.fromJson(baseJson, 's1');
      expect(m.badDebtDate, isNull);
    });
  });

  // ── bad_debt field parsing ───────────────────────────────────────────────────

  group('ShopModel — bad debt parsing', () {
    test('parses bad_debt = true correctly', () {
      final m = ShopModel.fromJson({...baseJson, 'bad_debt': true}, 's2');
      expect(m.badDebt, isTrue);
    });

    test('parses bad_debt_amount correctly', () {
      final m = ShopModel.fromJson({
        ...baseJson,
        'bad_debt': true,
        'bad_debt_amount': 3000.0,
        'bad_debt_date': ts,
      }, 's3');
      expect(m.badDebtAmount, 3000.0);
      expect(m.badDebtDate, ts);
    });

    test('bad_debt_amount coerces int to double', () {
      final m = ShopModel.fromJson({
        ...baseJson,
        'bad_debt': true,
        'bad_debt_amount': 5000, // int in Firestore
      }, 's4');
      expect(m.badDebtAmount, 5000.0);
    });
  });

  // ── toJson round-trip ────────────────────────────────────────────────────────

  group('ShopModel — bad debt toJson round-trip', () {
    test('bad_debt fields survive fromJson → toJson → fromJson', () {
      final original = ShopModel.fromJson({
        ...baseJson,
        'bad_debt': true,
        'bad_debt_amount': 2500.0,
        'bad_debt_date': ts,
      }, 's5');
      final json = original.toJson();
      final restored = ShopModel.fromJson(json, 's5');
      expect(restored.badDebt, isTrue);
      expect(restored.badDebtAmount, 2500.0);
      expect(restored.badDebtDate, ts);
    });

    test('bad_debt_date is omitted from toJson when null', () {
      final original = ShopModel.fromJson(baseJson, 's6');
      final json = original.toJson();
      expect(json.containsKey('bad_debt_date'), isFalse);
    });

    test('bad_debt_date is included in toJson when set', () {
      final original = ShopModel.fromJson({
        ...baseJson,
        'bad_debt': true,
        'bad_debt_amount': 1000.0,
        'bad_debt_date': ts,
      }, 's7');
      final json = original.toJson();
      expect(json.containsKey('bad_debt_date'), isTrue);
      expect(json['bad_debt_date'], ts);
    });
  });

  // ── hasOutstanding getter ────────────────────────────────────────────────────

  group('ShopModel — hasOutstanding after bad debt', () {
    test('hasOutstanding false when balance zeroed after write-off', () {
      // After markAsBadDebt(), balance is set to 0.0.
      final m = ShopModel.fromJson({
        ...baseJson,
        'balance': 0.0,
        'bad_debt': true,
        'bad_debt_amount': 3000.0,
        'bad_debt_date': ts,
      }, 's8');
      expect(m.hasOutstanding, isFalse);
      expect(m.badDebt, isTrue);
      expect(m.badDebtAmount, 3000.0);
    });

    test('hasOutstanding true while balance > 0 (before write-off)', () {
      final m = ShopModel.fromJson({...baseJson, 'balance': 3000.0}, 's9');
      expect(m.hasOutstanding, isTrue);
      expect(m.badDebt, isFalse);
    });
  });
}
