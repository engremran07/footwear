import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/waste_record_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);
  final base = <String, dynamic>{
    'qc_record_id': 'qc1',
    'batch_id': 'b1',
    'product_id': null,
    'size': null,
    'inventory_item_id': null,
    'worker_id': null,
    'reason': 'stitching failure',
    'disposed': false,
    'disposed_at': null,
    'created_at': ts,
  };

  group('WasteRecordModel.fromJson', () {
    test('parses required fields', () {
      final m = WasteRecordModel.fromJson(base, 'wr1');
      expect(m.id, 'wr1');
      expect(m.qcRecordId, 'qc1');
      expect(m.batchId, 'b1');
      expect(m.reason, 'stitching failure');
      expect(m.disposed, isFalse);
    });

    test('optional fields null', () {
      final m = WasteRecordModel.fromJson(base, 'wr1');
      expect(m.productId, isNull);
      expect(m.size, isNull);
      expect(m.inventoryItemId, isNull);
      expect(m.workerId, isNull);
      expect(m.disposedAt, isNull);
    });

    test('disposed record parses disposedAt', () {
      final m = WasteRecordModel.fromJson({
        ...base,
        'disposed': true,
        'disposed_at': ts,
        'product_id': 'p1',
        'size': '42',
        'inventory_item_id': 'ii1',
        'worker_id': 'w1',
      }, 'wr2');
      expect(m.disposed, isTrue);
      expect(m.disposedAt, ts);
      expect(m.productId, 'p1');
      expect(m.size, '42');
      expect(m.inventoryItemId, 'ii1');
      expect(m.workerId, 'w1');
    });

    test('defaults for empty json', () {
      final m = WasteRecordModel.fromJson({}, 'wr3');
      expect(m.reason, '');
      expect(m.disposed, isFalse);
    });
  });

  group('WasteRecordModel.toJson + copyWith', () {
    test('round-trip', () {
      final original = WasteRecordModel.fromJson({...base, 'size': '41'}, 'wr1');
      final restored = WasteRecordModel.fromJson(original.toJson(), 'wr1');
      expect(restored.batchId, original.batchId);
      expect(restored.size, '41');
    });

    test('copyWith marks disposed', () {
      final m = WasteRecordModel.fromJson(base, 'wr1');
      final copy = m.copyWith(disposed: true, disposedAt: ts);
      expect(copy.disposed, isTrue);
      expect(copy.disposedAt, ts);
    });
  });
}
