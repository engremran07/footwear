import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/cash_transaction_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);
  final base = <String, dynamic>{
    'type': 'cash_in',
    'amount': 1000.0,
    'reference': 'SALE-001',
    'pnl_category': 'revenue',
    'description': 'Customer payment',
    'worker_id': null,
    'worker_payment_id': null,
    'status': 'pending',
    'approved_by': null,
    'approved_at': null,
    'created_at': ts,
    'updated_at': ts,
  };

  group('CashTransactionModel.fromJson', () {
    test('parses cash_in transaction', () {
      final m = CashTransactionModel.fromJson(base, 'ct1');
      expect(m.id, 'ct1');
      expect(m.type, 'cash_in');
      expect(m.amount, 1000.0);
      expect(m.reference, 'SALE-001');
      expect(m.pnlCategory, 'revenue');
      expect(m.status, 'pending');
    });

    test('parses cash_out transaction', () {
      final m = CashTransactionModel.fromJson({
        ...base,
        'type': 'cash_out',
        'pnl_category': 'expenses',
        'amount': 200.0,
      }, 'ct2');
      expect(m.type, 'cash_out');
      expect(m.pnlCategory, 'expenses');
    });

    test('optional fields null', () {
      final m = CashTransactionModel.fromJson(base, 'ct1');
      expect(m.workerId, isNull);
      expect(m.workerPaymentId, isNull);
      expect(m.approvedBy, isNull);
    });

    test('worker payment transaction', () {
      final m = CashTransactionModel.fromJson({
        ...base,
        'type': 'cash_out',
        'pnl_category': 'worker_cost',
        'worker_id': 'w1',
        'worker_payment_id': 'wp1',
      }, 'ct3');
      expect(m.workerId, 'w1');
      expect(m.workerPaymentId, 'wp1');
    });

    test('defaults for empty json', () {
      final m = CashTransactionModel.fromJson({}, 'ct4');
      expect(m.type, 'cash_in');
      expect(m.pnlCategory, 'other');
      expect(m.status, 'pending');
    });
  });

  group('CashTransactionModel.toJson + copyWith', () {
    test('round-trip', () {
      final original = CashTransactionModel.fromJson(base, 'ct1');
      final restored = CashTransactionModel.fromJson(original.toJson(), 'ct1');
      expect(restored.type, original.type);
      expect(restored.amount, original.amount);
    });

    test('copyWith changes status', () {
      final m = CashTransactionModel.fromJson(base, 'ct1');
      final copy = m.copyWith(status: 'approved');
      expect(copy.status, 'approved');
      expect(copy.reference, m.reference);
    });
  });
}
