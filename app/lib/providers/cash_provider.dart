import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../models/cash_transaction_model.dart';
import '../models/cash_approval_model.dart';

final cashTransactionsProvider =
    StreamProvider<List<CashTransactionModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.cashTransactions)
      .orderBy('created_at', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => CashTransactionModel.fromJson(d.data(), d.id))
          .toList());
});

final cashApprovalsProvider = StreamProvider<List<CashApprovalModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.cashApprovals)
      .where('status', isEqualTo: 'pending')
      .orderBy('created_at', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => CashApprovalModel.fromJson(d.data(), d.id))
          .toList());
});

class CashNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> addTransaction(
      Map<String, dynamic> data, String createdBy) async {
    state = const AsyncLoading();
    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      final now = Timestamp.now();

      final txRef = db.collection(Collections.cashTransactions).doc();
      batch.set(txRef, {
        ...data,
        'created_by': createdBy,
        'status': 'pending',
        'created_at': now,
        'updated_at': now,
      });

      final approvalRef = db.collection(Collections.cashApprovals).doc();
      batch.set(approvalRef, {
        'transaction_id': txRef.id,
        'amount': data['amount'],
        'type': data['type'],
        'reference': data['reference'] ?? '',
        'status': 'pending',
        'created_at': now,
        'updated_at': now,
      });

      await batch.commit();
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> approveCashApproval(String approvalId, String approvedBy) async {
    state = const AsyncLoading();
    try {
      await FirebaseFirestore.instance
          .collection(Collections.cashApprovals)
          .doc(approvalId)
          .update({
        'status': 'approved',
        'approved_by': approvedBy,
        'updated_at': Timestamp.now(),
      });
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> rejectCashApproval(
      String approvalId, String approvedBy, String notes) async {
    state = const AsyncLoading();
    try {
      await FirebaseFirestore.instance
          .collection(Collections.cashApprovals)
          .doc(approvalId)
          .update({
        'status': 'rejected',
        'approved_by': approvedBy,
        'notes': notes,
        'updated_at': Timestamp.now(),
      });
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final cashNotifierProvider =
    AsyncNotifierProvider<CashNotifier, void>(CashNotifier.new);
