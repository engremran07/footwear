import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/worker_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);
  final basePk = <String, dynamic>{
    'name': 'Ali Hassan',
    'type': 'pk',
    'rate_per_pair': 50.0,
    'currency': 'PKR',
    'total_earned': 5000.0,
    'pairs_produced': 100,
    'active': true,
    'joined_at': ts,
    'created_at': ts,
    'updated_at': ts,
  };

  group('WorkerModel.fromJson', () {
    test('parses PK worker', () {
      final m = WorkerModel.fromJson(basePk, 'w1');
      expect(m.id, 'w1');
      expect(m.name, 'Ali Hassan');
      expect(m.type, 'pk');
      expect(m.ratePerPair, 50.0);
      expect(m.currency, 'PKR');
      expect(m.totalEarned, 5000.0);
      expect(m.pairsProduced, 100);
      expect(m.active, isTrue);
    });

    test('parses KSA worker', () {
      final m = WorkerModel.fromJson({
        ...basePk,
        'type': 'ksa',
        'currency': 'SAR',
        'rate_per_pair': 10.0,
      }, 'w2');
      expect(m.type, 'ksa');
      expect(m.currency, 'SAR');
      expect(m.ratePerPair, 10.0);
    });

    test('defaults for empty json', () {
      final m = WorkerModel.fromJson({}, 'w3');
      expect(m.type, 'pk');
      expect(m.currency, 'PKR');
      expect(m.ratePerPair, 0.0);
      expect(m.active, isTrue);
    });

    test('handles integer rate', () {
      final m = WorkerModel.fromJson({...basePk, 'rate_per_pair': 50}, 'w4');
      expect(m.ratePerPair, 50.0);
    });
  });

  group('WorkerModel.toJson', () {
    test('round-trip preserves data', () {
      final original = WorkerModel.fromJson(basePk, 'w1');
      final restored = WorkerModel.fromJson(original.toJson(), 'w1');
      expect(restored.name, original.name);
      expect(restored.type, original.type);
      expect(restored.ratePerPair, original.ratePerPair);
    });
  });

  group('WorkerModel.copyWith', () {
    test('changes active status', () {
      final m = WorkerModel.fromJson(basePk, 'w1');
      final copy = m.copyWith(active: false);
      expect(copy.active, isFalse);
      expect(copy.name, m.name);
    });

    test('changes totalEarned and pairsProduced', () {
      final m = WorkerModel.fromJson(basePk, 'w1');
      final copy = m.copyWith(totalEarned: 6000.0, pairsProduced: 120);
      expect(copy.totalEarned, 6000.0);
      expect(copy.pairsProduced, 120);
    });
  });
}
