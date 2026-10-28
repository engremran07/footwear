import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:footwear_erp/models/notification_model.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/notification_provider.dart';
import 'package:footwear_erp/screens/notification_center_screen.dart';
import 'package:footwear_erp/widgets/shimmer_loading.dart';

void main() {
  testWidgets('missing profile is actionable and does not start the feed', (
    tester,
  ) async {
    var notificationSubscriptions = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(null)),
          notificationsProvider.overrideWith((ref, tenantId) {
            notificationSubscriptions++;
            return const Stream.empty();
          }),
        ],
        child: const MaterialApp(home: NotificationCenterScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Your account is not assigned to a workspace. Contact your administrator.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(ShimmerLoading), findsNothing);
    expect(notificationSubscriptions, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'profile-stream failures show retry feedback without starting a feed query',
    (tester) async {
      var notificationSubscriptions = 0;
      final profileError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith(
              (ref) => Stream<UserModel?>.error(profileError),
            ),
            notificationsProvider.overrideWith((ref, tenantId) {
              notificationSubscriptions++;
              return const Stream.empty();
            }),
          ],
          child: const MaterialApp(home: NotificationCenterScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('You do not have permission to perform this action.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(ShimmerLoading), findsNothing);
      expect(notificationSubscriptions, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('feed permission failures show mapped retry feedback', (
    tester,
  ) async {
    final user = UserModel(
      id: 'admin-1',
      email: 'admin@example.com',
      displayName: 'Admin',
      role: UserRole.admin,
      tenantId: 'tenant-1',
      active: true,
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    );
    final feedError = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );
    var shopVisibilitySubscriptions = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(user)),
          notificationsProvider.overrideWith(
            (ref, tenantId) => Stream<List<NotificationModel>>.error(feedError),
          ),
          activeNotificationShopIdsProvider.overrideWith((ref, tenantId) {
            shopVisibilitySubscriptions++;
            return const Stream.empty();
          }),
        ],
        child: const MaterialApp(home: NotificationCenterScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('You do not have permission to perform this action.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(shopVisibilitySubscriptions, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps cached notifications visible after a feed error', (
    tester,
  ) async {
    final user = UserModel(
      id: 'admin-1',
      email: 'admin@example.com',
      displayName: 'Admin',
      role: UserRole.admin,
      tenantId: 'tenant-1',
      active: true,
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    );
    final feed = StreamController<List<NotificationModel>>();
    final shops = StreamController<Set<String>>();
    addTearDown(() async {
      await feed.close();
      await shops.close();
    });
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(user)),
          notificationsProvider.overrideWith((ref, tenantId) => feed.stream),
          activeNotificationShopIdsProvider.overrideWith(
            (ref, tenantId) => shops.stream,
          ),
        ],
        child: const MaterialApp(home: NotificationCenterScreen()),
      ),
    );
    await tester.pump();
    feed.add([notification]);
    shops.add({'shop-1'});
    await tester.pumpAndSettle();
    expect(find.text('Shop One'), findsOneWidget);
    final providerContainer = ProviderScope.containerOf(
      tester.element(find.byType(NotificationCenterScreen)),
    );

    feed.addError(
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Shop One'), findsOneWidget);
    expect(find.byKey(const Key('notification_feed_error')), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(
      providerContainer.read(visibleNotificationsProvider).hasError,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps cached notifications visible after shop lookup error', (
    tester,
  ) async {
    final user = UserModel(
      id: 'admin-1',
      email: 'admin@example.com',
      displayName: 'Admin',
      role: UserRole.admin,
      tenantId: 'tenant-1',
      active: true,
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    );
    final feed = StreamController<List<NotificationModel>>();
    final shops = StreamController<Set<String>>();
    addTearDown(() async {
      await feed.close();
      await shops.close();
    });
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(user)),
          notificationsProvider.overrideWith((ref, tenantId) => feed.stream),
          activeNotificationShopIdsProvider.overrideWith(
            (ref, tenantId) => shops.stream,
          ),
        ],
        child: const MaterialApp(home: NotificationCenterScreen()),
      ),
    );
    await tester.pump();
    feed.add([notification]);
    shops.add({'shop-1'});
    await tester.pumpAndSettle();
    expect(find.text('Shop One'), findsOneWidget);
    final providerContainer = ProviderScope.containerOf(
      tester.element(find.byType(NotificationCenterScreen)),
    );

    shops.addError(
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Shop One'), findsOneWidget);
    expect(
      providerContainer
          .read(activeNotificationShopIdsProvider('tenant-1'))
          .hasError,
      isTrue,
    );
    final feedState = providerContainer.read(notificationsProvider('tenant-1'));
    final visibleState = providerContainer.read(visibleNotificationsProvider);
    expect(feedState.hasValue, isTrue, reason: '$feedState');
    expect(
      visibleState.hasError,
      isTrue,
      reason: 'feed=$feedState, visible=$visibleState',
    );
    expect(find.byKey(const Key('notification_feed_error')), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'super-admin without support context gets guidance, not a query',
    (tester) async {
      var notificationSubscriptions = 0;
      final user = UserModel(
        id: 'platform-admin',
        email: 'platform@example.com',
        displayName: 'Platform Admin',
        role: UserRole.superAdmin,
        active: true,
        createdAt: Timestamp.now(),
        updatedAt: Timestamp.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith((ref) => Stream.value(user)),
            notificationsProvider.overrideWith((ref, tenantId) {
              notificationSubscriptions++;
              return const Stream.empty();
            }),
          ],
          child: const MaterialApp(home: NotificationCenterScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Access Denied'), findsOneWidget);
      expect(notificationSubscriptions, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shows mark-as-read permission failures instead of ignoring them',
    (tester) async {
      final user = UserModel(
        id: 'admin-1',
        email: 'admin@example.com',
        displayName: 'Admin',
        role: UserRole.admin,
        tenantId: 'tenant-1',
        active: true,
        createdAt: Timestamp.now(),
        updatedAt: Timestamp.now(),
      );
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
      final router = GoRouter(
        initialLocation: '/notifications',
        routes: [
          GoRoute(
            path: '/notifications',
            builder: (_, _) => const NotificationCenterScreen(),
          ),
          GoRoute(
            path: '/shops/:id',
            builder: (_, _) => const Scaffold(body: Text('Shop details')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith((ref) => Stream.value(user)),
            notificationsProvider.overrideWith(
              (ref, tenantId) => Stream.value([notification]),
            ),
            activeNotificationShopIdsProvider.overrideWith(
              (ref, tenantId) => Stream.value({'shop-1'}),
            ),
            notificationNotifierProvider.overrideWith(
              _PermissionDeniedNotificationNotifier.new,
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Shop One'));
      await tester.pumpAndSettle();

      expect(
        find.text('You do not have permission to perform this action.'),
        findsOneWidget,
      );
      expect(find.text('Shop details'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mark all read shows progress and mapped failure feedback', (
    tester,
  ) async {
    final notifier = _DelayedNotificationNotifier();
    final user = UserModel(
      id: 'admin-1',
      email: 'admin@example.com',
      displayName: 'Admin',
      role: UserRole.admin,
      tenantId: 'tenant-1',
      active: true,
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    );
    final notification = NotificationModel(
      id: 'notification-1',
      type: 'transaction',
      shopId: 'shop-1',
      shopName: 'Shop',
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
    final deletedShopNotification = notification.copyWith(
      id: 'notification-deleted-shop',
      shopId: 'shop-deleted',
      shopName: 'Deleted shop',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(user)),
          notificationsProvider.overrideWith(
            (ref, tenantId) =>
                Stream.value([notification, deletedShopNotification]),
          ),
          activeNotificationShopIdsProvider.overrideWith(
            (ref, tenantId) => Stream.value({'shop-1'}),
          ),
          notificationNotifierProvider.overrideWith(() => notifier),
        ],
        child: const MaterialApp(home: NotificationCenterScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Deleted shop'), findsNothing);
    expect(find.text('1'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.mark_email_read));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    notifier.completer.completeError(
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
    );
    await tester.pumpAndSettle();

    expect(notifier.notificationIds, {'notification-1'});
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.error_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _PermissionDeniedNotificationNotifier extends NotificationNotifier {
  @override
  Future<void> build() async {}

  @override
  Future<void> markAsRead(String notifId) => Future<void>.error(
    FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
  );
}

class _DelayedNotificationNotifier extends NotificationNotifier {
  final Completer<void> completer = Completer<void>();
  Set<String> notificationIds = const {};

  @override
  Future<void> build() async {}

  @override
  Future<void> markAllAsRead(Set<String> visibleNotificationIds) {
    notificationIds = visibleNotificationIds;
    return completer.future;
  }
}
