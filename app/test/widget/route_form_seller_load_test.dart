import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/route_model.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/route_provider.dart';
import 'package:footwear_erp/providers/user_provider.dart';
import 'package:footwear_erp/screens/route_form_screen.dart';
import 'package:footwear_erp/widgets/error_state.dart';

void main() {
  testWidgets(
    'route form waits for the active profile before showing access errors',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith((ref) => const Stream.empty()),
          ],
          child: const MaterialApp(home: RouteFormScreen()),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Access Denied'), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
    },
  );

  testWidgets('route edit waits for the existing route before showing fields', (
    tester,
  ) async {
    final admin = _admin();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(admin)),
          routeDetailProvider(
            'route-1',
          ).overrideWith((ref) => const Stream.empty()),
        ],
        child: const MaterialApp(home: RouteFormScreen(routeId: 'route-1')),
      ),
    );
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('route edit exposes retry and loads the record after failure', (
    tester,
  ) async {
    var loadAttempts = 0;
    final route = _route();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(_admin())),
          sellersProvider.overrideWith((ref) => Stream.value([_seller()])),
          routeDetailProvider('route-1').overrideWith((ref) {
            loadAttempts += 1;
            return loadAttempts == 1
                ? Stream.error(StateError('route unavailable'))
                : Stream.value(route);
          }),
        ],
        child: const MaterialApp(home: RouteFormScreen(routeId: 'route-1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Save'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(loadAttempts, greaterThan(1));
    expect(find.byType(ErrorState), findsNothing);
    expect(find.byType(TextFormField), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      'Existing route',
    );
    expect(tester.widget<FilterChip>(find.byType(FilterChip)).selected, isTrue);
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .initialValue,
      'PKR',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing route data is not presented as an editable default', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(_admin())),
          routeDetailProvider(
            'route-1',
          ).overrideWith((ref) => Stream.value(null)),
        ],
        child: const MaterialApp(home: RouteFormScreen(routeId: 'route-1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Save'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('seller load failures are visible and retryable', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(_admin())),
          sellersProvider.overrideWith(
            (ref) => Stream.error(StateError('seller list unavailable')),
          ),
        ],
        child: const MaterialApp(home: RouteFormScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('No sellers available.'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

UserModel _admin() {
  final now = Timestamp.now();
  return UserModel(
    id: 'admin-1',
    email: 'admin@example.com',
    displayName: 'Admin',
    role: UserRole.tenantAdmin,
    tenantId: 'tenant-1',
    active: true,
    createdAt: now,
    updatedAt: now,
  );
}

UserModel _seller() {
  final now = Timestamp.now();
  return UserModel(
    id: 'seller-1',
    email: 'seller@example.com',
    displayName: 'Seller One',
    role: UserRole.seller,
    tenantId: 'tenant-1',
    active: true,
    createdAt: now,
    updatedAt: now,
  );
}

RouteModel _route() {
  final now = Timestamp.now();
  return RouteModel(
    id: 'route-1',
    routeNumber: 1,
    name: 'Existing route',
    totalShops: 0,
    assignedSellerIds: const ['seller-1'],
    assignedSellerNames: const ['Seller One'],
    currency: 'PKR',
    active: true,
    createdBy: 'admin-1',
    createdAt: now,
    updatedAt: now,
  );
}
