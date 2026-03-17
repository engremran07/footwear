import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/expense_approval_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);
  final base = <String, dynamic>{
    'expense_id': 'e1',
    'amount': 500.0,
    'category': 'utilities',
    'description': 'Electricity bill',
    'status': 'pending',
    'approved_by': null,
    'notes': null,
    'created_at': ts,
    'updated_at': ts,
  };

  group('ExpenseApprovalModel.fromJson', () {
    test('parses pending', () {
      final m = ExpenseApprovalModel.fromJson(base, 'ea1');
      expect(m.id, 'ea1');
      expect(m.expenseId, 'e1');
      expect(m.amount, 500.0);
      expect(m.category, 'utilities');
      expect(m.description, 'Electricity bill');
      expect(m.status, 'pending');
    });

    test('parses approved', () {
      final m = ExpenseApprovalModel.fromJson({
        ...base,
        'status': 'approved',
        'approved_by': 'admin1',
        'notes': 'Valid receipt',
      }, 'ea2');
      expect(m.status, 'approved');
      expect(m.approvedBy, 'admin1');
      expect(m.notes, 'Valid receipt');
    });

    test('defaults', () {
      final m = ExpenseApprovalModel.fromJson({}, 'ea3');
      expect(m.status, 'pending');
      expect(m.amount, 0.0);
    });
  });

  group('ExpenseApprovalModel.toJson + copyWith', () {
    test('round-trip', () {
      final original = ExpenseApprovalModel.fromJson(base, 'ea1');
      final restored = ExpenseApprovalModel.fromJson(original.toJson(), 'ea1');
      expect(restored.expenseId, original.expenseId);
      expect(restored.category, original.category);
    });

    test('copyWith changes status', () {
      final m = ExpenseApprovalModel.fromJson(base, 'ea1');
      final copy = m.copyWith(status: 'rejected');
      expect(copy.status, 'rejected');
      expect(copy.expenseId, m.expenseId);
    });
  });
}
