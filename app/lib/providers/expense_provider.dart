import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../models/expense_model.dart';
import '../models/expense_approval_model.dart';

final expensesProvider = StreamProvider<List<ExpenseModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.expenses)
      .orderBy('created_at', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => ExpenseModel.fromJson(d.data(), d.id)).toList());
});

final expenseDetailProvider =
    StreamProvider.family<ExpenseModel?, String>((ref, id) {
  return FirebaseFirestore.instance
      .collection(Collections.expenses)
      .doc(id)
      .snapshots()
      .map((doc) =>
          doc.exists ? ExpenseModel.fromJson(doc.data()!, doc.id) : null);
});

final expenseApprovalsProvider =
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

class ExpenseNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<String> uploadReceipt(String fileId, Uint8List bytes) async {
    state = const AsyncLoading();
    try {
      final ref = FirebaseStorage.instance.ref('receipts/$fileId.jpg');
      await ref.putData(bytes);
      final url = await ref.getDownloadURL();
      state = const AsyncData(null);
      return url;
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> create(Map<String, dynamic> data, String createdBy) async {
    state = const AsyncLoading();
    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      final now = Timestamp.now();

      final expenseRef = db.collection(Collections.expenses).doc();
      batch.set(expenseRef, {
        ...data,
        'status': 'pending_approval',
        'created_by': createdBy,
        'created_at': now,
        'updated_at': now,
      });

      final approvalRef = db.collection(Collections.expenseApprovals).doc();
      batch.set(approvalRef, {
        'expense_id': expenseRef.id,
        'amount': data['amount'],
        'category': data['category'],
        'description': data['description'] ?? '',
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

  Future<void> approveExpenseApproval(
      String approvalId, String approvedBy) async {
    state = const AsyncLoading();
    try {
      await FirebaseFirestore.instance
          .collection(Collections.expenseApprovals)
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

  Future<void> rejectExpenseApproval(
      String approvalId, String rejectedBy, String notes) async {
    state = const AsyncLoading();
    try {
      await FirebaseFirestore.instance
          .collection(Collections.expenseApprovals)
          .doc(approvalId)
          .update({
        'status': 'rejected',
        'approved_by': rejectedBy,
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

final expenseNotifierProvider =
    AsyncNotifierProvider<ExpenseNotifier, void>(ExpenseNotifier.new);
