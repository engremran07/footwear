import 'dart:async';
import 'dart:typed_data';

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
import 'package:footwear_erp/widgets/shimmer_loading.dart';

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

  testWidgets('backup route stays visible while role profile is loading', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'whats_new_seen_version': AppBrand.appVersion,
    });
    final profile = StreamController<UserModel?>();
    addTearDown(profile.close);
    final now = Timestamp.now();
    final tenant = TenantModel(
      id: 'tenant-1',
      name: 'Workspace One',
      slug: 'workspace-one',
      createdAt: now,
      updatedAt: now,
    );
    late GoRouter router;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(_TestFirebaseUser('test-user')),
          ),
          authUserProvider.overrideWith((ref) => profile.stream),
          databaseBackupProvider.overrideWith(_TestBackupNotifier.new),
          isOnlineProvider.overrideWith((ref) => Stream.value(true)),
          tenantProvider('tenant-1')
              .overrideWith((ref) => Stream.value(tenant)),
        ],
        child: Consumer(
          builder: (context, ref, child) {
            router = ref.watch(appRouterProvider);
            return MaterialApp.router(
              routerConfig: router,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child!,
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    router.go('/settings/backup');
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/settings/backup',
    );
    expect(find.byType(ShimmerLoading), findsOneWidget);
    expect(find.byType(DatabaseBackupScreen), findsNothing);

    profile.add(
      UserModel(
        id: 'test-user',
        email: 'admin@example.com',
        displayName: 'Workspace Admin',
        role: UserRole.admin,
        tenantId: 'tenant-1',
        active: true,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/settings/backup',
    );
    expect(find.byType(DatabaseBackupScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
  });

  testWidgets('workspace members do not see workspace names in backup UI', (
    tester,
  ) async {
    final router = await _pumpBackupRoute(
      tester,
      role: UserRole.tenantAdmin,
      routeIds: const [],
    );

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/settings/backup',
    );
    expect(find.byType(DatabaseBackupScreen), findsOneWidget);
    expect(find.text('Workspace One'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'archived workspace blocks business screens with recovery actions',
    (tester) async {
      final now = Timestamp.now();
      final router = await _pumpBackupRoute(
        tester,
        role: UserRole.tenantAdmin,
        routeIds: const [],
        tenantOverride: TenantModel(
          id: 'tenant-1',
          name: 'Workspace One',
          slug: 'workspace-one',
          active: false,
          createdAt: now,
          updatedAt: now,
        ),
      );

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/settings/backup',
      );
      expect(find.byType(DatabaseBackupScreen), findsNothing);
      expect(
        find.text(
          'This workspace has been archived. Contact your platform administrator.',
        ),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing workspace shows a retryable access state', (
    tester,
  ) async {
    await _pumpBackupRoute(
      tester,
      role: UserRole.tenantAdmin,
      routeIds: const [],
      tenantStreamOverride: () => Stream.value(null),
    );

    expect(find.byType(DatabaseBackupScreen), findsNothing);
    expect(
      find.text(
        'The selected workspace is unavailable. Refresh and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace read failure shows mapped retry feedback', (
    tester,
  ) async {
    final error = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );
    await _pumpBackupRoute(
      tester,
      role: UserRole.tenantAdmin,
      routeIds: const [],
      tenantStreamOverride: () => Stream.error(error),
    );

    expect(find.byType(DatabaseBackupScreen), findsNothing);
    expect(
      find.text('You do not have permission to perform this action.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace names stay hidden in the wide app shell', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view
      ..physicalSize = const Size(1400, 900)
      ..devicePixelRatio = 1;

    await _pumpBackupRoute(
      tester,
      role: UserRole.tenantAdmin,
      routeIds: const [],
    );

    expect(find.text('Workspace One'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('root super-admin can open the platform settings hub', (
    tester,
  ) async {
    final router = await _pumpBackupRoute(
      tester,
      role: UserRole.superAdmin,
      routeIds: const [],
      location: '/settings',
    );

    expect(router.routerDelegate.currentConfiguration.uri.path, '/settings');
    expect(find.text('Platform Settings'), findsOneWidget);
    expect(find.text('Workspaces'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unselected super-admin is directed to workspaces from a denied business route',
    (tester) async {
      final router = await _pumpBackupRoute(
        tester,
        role: UserRole.superAdmin,
        routeIds: const [],
        location: '/routes',
      );

      expect(router.routerDelegate.currentConfiguration.uri.path, '/tenants');
      expect(tester.takeException(), isNull);
    },
  );

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

  testWidgets(
    'notification route shows profile permission errors with retry feedback',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'whats_new_seen_version': AppBrand.appVersion,
      });
      var notificationSubscriptions = 0;
      final profileError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      late GoRouter router;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(
              (ref) => Stream.value(_TestFirebaseUser('test-user')),
            ),
            authUserProvider.overrideWith(
              (ref) => Stream<UserModel?>.error(profileError),
            ),
            databaseBackupProvider.overrideWith(_NoopBackupNotifier.new),
            isOnlineProvider.overrideWith((ref) => Stream.value(true)),
            notificationsProvider.overrideWith((ref, tenantId) {
              notificationSubscriptions++;
              return const Stream.empty();
            }),
            activeNotificationShopIdsProvider.overrideWith(
              (ref, tenantId) => Stream.value(const <String>{}),
            ),
          ],
          child: Consumer(
            builder: (context, ref, child) {
              router = ref.watch(appRouterProvider);
              return MaterialApp.router(routerConfig: router);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      router.go('/notifications');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/notifications',
      );
      expect(find.byType(NotificationCenterScreen), findsOneWidget);
      expect(
        find.text('You do not have permission to perform this action.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(notificationSubscriptions, 0);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<GoRouter> _pumpBackupRoute(
  WidgetTester tester, {
  required List<String> routeIds,
  UserRole role = UserRole.seller,
  bool disableAnimations = false,
  String location = '/settings/backup',
  TenantModel? tenantOverride,
  Stream<TenantModel?> Function()? tenantStreamOverride,
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
  final tenant =
      tenantOverride ??
      TenantModel(
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
        tenantsProvider.overrideWith((ref) => Stream.value([tenant])),
        activeNotificationShopIdsProvider.overrideWith(
          (ref, tenantId) => Stream.value(const <String>{}),
        ),
        tenantProvider(tenant.id).overrideWith(
          (ref) => tenantStreamOverride?.call() ?? Stream.value(tenant),
        ),
      ],
      child: Consumer(
        builder: (context, ref, child) {
          router = ref.watch(appRouterProvider);
          renderedUser = ref.watch(authUserProvider);
          return MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: disableAnimations),
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

class _NoopBackupNotifier extends _TestBackupNotifier {
  @override
  Future<
    ({
      Uint8List bytes,
      String localPath,
      String fileName,
      String tenantId,
      String checksum,
      String scope,
      List<String> routeIds,
    })?
  >
  checkAndAutoBackup() async => null;
}
