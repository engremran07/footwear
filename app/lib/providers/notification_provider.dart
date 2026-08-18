import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/collections.dart';
import '../core/utils/tenant_scope.dart';
import '../models/notification_model.dart';
import 'auth_provider.dart';

/// Admin-only stream of the 50 most-recent notifications ordered newest-first,
/// scoped to the current user's tenant.
///
/// Returns [Stream.empty] for non-admin users so the provider never fires a
/// Firestore query that would fail with permission-denied.
/// 
/// P1-10 FIX: Added TenantScope.applyToQuery() to prevent admins from one
/// workspace seeing notifications from other workspaces.
final notificationsProvider =
    StreamProvider.autoDispose<List<NotificationModel>>((ref) {
      final authState = ref.watch(authUserProvider);
      final isAdmin = authState.value?.isAdmin ?? false;
      if (!isAdmin) return const Stream.empty();

      final tenantId = authState.value?.tenantId;

      var query = FirebaseFirestore.instance
          .collection(Collections.notifications) as Query<Map<String, dynamic>>;

      // P1-10 FIX: Apply tenant scoping to prevent cross-tenant leakage
      query = TenantScope.applyToQuery(query, tenantId: tenantId);

      return query
          .where('target_role', isEqualTo: 'admin')
          .orderBy('created_at', descending: true)
          .limit(50)
          .snapshots()
          .map(
            (snap) => snap.docs
                .map((d) => NotificationModel.fromJson(d.data(), d.id))
                .toList(),
          );
    });

/// Derived count of unread notifications (admin only).
final unreadNotificationCountProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(notificationsProvider).value?.where((n) => !n.read).length ??
      0;
});

class NotificationNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> markAsRead(String notifId) async {
    if (notifId.trim().isEmpty) return;
    await FirebaseFirestore.instance
        .collection(Collections.notifications)
        .doc(notifId)
        .update({'read': true, 'read_at': Timestamp.now()});
  }

  Future<void> markAllAsRead() async {
    final notifications = ref.read(notificationsProvider).value ?? [];
    final unread = notifications.where((n) => !n.read).toList();
    if (unread.isEmpty) return;

    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    for (final n in unread) {
      batch.update(db.collection(Collections.notifications).doc(n.id), {
        'read': true,
        'read_at': Timestamp.now(),
      });
    }
    await batch.commit();
  }
}

final notificationNotifierProvider =
    AsyncNotifierProvider<NotificationNotifier, void>(NotificationNotifier.new);
