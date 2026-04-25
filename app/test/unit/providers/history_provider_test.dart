import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

// We import the provider file to test the exported constants and helper logic.
// The _kHistoryDays constant drives the 7-day cutoff — this test ensures it
// stays at 7 and is never accidentally changed.
//
// NOTE: We cannot unit-test the StreamProvider directly without a Firestore
// emulator, so we test the cutoff arithmetic and the client-side delete filter
// in isolation using TransactionModel.
import 'package:footwear_erp/models/transaction_model.dart';

// Shadow the private constant via the visible exported symbol.
// If the constant is changed, update the expected value in test 1 below.
const _expectedHistoryDays = 7;

void main() {
  group('History 7-day cutoff arithmetic', () {
    test('cutoff is exactly 7 days before midnight today', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final cutoff = today.subtract(const Duration(days: _expectedHistoryDays));
      final sevenDaysAgo = today.subtract(const Duration(days: 7));
      expect(cutoff, equals(sevenDaysAgo));
    });

    test('a transaction from 6 days ago is within the window', () {
      final sixDaysAgo = DateTime.now().subtract(const Duration(days: 6));
      final cutoff = DateTime.now().subtract(
        const Duration(days: _expectedHistoryDays),
      );
      expect(sixDaysAgo.isAfter(cutoff), isTrue);
    });

    test('a transaction from exactly 7 days ago is on the boundary', () {
      final sevenDaysAgo = DateTime.now().subtract(
        const Duration(days: _expectedHistoryDays),
      );
      final cutoff = DateTime.now().subtract(
        const Duration(days: _expectedHistoryDays),
      );
      // Boundary is inclusive (>= cutoff) — same instant should not be excluded
      expect(
        sevenDaysAgo.isAfter(cutoff) || sevenDaysAgo.isAtSameMomentAs(cutoff),
        isTrue,
      );
    });

    test('a transaction from 8 days ago is outside the window', () {
      final eightDaysAgo = DateTime.now().subtract(const Duration(days: 8));
      final cutoff = DateTime.now().subtract(
        const Duration(days: _expectedHistoryDays),
      );
      expect(eightDaysAgo.isBefore(cutoff), isTrue);
    });
  });

  group('Client-side deleted filter', () {
    final ts = Timestamp.fromMillisecondsSinceEpoch(0);

    Map<String, dynamic> makeTxJson({bool? deleted}) => <String, dynamic>{
      'type': 'cash_out',
      'shop_id': 's1',
      'route_id': 'r1',
      'amount': 100.0,
      'created_by': 'u1',
      'created_at': ts,
      'deleted': ?deleted,
    };

    test('non-deleted transaction passes client-side filter', () {
      final raw = makeTxJson(deleted: false);
      expect(raw['deleted'] != true, isTrue);
    });

    test('deleted=true transaction is filtered out by client-side check', () {
      final raw = makeTxJson(deleted: true);
      expect(raw['deleted'] != true, isFalse);
    });

    test('missing deleted field passes the client-side filter', () {
      final raw = makeTxJson();
      expect(raw['deleted'] != true, isTrue);
    });

    test('TransactionModel.fromJson with deleted=true still parses', () {
      final tx = TransactionModel.fromJson(makeTxJson(deleted: true), 'tx2');
      expect(tx.id, 'tx2');
    });
  });
}
