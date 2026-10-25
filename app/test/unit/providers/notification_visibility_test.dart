import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/notification_model.dart';
import 'package:footwear_erp/providers/notification_provider.dart';

void main() {
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
}
