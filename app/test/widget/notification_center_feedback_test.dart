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

void main() {
  testWidgets('super-admin without support context gets guidance, not a query', (
    tester,
  ) async {
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

    expect(
      find.text(
        'Select a workspace and provide a support reason before accessing its business data.',
      ),
      findsOneWidget,
    );
    expect(notificationSubscriptions, 0);
    expect(tester.takeException(), isNull);
  });

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
