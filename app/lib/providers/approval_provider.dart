import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/collections.dart';
import '../models/cash_approval_model.dart';
import '../models/expense_approval_model.dart';

final pendingCashApprovalsCountProvider = StreamProvider<int>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.cashApprovals)
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map((snap) => snap.docs.length);
});

final pendingExpenseApprovalsCountProvider = StreamProvider<int>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.expenseApprovals)
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map((snap) => snap.docs.length);
});

final pendingApprovalsCountProvider = Provider<int>((ref) {
  final cash = ref.watch(pendingCashApprovalsCountProvider).valueOrNull ?? 0;
  final expense =
      ref.watch(pendingExpenseApprovalsCountProvider).valueOrNull ?? 0;
  return cash + expense;
});

final allPendingCashApprovalsProvider =
    StreamProvider<List<CashApprovalModel>>((ref) {
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

final allPendingExpenseApprovalsProvider =
    StreamProvider<List<ExpenseApprovalModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.expenseApprovals)
      .where('status', isEqualTo: 'pending')
      .orderBy('created_at', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => ExpenseApprovalModel.fromJson(d.data(), d.id))
          .toList());
});
