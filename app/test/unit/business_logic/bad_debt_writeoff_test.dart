// Tests for bad debt write-off business logic.
//
// ShopNotifier.markAsBadDebt() flow:
//   1. Reads current balance from Firestore (customers/{shopId}.balance)
//   2. Batch: sets bad_debt=true, bad_debt_amount=balance, balance=0.0
//   3. Creates write_off transaction in 'transactions' collection
//
// These tests verify the pure math and guard conditions without Firestore.

import 'package:flutter_test/flutter_test.dart';

// ── Pure-logic mirrors of markAsBadDebt guards ───────────────────────────────

/// Returns error message if write-off preconditions fail; null if valid.
String? validateBadDebtWriteOff({required double currentBalance}) {
  if (currentBalance <= 0) {
    return 'No outstanding balance to write off';
  }
  return null;
}

/// Computes write-off transaction fields.
Map<String, dynamic> buildWriteOffTransaction({
  required String shopId,
  required String shopName,
  required String routeId,
  required double balance,
  required String createdBy,
}) {
  return {
    'type': 'write_off',
    'shop_id': shopId,
    'shop_name': shopName,
    'route_id': routeId,
    'amount': balance,
    'description': 'Bad debt write-off',
    'items': <Map<String, dynamic>>[],
    'created_by': createdBy,
  };
}

/// Returns the shop fields that should be updated during write-off.
Map<String, dynamic> buildWriteOffShopUpdate({required double balance}) {
  return {'bad_debt': true, 'bad_debt_amount': balance, 'balance': 0.0};
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── Precondition validation ───────────────────────────────────────────────

  group('markAsBadDebt — precondition guards', () {
    test('allows write-off when balance > 0', () {
      expect(validateBadDebtWriteOff(currentBalance: 5000), isNull);
    });

    test('allows write-off for small balances (e.g., 1 paisa)', () {
      expect(validateBadDebtWriteOff(currentBalance: 0.01), isNull);
    });

    test('rejects write-off when balance == 0', () {
      expect(validateBadDebtWriteOff(currentBalance: 0), isNotNull);
    });

    test('rejects write-off when balance < 0 (overpayment)', () {
      expect(validateBadDebtWriteOff(currentBalance: -500), isNotNull);
    });
  });

  // ── Write-off transaction fields ──────────────────────────────────────────

  group('markAsBadDebt — write_off transaction fields', () {
    final tx = buildWriteOffTransaction(
      shopId: 'shop-42',
      shopName: 'Al-Noor Shoes',
      routeId: 'route-3',
      balance: 7500.0,
      createdBy: 'admin1',
    );

    test('type is write_off', () {
      expect(tx['type'], 'write_off');
    });

    test('shop_id is set correctly', () {
      expect(tx['shop_id'], 'shop-42');
    });

    test('amount equals outstanding balance', () {
      expect(tx['amount'], 7500.0);
    });

    test('route_id is populated', () {
      expect(tx['route_id'], 'route-3');
    });

    test('items list is empty (no stock movement)', () {
      expect(tx['items'], isEmpty);
    });

    test('description contains bad debt language', () {
      expect((tx['description'] as String).toLowerCase(), contains('bad debt'));
    });
  });

  // ── Shop update fields ────────────────────────────────────────────────────

  group('markAsBadDebt — shop document update fields', () {
    final update = buildWriteOffShopUpdate(balance: 3200.0);

    test('bad_debt is set to true', () {
      expect(update['bad_debt'], isTrue);
    });

    test('bad_debt_amount equals original balance', () {
      expect(update['bad_debt_amount'], 3200.0);
    });

    test('balance is zeroed to 0.0', () {
      expect(update['balance'], 0.0);
    });
  });

  // ── Idempotency ───────────────────────────────────────────────────────────

  group('markAsBadDebt — post-write-off guards', () {
    test('shop with bad_debt=true and balance=0 blocks re-write-off', () {
      // A shop that has already been written off has balance=0, so the
      // precondition guard (balance <= 0) prevents a second write-off.
      expect(validateBadDebtWriteOff(currentBalance: 0), isNotNull);
    });
  });
}
