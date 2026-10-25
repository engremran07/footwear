import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/collections.dart';
import '../core/utils/tenant_scope.dart';
import '../models/notification_model.dart';
import 'auth_provider.dart';

@visibleForTesting
List<NotificationModel> filterVisibleNotifications(
  Iterable<NotificationModel> notifications,
  Set<String> activeShopIds,
) => notifications
    .where((notification) {
      final shopId = notification.shopId.trim();
      return shopId.isEmpty || activeShopIds.contains(shopId);
    })
    .toList(growable: false);

@visibleForTesting
bool isNotificationShopVisible(Map<String, dynamic> shopData) =>
    shopData['active'] != false && shopData['deleted'] != true;

@visibleForTesting
String notificationShopIdsKey(AsyncValue<List<NotificationModel>> state) {
  final shopIds =
      state.value
          ?.map((notification) => notification.shopId.trim())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList()
        ?..sort();
  return jsonEncode(shopIds ?? const <String>[]);
}

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
      final (isAdmin, tenantId) = ref.watch(
        authUserProvider.select(
          (state) => (state.value?.isAdmin ?? false, state.value?.tenantId),
        ),
      );
      if (!isAdmin) return const Stream.empty();

      var query =
          FirebaseFirestore.instance.collection(Collections.notifications)
              as Query<Map<String, dynamic>>;

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

/// Watches only the shops referenced by the bounded notification feed. Missing,
/// inactive, and soft-deleted shops are excluded without treating a capped
/// all-shops query as an existence check.
final activeNotificationShopIdsProvider =
    StreamProvider.autoDispose<Set<String>>((ref) {
      final (isAdmin, tenantId) = ref.watch(
        authUserProvider.select(
          (state) => (state.value?.isAdmin ?? false, state.value?.tenantId),
        ),
      );
      if (!isAdmin) return Stream.value(const <String>{});

      final encodedShopIds = ref.watch(
        notificationsProvider.select(notificationShopIdsKey),
      );
      final shopIds = (jsonDecode(encodedShopIds) as List<dynamic>)
          .cast<String>();
      if (shopIds.isEmpty) return Stream.value(const <String>{});

      final query = TenantScope.applyToQuery(
        FirebaseFirestore.instance.collection(Collections.shops),
        tenantId: tenantId,
      );
      final chunks = <List<String>>[
        for (var start = 0; start < shopIds.length; start += 30)
          shopIds.sublist(start, (start + 30).clamp(0, shopIds.length)),
      ];

      return Stream<Set<String>>.multi((controller) {
        final latest = List<Set<String>?>.filled(chunks.length, null);
        final subscriptions =
            <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

        void emitWhenReady(
          int chunkIndex,
          QuerySnapshot<Map<String, dynamic>> snapshot,
        ) {
          latest[chunkIndex] = {
            for (final document in snapshot.docs)
              if (isNotificationShopVisible(document.data())) document.id,
          };
          if (latest.every((ids) => ids != null)) {
            controller.add({for (final ids in latest) ...?ids});
          }
        }

        for (final (index, chunk) in chunks.indexed) {
          subscriptions.add(
            query
                .where(FieldPath.documentId, whereIn: chunk)
                .snapshots()
                .listen(
                  (snapshot) => emitWhenReady(index, snapshot),
                  onError: controller.addError,
                ),
          );
        }

        controller.onCancel = () async {
          await Future.wait(
            subscriptions.map((subscription) => subscription.cancel()),
          );
        };
      });
    });

/// The center, unread badge, and bulk-read action all consume this same
/// role- and tenant-scoped visible notification set.
final visibleNotificationsProvider =
    Provider.autoDispose<AsyncValue<List<NotificationModel>>>((ref) {
      final notifications = ref.watch(notificationsProvider);
      return notifications.when(
        data: (items) {
          final activeShopIds = ref.watch(activeNotificationShopIdsProvider);
          return activeShopIds.whenData(
            (ids) => filterVisibleNotifications(items, ids),
          );
        },
        loading: () => const AsyncLoading<List<NotificationModel>>(),
        error: (error, stackTrace) =>
            AsyncError<List<NotificationModel>>(error, stackTrace),
      );
    });

/// Derived count of unread notifications (admin only).
final unreadNotificationCountProvider = Provider.autoDispose<int>((ref) {
  return ref
          .watch(visibleNotificationsProvider)
          .value
          ?.where((notification) => !notification.read)
          .length ??
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

  Future<void> markAllAsRead(Set<String> visibleNotificationIds) async {
    final unreadIds = visibleNotificationIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (unreadIds.isEmpty) return;
    if (unreadIds.length > 50) {
      throw ArgumentError('At most 50 notifications can be marked at once.');
    }

    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    for (final id in unreadIds) {
      batch.update(db.collection(Collections.notifications).doc(id), {
        'read': true,
        'read_at': Timestamp.now(),
      });
    }
    await batch.commit();
  }
}

final notificationNotifierProvider =
    AsyncNotifierProvider<NotificationNotifier, void>(NotificationNotifier.new);
