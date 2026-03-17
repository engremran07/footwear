import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import 'approval_provider.dart';

/// A single in-app notification item derived from recent Firestore activity.
class AppNotification {
  final String id;
  final String title;
  final String subtitle;
  final String route;
  final Timestamp createdAt;

  const AppNotification({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.route,
    required this.createdAt,
  });
}

/// Streams the latest 20 activity items from pending approvals + recent orders.
final appNotificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final db = FirebaseFirestore.instance;

  // Stream 1: pending cash approvals
  final cashStream = db
      .collection(Collections.cashApprovals)
      .where('status', isEqualTo: 'pending')
      .orderBy('created_at', descending: true)
      .limit(10)
      .snapshots()
      .map((snap) => snap.docs.map((d) {
            final data = d.data();
            return AppNotification(
              id: 'cash_${d.id}',
              title: 'Cash approval pending',
              subtitle:
                  '${data['type'] ?? 'cash'} — ${data['amount'] ?? 0} ${data['reference'] ?? ''}',
              route: '/approvals',
              createdAt: data['created_at'] as Timestamp? ?? Timestamp.now(),
            );
          }).toList());

  // Combine cash approvals stream with expense approvals + recent orders
  return cashStream.asyncMap((cashList) async {
    final expSnap = await db
        .collection(Collections.expenseApprovals)
        .where('status', isEqualTo: 'pending')
        .orderBy('created_at', descending: true)
        .limit(10)
        .get();
    final orderSnap = await db
        .collection(Collections.orders)
        .orderBy('created_at', descending: true)
        .limit(10)
        .get();

    final expenseList = expSnap.docs.map((d) {
      final data = d.data();
      return AppNotification(
        id: 'exp_${d.id}',
        title: 'Expense approval pending',
        subtitle: '${data['category'] ?? ''} — ${data['amount'] ?? 0}',
        route: '/approvals',
        createdAt: data['created_at'] as Timestamp? ?? Timestamp.now(),
      );
    }).toList();

    final orderList = orderSnap.docs.map((d) {
      final data = d.data();
      return AppNotification(
        id: 'order_${d.id}',
        title: 'Order: ${data['customer_name'] ?? ''}',
        subtitle: '${data['status'] ?? 'pending'} — ${data['total'] ?? 0}',
        route: '/orders/${d.id}',
        createdAt: data['created_at'] as Timestamp? ?? Timestamp.now(),
      );
    }).toList();

    final all = [...cashList, ...expenseList, ...orderList];
    all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return all.take(20).toList();
  });
});

/// Badge count: pending cash + expense approvals (reactive composition).
final notificationBadgeCountProvider = Provider<int>((ref) {
  final cash = ref.watch(pendingCashApprovalsCountProvider).valueOrNull ?? 0;
  final expense =
      ref.watch(pendingExpenseApprovalsCountProvider).valueOrNull ?? 0;
  return cash + expense;
});
