import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../screens/login_screen.dart';
import '../../screens/dashboard_screen.dart';
import '../../screens/routes_list_screen.dart';
import '../../screens/route_form_screen.dart';
import '../../screens/route_detail_screen.dart';
import '../../screens/shops_list_screen.dart';
import '../../screens/shop_form_screen.dart';
import '../../screens/shop_detail_screen.dart';
import '../../screens/customers_list_screen.dart';
import '../../screens/customer_form_screen.dart';
import '../../screens/customer_detail_screen.dart';
import '../../screens/products_list_screen.dart';
import '../../screens/product_form_screen.dart';
import '../../screens/product_detail_screen.dart';
import '../../screens/variant_form_screen.dart';
import '../../screens/inventory_screen.dart';
import '../../screens/reports_screen.dart';
import '../../screens/settings_screen.dart';
import '../../screens/bootstrap_profile_screen.dart';
import '../../widgets/app_shell.dart';

bool _isAdminOnlyPath(String path) {
  if (path == '/settings' || path == '/routes/new' || path == '/products/new') {
    return true;
  }
  return RegExp(r'^/routes/[^/]+/edit$').hasMatch(path) ||
      RegExp(r'^/products/[^/]+/edit$').hasMatch(path) ||
      RegExp(r'^/products/[^/]+/variants/new$').hasMatch(path) ||
      RegExp(r'^/products/[^/]+/variants/[^/]+/edit$').hasMatch(path);
}

bool _isSellerBlockedPath(String path) {
  return path == '/routes' ||
      path == '/customers' ||
      path == '/reports' ||
      path == '/settings' ||
      path == '/routes/new' ||
      path == '/customers/new' ||
      RegExp(r'^/routes/[^/]+$').hasMatch(path) ||
      RegExp(r'^/routes/[^/]+/edit$').hasMatch(path) ||
      RegExp(r'^/customers/[^/]+$').hasMatch(path) ||
      RegExp(r'^/customers/[^/]+/edit$').hasMatch(path);
}

/// Smooth fade+slide transition for all routes.
CustomTransitionPage<void> _fadePage(Widget child, GoRouterState state) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 250),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.03, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final appUserState = ref.watch(authUserProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final isLoggedIn = authState.valueOrNull != null;
      final isLoginRoute = state.matchedLocation == '/login';
      final isBootstrapRoute = state.matchedLocation == '/bootstrap-profile';

      if (!isLoggedIn && !isLoginRoute) return '/login';

      if (!isLoggedIn) return null;
      if (appUserState.isLoading) return null;

      final appUser = appUserState.valueOrNull;
      if (appUser == null) {
        if (!isBootstrapRoute) return '/bootstrap-profile';
        return null;
      }

      if (isLoginRoute || isBootstrapRoute) return '/';

      if (_isAdminOnlyPath(state.matchedLocation) && !appUser.isAdmin) {
        return '/';
      }
      if (appUser.isSeller && _isSellerBlockedPath(state.matchedLocation)) {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        pageBuilder: (_, s) => _fadePage(const LoginScreen(), s),
      ),
      GoRoute(
        path: '/bootstrap-profile',
        pageBuilder: (_, s) => _fadePage(const BootstrapProfileScreen(), s),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
              path: '/',
              pageBuilder: (_, s) => _fadePage(const DashboardScreen(), s)),
          // Routes
          GoRoute(
              path: '/routes',
              pageBuilder: (_, s) => _fadePage(const RoutesListScreen(), s)),
          GoRoute(
              path: '/routes/new',
              pageBuilder: (_, s) => _fadePage(const RouteFormScreen(), s)),
          GoRoute(
              path: '/routes/:id/edit',
              pageBuilder: (_, s) => _fadePage(
                  RouteFormScreen(routeId: s.pathParameters['id']!), s)),
          GoRoute(
              path: '/routes/:id',
              pageBuilder: (_, s) => _fadePage(
                  RouteDetailScreen(routeId: s.pathParameters['id']!), s)),
          // Shops
          GoRoute(
              path: '/shops',
              pageBuilder: (_, s) => _fadePage(const ShopsListScreen(), s)),
          GoRoute(
              path: '/shops/new',
              pageBuilder: (_, s) => _fadePage(
                  ShopFormScreen(
                      preselectedRouteId: s.uri.queryParameters['routeId']),
                  s)),
          GoRoute(
              path: '/shops/:id/edit',
              pageBuilder: (_, s) => _fadePage(
                  ShopFormScreen(shopId: s.pathParameters['id']!), s)),
          GoRoute(
              path: '/shops/:id',
              pageBuilder: (_, s) => _fadePage(
                  ShopDetailScreen(shopId: s.pathParameters['id']!), s)),
          // Customers
          GoRoute(
              path: '/customers',
              pageBuilder: (_, s) => _fadePage(const CustomersListScreen(), s)),
          GoRoute(
              path: '/customers/new',
              pageBuilder: (_, s) => _fadePage(const CustomerFormScreen(), s)),
          GoRoute(
              path: '/customers/:id/edit',
              pageBuilder: (_, s) => _fadePage(
                  CustomerFormScreen(customerId: s.pathParameters['id']!), s)),
          GoRoute(
              path: '/customers/:id',
              pageBuilder: (_, s) => _fadePage(
                  CustomerDetailScreen(customerId: s.pathParameters['id']!),
                  s)),
          // Products
          GoRoute(
              path: '/products',
              pageBuilder: (_, s) => _fadePage(const ProductsListScreen(), s)),
          GoRoute(
              path: '/products/new',
              pageBuilder: (_, s) => _fadePage(const ProductFormScreen(), s)),
          GoRoute(
              path: '/products/:id/edit',
              pageBuilder: (_, s) => _fadePage(
                  ProductFormScreen(productId: s.pathParameters['id']!), s)),
          GoRoute(
              path: '/products/:id',
              pageBuilder: (_, s) => _fadePage(
                  ProductDetailScreen(productId: s.pathParameters['id']!), s)),
          GoRoute(
              path: '/products/:id/variants/new',
              pageBuilder: (_, s) => _fadePage(
                  VariantFormScreen(productId: s.pathParameters['id']!), s)),
          GoRoute(
              path: '/products/:id/variants/:vid/edit',
              pageBuilder: (_, s) => _fadePage(
                  VariantFormScreen(
                      productId: s.pathParameters['id']!,
                      variantId: s.pathParameters['vid']!),
                  s)),
          // Inventory
          GoRoute(
              path: '/inventory',
              pageBuilder: (_, s) => _fadePage(const InventoryScreen(), s)),
          // Reports
          GoRoute(
              path: '/reports',
              pageBuilder: (_, s) => _fadePage(const ReportsScreen(), s)),
          // Settings
          GoRoute(
              path: '/settings',
              pageBuilder: (_, s) => _fadePage(const SettingsScreen(), s)),
        ],
      ),
    ],
    errorBuilder: (context, state) => const Scaffold(
      body: Center(child: Text('Page not found')),
    ),
  );
});
