import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/collections.dart';
import '../core/utils/tenant_scope.dart';
import '../models/notification_model.dart';
import '../models/user_model.dart';
import 'auth_provider.dart';

enum NotificationStreamSource { notifications, shops }

class NotificationStreamFailure implements Exception {
  final NotificationStreamSource source;
  final Object cause;

  const NotificationStreamFailure({required this.source, required this.cause});
}

String? notificationTenantIdFor(UserModel? user) {
  if (user == null || !user.active || !user.canAccessNotifications) return null;
  final tenantId = TenantScope.normalize(user.tenantId);
  if (tenantId == null || tenantId == TenantScope.globalTenantId) return null;
  return tenantId;
}

@visibleForTesting
UserModel? notificationProfileForState(
  AsyncValue<UserModel?> profile, {
  required String? authenticatedUid,
}) {
  if (profile.hasError || authenticatedUid == null) return null;
  final user = profile.value;
  return user?.id == authenticatedUid ? user : null;
}

@visibleForTesting
Map<String, dynamic> notificationReadUpdate() => {
  'read': true,
  'read_at': FieldValue.serverTimestamp(),
};

final notificationTenantScopeProvider = Provider.autoDispose<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  if (authState.isLoading || authState.hasError) return null;
  final profile = ref.watch(authUserProvider);
  return notificationTenantIdFor(
    notificationProfileForState(
      profile,
      authenticatedUid: authState.value?.uid,
    ),
  );
});

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
AsyncValue<List<NotificationModel>> notificationsWithShopVisibility(
  List<NotificationModel> notifications,
  AsyncValue<Set<String>> activeShopIds,
) {
  if (activeShopIds.hasError) {
    return AsyncError<List<NotificationModel>>(
      NotificationStreamFailure(
        source: NotificationStreamSource.shops,
        cause: activeShopIds.error!,
      ),
      activeShopIds.stackTrace!,
    );
  }
  if (activeShopIds.isLoading && activeShopIds.hasValue) {
    final cachedShopIds = activeShopIds.value;
    if (cachedShopIds != null) {
      return AsyncData(
        filterVisibleNotifications(notifications, cachedShopIds),
      );
    }
  }
  return activeShopIds.whenData(
    (ids) => filterVisibleNotifications(notifications, ids),
  );
}

@visibleForTesting
AsyncValue<List<NotificationModel>> visibleNotificationState(
  AsyncValue<List<NotificationModel>> notifications,
  AsyncValue<Set<String>> activeShopIds,
) {
  if (notifications.hasError) {
    return AsyncError<List<NotificationModel>>(
      NotificationStreamFailure(
        source: NotificationStreamSource.notifications,
        cause: notifications.error!,
      ),
      notifications.stackTrace!,
    );
  }
  final currentNotifications = notifications.value;
  if (currentNotifications == null) {
    return const AsyncLoading<List<NotificationModel>>();
  }
  return notificationsWithShopVisibility(currentNotifications, activeShopIds);
}

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

/// Streams the 50 newest notifications for an authorized operational role,
/// scoped to the current concrete tenant. Unsupported or unresolved contexts
/// receive an empty value without starting a Firestore query.
final notificationsProvider = StreamProvider.autoDispose
    .family<List<NotificationModel>, String?>((ref, tenantId) {
      if (tenantId == null ||
          ref.watch(notificationTenantScopeProvider) != tenantId) {
        return Stream.value(const <NotificationModel>[]);
      }

      var query = FirebaseFirestore.instance.collection(
        Collections.notifications,
      ) as Query<Map<String, dynamic>>;

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
final activeNotificationShopIdsProvider = StreamProvider.autoDispose
    .family<Set<String>, String?>((ref, tenantId) {
      if (tenantId == null ||
          ref.watch(notificationTenantScopeProvider) != tenantId) {
        return Stream.value(const <String>{});
      }

      final encodedShopIds = ref.watch(
        notificationsProvider(tenantId).select(notificationShopIdsKey),
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
      final tenantId = ref.watch(notificationTenantScopeProvider);
      final notifications = ref.watch(notificationsProvider(tenantId));
      if (notifications.hasError) {
        return visibleNotificationState(
          notifications,
          const AsyncLoading<Set<String>>(),
        );
      }
      if (notifications.value == null) {
        return const AsyncLoading<List<NotificationModel>>();
      }
      final activeShopIds = ref.watch(
        activeNotificationShopIdsProvider(tenantId),
      );
      return visibleNotificationState(notifications, activeShopIds);
    });

/// Derived count of unread notifications for authorized operational roles.
final unreadNotificationCountProvider = Provider.autoDispose
    .family<int, String?>((ref, tenantId) {
      if (tenantId == null ||
          ref.watch(notificationTenantScopeProvider) != tenantId) {
        return 0;
      }
      final notifications = ref.watch(notificationsProvider(tenantId));
      if (notifications.value == null || notifications.hasError) return 0;
      final shopIds = ref.watch(activeNotificationShopIdsProvider(tenantId));
      return visibleNotificationState(
            notifications,
            shopIds,
          ).value?.where((notification) => !notification.read).length ??
          0;
    });

class NotificationNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> markAsRead(String notifId) async {
    if (notifId.trim().isEmpty) return;
    final user = await ref.read(authUserProvider.future);
    if (notificationTenantIdFor(user) == null) {
      throw StateError(
        user?.isSuperAdmin == true
            ? 'active platform super-admin access is required'
            : 'An active workspace is required for this operation',
      );
    }
    await FirebaseFirestore.instance
        .collection(Collections.notifications)
        .doc(notifId)
        .update(notificationReadUpdate());
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
    final user = await ref.read(authUserProvider.future);
    if (notificationTenantIdFor(user) == null) {
      throw StateError(
        user?.isSuperAdmin == true
            ? 'active platform super-admin access is required'
            : 'An active workspace is required for this operation',
      );
    }

    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    for (final id in unreadIds) {
      batch.update(db.collection(Collections.notifications).doc(id), {
        ...notificationReadUpdate(),
      });
    }
    await batch.commit();
  }
}

final notificationNotifierProvider =
    AsyncNotifierProvider<NotificationNotifier, void>(NotificationNotifier.new);
