import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/notification_model.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/notification_provider.dart';
import 'package:footwear_erp/screens/notification_center_screen.dart';

void main() {
  testWidgets('mark all read shows progress and mapped failure feedback', (
    tester,
  ) async {
    final notifier = _DelayedNotificationNotifier();
    final user = UserModel(
      id: 'admin-1',
      email: 'admin@example.com',
      displayName: 'Admin',
      role: UserRole.admin,
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
            (ref) => Stream.value([notification, deletedShopNotification]),
          ),
          activeNotificationShopIdsProvider.overrideWith(
            (ref) => Stream.value({'shop-1'}),
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
