import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/pnl_snapshot_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);
  final base = <String, dynamic>{
    'period': '2024-01',
    'revenue': 50000.0,
    'cogs': 20000.0,
    'gross_profit': 30000.0,
    'expenses': 5000.0,
    'worker_cost': 3000.0,
    'net_profit': 22000.0,
    'updated_at': ts,
  };

  group('PnlSnapshotModel.fromJson', () {
    test('parses all P&L fields', () {
      final m = PnlSnapshotModel.fromJson(base, '2024-01');
      expect(m.id, '2024-01');
      expect(m.period, '2024-01');
      expect(m.revenue, 50000.0);
      expect(m.cogs, 20000.0);
      expect(m.grossProfit, 30000.0);
      expect(m.expenses, 5000.0);
      expect(m.workerCost, 3000.0);
      expect(m.netProfit, 22000.0);
    });

    test('defaults period to docId when missing', () {
      final m = PnlSnapshotModel.fromJson({'updated_at': ts}, '2024-02');
      expect(m.period, '2024-02');
    });

    test('defaults zeroes for missing numeric fields', () {
      final m = PnlSnapshotModel.fromJson({}, '2024-03');
      expect(m.revenue, 0.0);
      expect(m.netProfit, 0.0);
    });

    test('handles integer values', () {
      final m = PnlSnapshotModel.fromJson({...base, 'revenue': 50000, 'cogs': 20000}, '2024-01');
      expect(m.revenue, 50000.0);
      expect(m.cogs, 20000.0);
    });
  });

  group('PnlSnapshotModel.toJson', () {
    test('toJson returns empty map (read-only, never written by Flutter)', () {
      final m = PnlSnapshotModel.fromJson(base, '2024-01');
      expect(m.toJson(), isEmpty);
    });
  });

  group('PnlSnapshotModel.copyWith', () {
    test('changes revenue', () {
      final m = PnlSnapshotModel.fromJson(base, '2024-01');
      final copy = m.copyWith(revenue: 60000.0);
      expect(copy.revenue, 60000.0);
      expect(copy.cogs, m.cogs);
    });
  });
}
