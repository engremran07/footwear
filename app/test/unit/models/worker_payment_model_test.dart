import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/worker_payment_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);
  final base = <String, dynamic>{
    'worker_id': 'w1',
    'worker_name': 'Ali Hassan',
    'worker_type': 'pk',
    'amount': 2500.0,
    'pairs_count': 50,
    'period': '2024-01',
    'status': 'draft',
    'approved_by': null,
    'approved_at': null,
    'notes': null,
    'created_at': ts,
    'updated_at': ts,
  };

  group('WorkerPaymentModel.fromJson', () {
    test('parses all fields', () {
      final m = WorkerPaymentModel.fromJson(base, 'wp1');
      expect(m.id, 'wp1');
      expect(m.workerId, 'w1');
      expect(m.workerName, 'Ali Hassan');
      expect(m.workerType, 'pk');
      expect(m.amount, 2500.0);
      expect(m.pairsCount, 50);
      expect(m.period, '2024-01');
      expect(m.status, 'draft');
    });

    test('optional fields null', () {
      final m = WorkerPaymentModel.fromJson(base, 'wp1');
      expect(m.approvedBy, isNull);
      expect(m.approvedAt, isNull);
      expect(m.notes, isNull);
    });

    test('approval fields parsed when set', () {
      final m = WorkerPaymentModel.fromJson({
        ...base,
        'status': 'approved',
        'approved_by': 'admin1',
        'approved_at': ts,
        'notes': 'Approved on time',
      }, 'wp2');
      expect(m.status, 'approved');
      expect(m.approvedBy, 'admin1');
      expect(m.approvedAt, ts);
      expect(m.notes, 'Approved on time');
    });

    test('defaults for empty json', () {
      final m = WorkerPaymentModel.fromJson({}, 'wp3');
      expect(m.status, 'draft');
      expect(m.workerType, 'pk');
      expect(m.amount, 0.0);
    });
  });

  group('WorkerPaymentModel.toJson + copyWith', () {
    test('round-trip preserves data', () {
      final original = WorkerPaymentModel.fromJson(base, 'wp1');
      final restored = WorkerPaymentModel.fromJson(original.toJson(), 'wp1');
      expect(restored.workerId, original.workerId);
      expect(restored.period, original.period);
    });

    test('copyWith changes status', () {
      final m = WorkerPaymentModel.fromJson(base, 'wp1');
      final copy = m.copyWith(status: 'paid');
      expect(copy.status, 'paid');
      expect(copy.workerId, m.workerId);
    });
  });
}
