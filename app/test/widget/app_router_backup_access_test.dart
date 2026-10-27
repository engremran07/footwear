import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:footwear_erp/core/constants/app_brand.dart';
import 'package:footwear_erp/core/models/tenant_model.dart';
import 'package:footwear_erp/core/router/app_router.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/database_backup_provider.dart';
import 'package:footwear_erp/providers/network_provider.dart';
import 'package:footwear_erp/providers/notification_provider.dart';
import 'package:footwear_erp/providers/tenant_provider.dart';
import 'package:footwear_erp/screens/database_backup_screen.dart';
import 'package:footwear_erp/screens/notification_center_screen.dart';
import 'package:footwear_erp/screens/route_form_screen.dart';
import 'package:footwear_erp/screens/shop_form_screen.dart';
import 'package:footwear_erp/widgets/app_shell.dart';

void main() {
  testWidgets('router page transitions are disabled for reduced motion', (
    tester,
  ) async {
    await _pumpBackupRoute(
      tester,
      routeIds: const ['route-1'],
      disableAnimations: true,
    );

    expect(
      find.ancestor(
        of: find.byType(DatabaseBackupScreen),
        matching: find.byType(ScaleTransition),
      ),
      findsNothing,
    );
  });

  testWidgets('router page transitions remain enabled when motion is allowed', (
    tester,
  ) async {
    await _pumpBackupRoute(
      tester,
      routeIds: const ['route-1'],
      disableAnimations: false,
    );

    expect(
      find.ancestor(
        of: find.byType(DatabaseBackupScreen),
        matching: find.byType(ScaleTransition),
      ),
      findsOneWidget,
    );
  });

  testWidgets('router form transitions are disabled for reduced motion', (
    tester,
  ) async {
    await _pumpBackupRoute(
      tester,
      routeIds: const ['route-1'],
      disableAnimations: true,
      location: '/shops/new',
      onTransitionFrame: (tester) {
        expect(
          find.ancestor(
            of: find.byType(ShopFormScreen),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is SlideTransition && widget.position.value.dy != 0,
            ),
          ),
          findsNothing,
        );
      },
    );
  });

  testWidgets('router form transitions remain enabled when motion is allowed', (
    tester,
  ) async {
    await _pumpBackupRoute(
      tester,
      routeIds: const ['route-1'],
      disableAnimations: false,
      location: '/shops/new',
      onTransitionFrame: (tester) {
        expect(
          find.ancestor(
            of: find.byType(ShopFormScreen),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is SlideTransition && widget.position.value.dy != 0,
            ),
          ),
          findsOneWidget,
        );
      },
    );
  });

  testWidgets('seller with an assigned route can open backup through router', (
    tester,
  ) async {
    final router = await _pumpBackupRoute(tester, routeIds: const ['route-1']);

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/settings/backup',
    );
    expect(find.byType(DatabaseBackupScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('seller without an assigned route is redirected from backup', (
    tester,
  ) async {
    final router = await _pumpBackupRoute(tester, routeIds: const []);

    expect(router.routerDelegate.currentConfiguration.uri.path, '/');
    expect(find.byType(DatabaseBackupScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy admin can open workspace backup screen', (tester) async {
    final router = await _pumpBackupRoute(
      tester,
      role: UserRole.admin,
      routeIds: const [],
    );

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/settings/backup',
    );
    expect(find.byType(DatabaseBackupScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('supervisor can open operational and notification screens', (
    tester,
  ) async {
    final router = await _pumpBackupRoute(
      tester,
      role: UserRole.supervisor,
      routeIds: const [],
      location: '/routes/new',
    );

    expect(router.routerDelegate.currentConfiguration.uri.path, '/routes/new');
    expect(find.byType(RouteFormScreen), findsOneWidget);

    router.go('/settings/backup');
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/');
    expect(find.byType(DatabaseBackupScreen), findsNothing);

    router.go('/notifications');
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/notifications',
    );
    expect(find.byType(NotificationCenterScreen), findsOneWidget);
    expect(
      AppShell.navigationRoutesFor(
        UserModel(
          id: 'supervisor',
          email: '',
          displayName: '',
          role: UserRole.supervisor,
          tenantId: 'tenant-1',
          active: true,
          createdAt: Timestamp.now(),
          updatedAt: Timestamp.now(),
        ),
      ),
      contains('/notifications'),
    );

    router.go('/users');
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/');
    expect(tester.takeException(), isNull);
  });

  testWidgets('seller remains unable to open notification center', (
    tester,
  ) async {
    final router = await _pumpBackupRoute(
      tester,
      role: UserRole.seller,
      routeIds: const ['route-1'],
      location: '/notifications',
    );

    expect(router.routerDelegate.currentConfiguration.uri.path, '/');
    expect(find.byIcon(Icons.notifications_outlined), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<GoRouter> _pumpBackupRoute(
  WidgetTester tester, {
  required List<String> routeIds,
  UserRole role = UserRole.seller,
  bool disableAnimations = false,
  String location = '/settings/backup',
  void Function(WidgetTester tester)? onTransitionFrame,
}) async {
  SharedPreferences.setMockInitialValues({
    'whats_new_seen_version': AppBrand.appVersion,
  });
  final now = Timestamp.now();
  final user = UserModel(
    id: 'test-user',
    email: 'test@example.com',
    displayName: 'Test User',
    role: role,
    tenantId: 'tenant-1',
    assignedRouteIds: role == UserRole.seller ? routeIds : const [],
    active: true,
    createdAt: now,
    updatedAt: now,
  );
  final tenant = TenantModel(
    id: 'tenant-1',
    name: 'Workspace One',
    slug: 'workspace-one',
    createdAt: now,
    updatedAt: now,
  );
  late GoRouter router;
  late AsyncValue<UserModel?> renderedUser;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => Stream.value(_TestFirebaseUser(user.id)),
        ),
        authUserProvider.overrideWith((ref) => Stream.value(user)),
        databaseBackupProvider.overrideWith(_TestBackupNotifier.new),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        notificationsProvider.overrideWith(
          (ref, tenantId) => Stream.value(const []),
        ),
        activeNotificationShopIdsProvider.overrideWith(
          (ref, tenantId) => Stream.value(const <String>{}),
        ),
        tenantProvider(tenant.id).overrideWith((ref) => Stream.value(tenant)),
      ],
      child: Consumer(
        builder: (context, ref, child) {
          router = ref.watch(appRouterProvider);
          renderedUser = ref.watch(authUserProvider);
          return MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: disableAnimations),
              child: child!,
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(renderedUser.value?.id, user.id);
  expect(renderedUser.value?.canCreateBackup, user.canCreateBackup);
  router.go(location);
  if (onTransitionFrame != null) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    onTransitionFrame(tester);
  }
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 7));
  await tester.pumpAndSettle();
  return router;
}

class _TestFirebaseUser implements User {
  @override
  final String uid;

  _TestFirebaseUser(this.uid);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestBackupNotifier extends DatabaseBackupNotifier {
  @override
  void build() {}

  @override
  Future<bool> getAutoEnabled() async => false;

  @override
  Future<int> getIntervalMinutes() async => 1440;

  @override
  Future<DateTime?> getLastBackupAt() async => null;

  @override
  Future<DateTime?> getLastDriveBackupAt() async => null;

  @override
  Future<DateTime?> getLastRestoreAt() async => null;

  @override
  Future<String?> getLastRestoreBy() async => null;
}
