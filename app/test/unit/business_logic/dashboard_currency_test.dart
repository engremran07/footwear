import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/route_model.dart';
import 'package:footwear_erp/models/shop_model.dart';
import 'package:footwear_erp/screens/dashboard_screen.dart';

void main() {
  test(
    'seller outstanding remains grouped by each assigned route currency',
    () {
      final now = Timestamp.fromMillisecondsSinceEpoch(0);
      final routes = [
        RouteModel(
          id: 'sar-route',
          routeNumber: 1,
          name: 'SAR Route',
          totalShops: 2,
          currency: 'SAR',
          active: true,
          createdBy: 'seller',
          createdAt: now,
          updatedAt: now,
        ),
        RouteModel(
          id: 'pkr-route',
          routeNumber: 2,
          name: 'PKR Route',
          totalShops: 1,
          currency: 'PKR',
          active: true,
          createdBy: 'seller',
          createdAt: now,
          updatedAt: now,
        ),
      ];
      final shops = [
        ShopModel(
          id: 'sar-shop-1',
          name: 'SAR Shop 1',
          routeId: 'sar-route',
          routeNumber: 1,
          balance: 100,
          active: true,
          createdBy: 'seller',
          createdAt: now,
          updatedAt: now,
        ),
        ShopModel(
          id: 'sar-shop-2',
          name: 'SAR Shop 2',
          routeId: 'sar-route',
          routeNumber: 1,
          balance: 50,
          active: true,
          createdBy: 'seller',
          createdAt: now,
          updatedAt: now,
        ),
        ShopModel(
          id: 'pkr-shop',
          name: 'PKR Shop',
          routeId: 'pkr-route',
          routeNumber: 2,
          balance: 2000,
          active: true,
          createdBy: 'seller',
          createdAt: now,
          updatedAt: now,
        ),
      ];

      expect(outstandingBalanceByCurrency(shops: shops, routes: routes), {
        'SAR': 150,
        'PKR': 2000,
      });
    },
  );
}
