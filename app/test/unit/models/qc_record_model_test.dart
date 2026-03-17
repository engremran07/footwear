import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/qc_record_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);
  final rejectedItems = [
    {'inventory_item_id': 'ii1', 'size': '42', 'reason': 'stitching failure'},
  ];
  final base = <String, dynamic>{
    'batch_id': 'b1',
    'product_id': 'p1',
    'passed_qty': 90,
    'rejected_qty': 10,
    'worker_id': null,
    'rejected_items': rejectedItems,
    'notes': null,
    'inspector': 'user1',
    'created_at': ts,
  };

  group('QcRecordModel.fromJson', () {
    test('parses required fields', () {
      final m = QcRecordModel.fromJson(base, 'qc1');
      expect(m.id, 'qc1');
      expect(m.batchId, 'b1');
      expect(m.productId, 'p1');
      expect(m.passedQty, 90);
      expect(m.rejectedQty, 10);
      expect(m.inspector, 'user1');
    });

    test('parses rejected items', () {
      final m = QcRecordModel.fromJson(base, 'qc1');
      expect(m.rejectedItems, hasLength(1));
      expect(m.rejectedItems.first['size'], '42');
      expect(m.rejectedItems.first['reason'], 'stitching failure');
    });

    test('optional fields null when not set', () {
      final m = QcRecordModel.fromJson(base, 'qc1');
      expect(m.workerId, isNull);
      expect(m.notes, isNull);
    });

    test('parses worker and notes when present', () {
      final m = QcRecordModel.fromJson({
        ...base,
        'worker_id': 'w1',
        'notes': 'Minor issues',
      }, 'qc2');
      expect(m.workerId, 'w1');
      expect(m.notes, 'Minor issues');
    });

    test('defaults for empty json', () {
      final m = QcRecordModel.fromJson({}, 'qc3');
      expect(m.passedQty, 0);
      expect(m.rejectedQty, 0);
      expect(m.rejectedItems, isEmpty);
      expect(m.inspector, '');
    });
  });

  group('QcRecordModel.toJson + copyWith', () {
    test('round-trip preserves rejected items', () {
      final original = QcRecordModel.fromJson(base, 'qc1');
      final restored = QcRecordModel.fromJson(original.toJson(), 'qc1');
      expect(restored.batchId, original.batchId);
      expect(restored.rejectedItems, hasLength(1));
    });

    test('copyWith changes notes', () {
      final m = QcRecordModel.fromJson(base, 'qc1');
      final copy = m.copyWith(notes: 'Updated notes');
      expect(copy.notes, 'Updated notes');
      expect(copy.batchId, m.batchId);
    });
  });
}
