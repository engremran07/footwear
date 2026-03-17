import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/cash_approval_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);
  final base = <String, dynamic>{
    'transaction_id': 'ct1',
    'amount': 1000.0,
    'type': 'cash_in',
    'reference': 'SALE-001',
    'status': 'pending',
    'approved_by': null,
    'notes': null,
    'created_at': ts,
    'updated_at': ts,
  };

  group('CashApprovalModel.fromJson', () {
    test('parses pending approval', () {
      final m = CashApprovalModel.fromJson(base, 'ca1');
      expect(m.id, 'ca1');
      expect(m.transactionId, 'ct1');
      expect(m.amount, 1000.0);
      expect(m.type, 'cash_in');
      expect(m.status, 'pending');
      expect(m.approvedBy, isNull);
      expect(m.notes, isNull);
    });

    test('parses approved state', () {
      final m = CashApprovalModel.fromJson({
        ...base,
        'status': 'approved',
        'approved_by': 'admin1',
        'notes': 'Looks good',
      }, 'ca2');
      expect(m.status, 'approved');
      expect(m.approvedBy, 'admin1');
      expect(m.notes, 'Looks good');
    });

    test('defaults for empty json', () {
      final m = CashApprovalModel.fromJson({}, 'ca3');
      expect(m.status, 'pending');
      expect(m.amount, 0.0);
    });
  });

  group('CashApprovalModel.toJson + copyWith', () {
    test('round-trip', () {
      final original = CashApprovalModel.fromJson(base, 'ca1');
      final restored = CashApprovalModel.fromJson(original.toJson(), 'ca1');
      expect(restored.transactionId, original.transactionId);
      expect(restored.reference, original.reference);
    });

    test('copyWith changes status', () {
      final m = CashApprovalModel.fromJson(base, 'ca1');
      final copy = m.copyWith(status: 'rejected', notes: 'Duplicate entry');
      expect(copy.status, 'rejected');
      expect(copy.notes, 'Duplicate entry');
      expect(copy.transactionId, m.transactionId);
    });
  });
}
