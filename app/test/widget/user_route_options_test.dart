import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/route_model.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/route_provider.dart';
import 'package:footwear_erp/providers/tenant_provider.dart';
import 'package:footwear_erp/screens/users_list_screen.dart';

void main() {
  testWidgets(
    'seller route assignment in user dialog can retry route loading',
    (tester) async {
      var routeAttempts = 0;
      final now = Timestamp.now();
      final admin = UserModel(
        id: 'admin-1',
        email: 'admin@example.com',
        displayName: 'Admin',
        role: UserRole.tenantAdmin,
        tenantId: 'tenant-1',
        active: true,
        createdAt: now,
        updatedAt: now,
      );
      final route = RouteModel(
        id: 'route-1',
        routeNumber: 1,
        name: 'Route One',
        totalShops: 0,
        active: true,
        createdBy: admin.id,
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(
              (ref) => Stream.value(_TestFirebaseUser(admin.id)),
            ),
            authUserProvider.overrideWith((ref) => Stream.value(admin)),
            tenantUsersProvider(
              'tenant-1',
            ).overrideWith((ref) => Stream.value(<UserModel>[])),
            routesProvider.overrideWith((ref) {
              routeAttempts += 1;
              return routeAttempts == 1
                  ? Stream.error(StateError('routes unavailable'))
                  : Stream.value([route]);
            }),
          ],
          child: const MaterialApp(home: UsersListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(
        find.text('Something went wrong. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(routeAttempts, greaterThan(1));
      expect(find.text('Route One'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _TestFirebaseUser implements User {
  @override
  final String uid;

  _TestFirebaseUser(this.uid);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
