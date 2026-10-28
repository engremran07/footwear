import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/notification_model.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/notification_provider.dart';

void main() {
  test(
    'workspace change never reuses prior tenant notification rows',
    () async {
      final profiles = StreamController<UserModel?>();
      final tenantAFeed = StreamController<List<NotificationModel>>();
      final tenantBFeed = StreamController<List<NotificationModel>>();
      final tenantAShops = StreamController<Set<String>>();
      final tenantBShops = StreamController<Set<String>>();
      final tenantBReady = Completer<void>();
      final now = Timestamp.now();
      UserModel user(String tenantId) => UserModel(
        id: 'admin-$tenantId',
        email: 'admin@example.com',
        displayName: 'Admin',
        role: UserRole.admin,
        tenantId: tenantId,
        active: true,
        createdAt: now,
        updatedAt: now,
      );
      final tenantANotification = NotificationModel(
        id: 'notification-a',
        type: 'transaction',
        shopId: 'shop-a',
        shopName: 'Tenant A shop',
        routeId: 'route-a',
        sellerId: 'seller-a',
        sellerName: 'Seller A',
        amount: 10,
        transactionType: 'cash_in',
        refId: 'transaction-a',
        targetRole: 'admin',
        createdBy: 'seller-a',
        createdAt: now,
      );
      final container = ProviderContainer(
        overrides: [
          authUserProvider.overrideWith((ref) => profiles.stream),
          notificationsProvider.overrideWith((ref, tenantId) {
            return switch (tenantId) {
              'tenant-a' => tenantAFeed.stream,
              'tenant-b' => tenantBFeed.stream,
              _ => Stream.value(const <NotificationModel>[]),
            };
          }),
          activeNotificationShopIdsProvider.overrideWith((ref, tenantId) {
            return switch (tenantId) {
              'tenant-a' => tenantAShops.stream,
              'tenant-b' => tenantBShops.stream,
              _ => Stream.value(const <String>{}),
            };
          }),
        ],
      );
      final subscription = container.listen(
        visibleNotificationsProvider,
        (_, _) {},
      );
      final scopeSubscription = container.listen(
        notificationTenantScopeProvider,
        (_, tenantId) {
          if (tenantId == 'tenant-b' && !tenantBReady.isCompleted) {
            tenantBReady.complete();
          }
        },
      );
      addTearDown(() {
        subscription.close();
        scopeSubscription.close();
        container.dispose();
        unawaited(profiles.close());
        unawaited(tenantAFeed.close());
        unawaited(tenantBFeed.close());
        unawaited(tenantAShops.close());
        unawaited(tenantBShops.close());
      });

      profiles.add(user('tenant-a'));
      await container.read(authUserProvider.future);
      expect(container.read(notificationTenantScopeProvider), 'tenant-a');
      tenantAFeed.add([tenantANotification]);
      tenantAShops.add({'shop-a'});
      await container.read(notificationsProvider('tenant-a').future);
      await container.read(
        activeNotificationShopIdsProvider('tenant-a').future,
      );
      expect(
        container.read(visibleNotificationsProvider).value?.single.shopName,
        'Tenant A shop',
      );

      profiles.add(user('tenant-b'));
      await tenantBReady.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);

      final afterWorkspaceSwitch = container.read(visibleNotificationsProvider);
      expect(afterWorkspaceSwitch.isLoading, isTrue);
      expect(afterWorkspaceSwitch.value, isNull);
    },
  );

  test(
    'unread badge count is tenant-keyed during workspace switches',
    () async {
      final profiles = StreamController<UserModel?>();
      final tenantAFeed = StreamController<List<NotificationModel>>();
      final tenantBFeed = StreamController<List<NotificationModel>>();
      final tenantAShops = StreamController<Set<String>>();
      final tenantBShops = StreamController<Set<String>>();
      final tenantBReady = Completer<void>();
      final now = Timestamp.now();
      UserModel user(String tenantId) => UserModel(
        id: 'admin-$tenantId',
        email: 'admin@example.com',
        displayName: 'Admin',
        role: UserRole.admin,
        tenantId: tenantId,
        active: true,
        createdAt: now,
        updatedAt: now,
      );
      final notification = NotificationModel(
        id: 'notification-a',
        type: 'transaction',
        shopId: 'shop-a',
        shopName: 'Tenant A shop',
        routeId: 'route-a',
        sellerId: 'seller-a',
        sellerName: 'Seller A',
        amount: 10,
        transactionType: 'cash_in',
        refId: 'transaction-a',
        targetRole: 'admin',
        createdBy: 'seller-a',
        createdAt: now,
      );
      final container = ProviderContainer(
        overrides: [
          authUserProvider.overrideWith((ref) => profiles.stream),
          notificationsProvider.overrideWith((ref, tenantId) {
            return switch (tenantId) {
              'tenant-a' => tenantAFeed.stream,
              'tenant-b' => tenantBFeed.stream,
              _ => Stream.value(const <NotificationModel>[]),
            };
          }),
          activeNotificationShopIdsProvider.overrideWith((ref, tenantId) {
            return switch (tenantId) {
              'tenant-a' => tenantAShops.stream,
              'tenant-b' => tenantBShops.stream,
              _ => Stream.value(const <String>{}),
            };
          }),
        ],
      );
      final scopeSubscription = container.listen(
        notificationTenantScopeProvider,
        (_, tenantId) {
          if (tenantId == 'tenant-b' && !tenantBReady.isCompleted) {
            tenantBReady.complete();
          }
        },
      );
      final tenantACountSubscription = container.listen(
        unreadNotificationCountProvider('tenant-a'),
        (_, _) {},
      );
      addTearDown(() {
        scopeSubscription.close();
        tenantACountSubscription.close();
        container.dispose();
        unawaited(profiles.close());
        unawaited(tenantAFeed.close());
        unawaited(tenantBFeed.close());
        unawaited(tenantAShops.close());
        unawaited(tenantBShops.close());
      });

      profiles.add(user('tenant-a'));
      await container.read(authUserProvider.future);
      tenantAFeed.add([notification]);
      tenantAShops.add({'shop-a'});
      await container.read(notificationsProvider('tenant-a').future);
      await container.read(
        activeNotificationShopIdsProvider('tenant-a').future,
      );
      expect(container.read(unreadNotificationCountProvider('tenant-a')), 1);

      profiles.add(user('tenant-b'));
      await tenantBReady.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(unreadNotificationCountProvider('tenant-b')), 0);
    },
  );

  test('shop listener key is stable when notification read state changes', () {
    NotificationModel notification(
      String id,
      String shopId, {
      bool read = false,
    }) => NotificationModel(
      id: id,
      type: 'transaction',
      shopId: shopId,
      shopName: shopId,
      routeId: 'route-1',
      sellerId: 'seller-1',
      sellerName: 'Seller',
      amount: 10,
      transactionType: 'cash_in',
      refId: id,
      targetRole: 'admin',
      read: read,
      createdBy: 'seller-1',
      createdAt: Timestamp.now(),
    );

    final unread = AsyncData([
      notification('newest', 'shop-2'),
      notification('older', 'shop-1'),
    ]);
    final read = AsyncData([
      notification('newest', 'shop-2', read: true),
      notification('older', 'shop-1', read: true),
    ]);

    expect(notificationShopIdsKey(unread), notificationShopIdsKey(read));
    expect(notificationShopIdsKey(unread), '["shop-1","shop-2"]');
  });

  test('hides inactive and soft-deleted shop documents', () {
    expect(isNotificationShopVisible({'active': true}), isTrue);
    expect(isNotificationShopVisible({'deleted': false}), isTrue);
    expect(isNotificationShopVisible({'active': false}), isFalse);
    expect(isNotificationShopVisible({'deleted': true}), isFalse);
  });

  test('notification access requires an active entitled workspace context', () {
    final now = DateTime.utc(2026, 10, 26);
    UserModel user({
      UserRole role = UserRole.admin,
      String? tenantId = 'tenant-1',
      bool active = true,
      String? workspaceId,
      String? supportReason,
      DateTime? selectedAt,
    }) => UserModel(
      id: 'user-1',
      email: 'user@example.com',
      displayName: 'User',
      role: role,
      tenantId: tenantId,
      activeWorkspaceId: workspaceId,
      activeWorkspaceReason: supportReason,
      activeWorkspaceSelectedAt: selectedAt == null
          ? null
          : Timestamp.fromDate(selectedAt),
      active: active,
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    );

    expect(notificationTenantIdFor(user(), now: now), 'tenant-1');
    expect(
      notificationTenantIdFor(user(tenantId: '__global__'), now: now),
      isNull,
    );
    expect(
      notificationTenantIdFor(user(role: UserRole.supervisor), now: now),
      'tenant-1',
    );
    expect(notificationTenantIdFor(user(tenantId: null), now: now), isNull);
    expect(notificationTenantIdFor(user(active: false), now: now), isNull);
    expect(
      notificationTenantIdFor(user(role: UserRole.seller), now: now),
      isNull,
    );
    expect(
      notificationTenantIdFor(
        user(
          role: UserRole.superAdmin,
          tenantId: null,
          workspaceId: 'tenant-1',
          supportReason: 'Investigating access',
          selectedAt: now.subtract(const Duration(hours: 1)),
        ),
        now: now,
      ),
      isNull,
    );
    expect(
      notificationTenantIdFor(
        user(
          role: UserRole.superAdmin,
          tenantId: null,
          workspaceId: 'tenant-1',
          supportReason: 'short',
          selectedAt: now,
        ),
        now: now,
      ),
      isNull,
    );
  });

  test(
    'profile-stream errors do not authorize a notification tenant',
    () async {
      final profileError = StateError('profile stream failed');
      final container = ProviderContainer(
        overrides: [
          authUserProvider.overrideWith(
            (ref) => Stream<UserModel?>.error(profileError),
          ),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        notificationTenantScopeProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      await expectLater(
        container.read(authUserProvider.future),
        throwsA(same(profileError)),
      );
      expect(container.read(notificationTenantScopeProvider), isNull);
    },
  );

  test('filters missing and inactive shops from notification visibility', () {
    NotificationModel notification(String id, String shopId) =>
        NotificationModel(
          id: id,
          type: 'transaction',
          shopId: shopId,
          shopName: shopId,
          routeId: 'route-1',
          sellerId: 'seller-1',
          sellerName: 'Seller',
          amount: 10,
          transactionType: 'cash_in',
          refId: id,
          targetRole: 'admin',
          createdBy: 'seller-1',
          createdAt: Timestamp.now(),
        );

    final visible = filterVisibleNotifications(
      [
        notification('active', 'shop-active'),
        notification('inactive', 'shop-inactive'),
        notification('missing', 'shop-missing'),
        notification('system', ''),
      ],
      const {'shop-active'},
    );

    expect(visible.map((item) => item.id), ['active', 'system']);
  });

  test('keeps cached visible rows while shop visibility refreshes', () {
    final notification = NotificationModel(
      id: 'notification-1',
      type: 'transaction',
      shopId: 'shop-1',
      shopName: 'Shop One',
      routeId: 'route-1',
      sellerId: 'seller-1',
      sellerName: 'Seller',
      amount: 10,
      transactionType: 'cash_in',
      refId: 'transaction-1',
      targetRole: 'admin',
      createdBy: 'seller-1',
      createdAt: Timestamp.now(),
    );
    // Construct the refresh state emitted internally by Riverpod.
    // ignore: invalid_use_of_internal_member
    final refreshing = const AsyncLoading<Set<String>>().copyWithPrevious(
      const AsyncData({'shop-1'}),
    );

    final visible = notificationsWithShopVisibility([notification], refreshing);

    expect(visible.value?.map((item) => item.id), ['notification-1']);
    expect(visible.isLoading, isFalse);
    expect(visible.hasError, isFalse);
  });

  test('keeps cached rows while the notification stream refreshes', () {
    final notification = NotificationModel(
      id: 'notification-1',
      type: 'transaction',
      shopId: 'shop-1',
      shopName: 'Shop One',
      routeId: 'route-1',
      sellerId: 'seller-1',
      sellerName: 'Seller',
      amount: 10,
      transactionType: 'cash_in',
      refId: 'transaction-1',
      targetRole: 'admin',
      createdBy: 'seller-1',
      createdAt: Timestamp.now(),
    );
    // Reproduce Riverpod's loading state while a stream dependency refreshes.
    final refreshing = const AsyncLoading<List<NotificationModel>>()
        // ignore: invalid_use_of_internal_member
        .copyWithPrevious(AsyncData([notification]));

    final visible = visibleNotificationState(
      refreshing,
      const AsyncData({'shop-1'}),
    );

    expect(visible.value?.map((item) => item.id), ['notification-1']);
    expect(visible.isLoading, isFalse);
    expect(visible.hasError, isFalse);
  });

  test('keeps cached visible rows while surfacing a feed stream error', () {
    final notification = NotificationModel(
      id: 'notification-1',
      type: 'transaction',
      shopId: 'shop-1',
      shopName: 'Shop One',
      routeId: 'route-1',
      sellerId: 'seller-1',
      sellerName: 'Seller',
      amount: 10,
      transactionType: 'cash_in',
      refId: 'transaction-1',
      targetRole: 'admin',
      createdBy: 'seller-1',
      createdAt: Timestamp.now(),
    );
    final permissionError = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );
    final failedFeed =
        AsyncError<List<NotificationModel>>(permissionError, StackTrace.current)
        // ignore: invalid_use_of_internal_member
        .copyWithPrevious(AsyncData([notification]));

    final visible = visibleNotificationState(
      failedFeed,
      const AsyncData({'shop-1'}),
    );

    expect(visible.hasError, isTrue);
    expect(visible.error, same(permissionError));
  });

  test('keeps cached visible rows while shop visibility emits an error', () {
    final notification = NotificationModel(
      id: 'notification-1',
      type: 'transaction',
      shopId: 'shop-1',
      shopName: 'Shop One',
      routeId: 'route-1',
      sellerId: 'seller-1',
      sellerName: 'Seller',
      amount: 10,
      transactionType: 'cash_in',
      refId: 'transaction-1',
      targetRole: 'admin',
      createdBy: 'seller-1',
      createdAt: Timestamp.now(),
    );
    final permissionError = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );
    final failedVisibility =
        AsyncError<Set<String>>(permissionError, StackTrace.current)
        // ignore: invalid_use_of_internal_member
        .copyWithPrevious(const AsyncData({'shop-1'}));

    final visible = notificationsWithShopVisibility([
      notification,
    ], failedVisibility);

    expect(visible.hasError, isTrue);
    expect(visible.error, same(permissionError));
  });

  test(
    'keeps first visibility load loading and surfaces visibility errors',
    () {
      const firstLoad = AsyncLoading<Set<String>>();
      final permissionError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      final failed = AsyncError<Set<String>>(
        permissionError,
        StackTrace.current,
      );

      expect(
        notificationsWithShopVisibility(const [], firstLoad).isLoading,
        isTrue,
      );
      final visibleError = notificationsWithShopVisibility(const [], failed);
      expect(visibleError.hasError, isTrue);
      expect(visibleError.error, same(permissionError));
    },
  );
}
