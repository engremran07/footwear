import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../models/pnl_snapshot_model.dart';
import '../core/utils/formatters.dart';

final currentPnlProvider = StreamProvider<PnlSnapshotModel?>((ref) {
  final period = AppFormatters.currentPeriod();
  return FirebaseFirestore.instance
      .collection(Collections.pnlSnapshots)
      .doc(period)
      .snapshots()
      .map((doc) =>
          doc.exists ? PnlSnapshotModel.fromJson(doc.data()!, doc.id) : null);
});

final yearlyPnlProvider =
    StreamProvider.family<List<PnlSnapshotModel>, int>((ref, year) {
  final periods = List.generate(12, (i) {
    final month = (i + 1).toString().padLeft(2, '0');
    return '$year-$month';
  });

  return FirebaseFirestore.instance
      .collection(Collections.pnlSnapshots)
      .where(FieldPath.documentId, whereIn: periods)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => PnlSnapshotModel.fromJson(d.data(), d.id))
          .toList()
        ..sort((a, b) => a.period.compareTo(b.period)));
});
