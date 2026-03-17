import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/expense_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);
  final base = <String, dynamic>{
    'category': 'rent',
    'amount': 5000.0,
    'description': 'Monthly warehouse rent',
    'receipt_url': null,
    'status': 'draft',
    'created_by': 'user1',
    'approved_by': null,
    'approved_at': null,
    'rejected_by': null,
    'rejected_at': null,
    'created_at': ts,
    'updated_at': ts,
  };

  group('ExpenseModel.fromJson', () {
    test('parses required fields', () {
      final m = ExpenseModel.fromJson(base, 'e1');
      expect(m.id, 'e1');
      expect(m.category, 'rent');
      expect(m.amount, 5000.0);
      expect(m.description, 'Monthly warehouse rent');
      expect(m.status, 'draft');
      expect(m.createdBy, 'user1');
    });

    test('nullable fields are null', () {
      final m = ExpenseModel.fromJson(base, 'e1');
      expect(m.receiptUrl, isNull);
      expect(m.approvedBy, isNull);
      expect(m.rejectedBy, isNull);
    });

    test('approved expense parses approval fields', () {
      final m = ExpenseModel.fromJson({
        ...base,
        'status': 'approved',
        'approved_by': 'admin1',
        'approved_at': ts,
        'receipt_url': 'http://example.com/receipt.jpg',
      }, 'e2');
      expect(m.status, 'approved');
      expect(m.approvedBy, 'admin1');
      expect(m.receiptUrl, 'http://example.com/receipt.jpg');
    });

    test('rejected expense parses rejection fields', () {
      final m = ExpenseModel.fromJson({
        ...base,
        'status': 'rejected',
        'rejected_by': 'admin1',
        'rejected_at': ts,
      }, 'e3');
      expect(m.status, 'rejected');
      expect(m.rejectedBy, 'admin1');
      expect(m.rejectedAt, ts);
    });

    test('defaults for empty json', () {
      final m = ExpenseModel.fromJson({}, 'e4');
      expect(m.category, 'other');
      expect(m.status, 'draft');
      expect(m.amount, 0.0);
    });
  });

  group('ExpenseModel.toJson + copyWith', () {
    test('round-trip preserves data', () {
      final original = ExpenseModel.fromJson(base, 'e1');
      final restored = ExpenseModel.fromJson(original.toJson(), 'e1');
      expect(restored.category, original.category);
      expect(restored.amount, original.amount);
    });

    test('copyWith changes status', () {
      final m = ExpenseModel.fromJson(base, 'e1');
      final copy = m.copyWith(status: 'pending_approval');
      expect(copy.status, 'pending_approval');
      expect(copy.description, m.description);
    });
  });
}
