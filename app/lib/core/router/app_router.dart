import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../screens/login_screen.dart';
import '../../screens/dashboard_screen.dart';
import '../../screens/routes_list_screen.dart';
import '../../screens/route_form_screen.dart';
import '../../screens/route_detail_screen.dart';
import '../../screens/shops_list_screen.dart';
import '../../screens/shop_form_screen.dart';
import '../../screens/shop_detail_screen.dart';
import '../../screens/products_list_screen.dart';
import '../../screens/product_form_screen.dart';
import '../../screens/product_detail_screen.dart';
import '../../screens/variant_form_screen.dart';
import '../../screens/inventory_screen.dart';
import '../../screens/reports_screen.dart';
import '../../screens/settings_screen.dart';
import '../../screens/profile_screen.dart';
import '../../screens/invoices_list_screen.dart';
import '../../screens/invoice_detail_screen.dart';
import '../../screens/create_sale_invoice_screen.dart';
import '../../screens/bootstrap_profile_screen.dart';
import '../../screens/about_screen.dart';
import '../../screens/users_list_screen.dart';
import '../../widgets/app_shell.dart';
import '../l10n/app_locale.dart';

/// Normalize path: strip query params, trailing slashes, collapse double slashes.
String _normalizePath(String raw) {
  var p = Uri.parse(raw).path;
  p = p.replaceAll(RegExp(r'/+'), '/'); // collapse double slashes
  if (p.length > 1 && p.endsWith('/')) p = p.substring(0, p.length - 1);
  return p;
}

bool _isAdminOnlyPath(String rawPath) {
  final path = _normalizePath(rawPath);
  if (path == '/settings' ||
      path == '/users' ||
      path == '/routes/new' ||
      path == '/products/new') {
    return true;
  }
  return RegExp(r'^/routes/[^/]+/edit$').hasMatch(path) ||
      RegExp(r'^/products/[^/]+/edit$').hasMatch(path) ||
      RegExp(r'^/products/[^/]+/variants/new$').hasMatch(path) ||
      RegExp(r'^/products/[^/]+/variants/[^/]+/edit$').hasMatch(path);
}

bool _isSellerBlockedPath(String rawPath) {
  final path = _normalizePath(rawPath);
  return path == '/routes' ||
      path == '/reports' ||
      path == '/settings' ||
      path == '/routes/new' ||
      RegExp(r'^/routes/[^/]+$').hasMatch(path) ||
      RegExp(r'^/routes/[^/]+/edit$').hasMatch(path);
}

/// Material shared-axis Z transition (scale+fade) for all routes.
CustomTransitionPage<void> _fadePage(Widget child, GoRouterState state) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final fadeIn = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      final scaleIn = CurvedAnimation(
        parent: animation,
        curve: Curves.fastOutSlowIn,
      );
      return FadeTransition(
        opacity: fadeIn,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1.0).animate(scaleIn),
          child: child,
        ),
      );
    },
  );
}

/// Slide-up + fade for form / create / edit screens.
CustomTransitionPage<void> _slidePage(Widget child, GoRouterState state) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final slideIn =
          Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: Curves.fastOutSlowIn),
          );
      final fadeIn = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return FadeTransition(
        opacity: fadeIn,
        child: SlideTransition(position: slideIn, child: child),
      );
    },
  );
}

/// Drives GoRouter redirects in response to auth-state changes.
///
/// Uses [ref.listen] (not ref.watch) so this notifier — and the GoRouter
/// that holds it — are created ONCE and never recreated when auth streams
/// emit. Only the redirect callback is re-evaluated, keeping the user on
/// their current screen (e.g. Settings) instead of bouncing to '/'.
class RouterNotifier extends ChangeNotifier {
  final Ref _ref;
  Timer? _debounceTimer;

  RouterNotifier(this._ref) {
    _ref.listen<AsyncValue<User?>>(authStateProvider, (prev, next) {
      final prevUid = prev?.value?.uid;
      final nextUid = next.value?.uid;
      if (prevUid != nextUid || prev?.isLoading != next.isLoading) {
        _scheduleNotify();
      }
    });
    _ref.listen<AsyncValue<UserModel?>>(authUserProvider, (prev, next) {
      final prevUser = prev?.value;
      final nextUser = next.value;
      final authRelevantChanged =
          prevUser?.id != nextUser?.id ||
          prevUser?.role != nextUser?.role ||
          prevUser?.active != nextUser?.active;
      if (authRelevantChanged || prev?.isLoading != next.isLoading) {
        _scheduleNotify();
      }
    });
  }

  void _scheduleNotify() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 100), notifyListeners);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  String? redirect(BuildContext context, GoRouterState state) {
    final isLoggedIn = _ref.read(authStateProvider).value != null;
    final isLoginRoute = state.matchedLocation == '/login';
    final isBootstrapRoute = state.matchedLocation == '/bootstrap-profile';

    if (!isLoggedIn && !isLoginRoute) return '/login';
    if (!isLoggedIn) return null;

    final appUserState = _ref.read(authUserProvider);
    if (appUserState.isLoading) return null;

    final appUser = appUserState.value;
    if (appUser == null) {
      if (!isBootstrapRoute) return '/bootstrap-profile';
      return null;
    }

    if (!appUser.active) return '/login';

    if (isLoginRoute || isBootstrapRoute) return '/';

    if (_isAdminOnlyPath(state.matchedLocation) && !appUser.isAdmin) {
      return '/';
    }
    if (appUser.isSeller && _isSellerBlockedPath(state.matchedLocation)) {
      return '/';
    }
    return null;
  }
}

final _routerNotifierProvider = Provider<RouterNotifier>((ref) {
  return RouterNotifier(ref);
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(_routerNotifierProvider);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: notifier,
    redirect: notifier.redirect,
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
            pageBuilder: (_, s) => _fadePage(const DashboardScreen(), s),
          ),
          // Routes
          GoRoute(
            path: '/routes',
            pageBuilder: (_, s) => _fadePage(const RoutesListScreen(), s),
          ),
          GoRoute(
            path: '/routes/new',
            pageBuilder: (_, s) => _slidePage(const RouteFormScreen(), s),
          ),
          GoRoute(
            path: '/routes/:id/edit',
            pageBuilder: (_, s) => _slidePage(
              RouteFormScreen(routeId: s.pathParameters['id']!),
              s,
            ),
          ),
          GoRoute(
            path: '/routes/:id',
            pageBuilder: (_, s) => _fadePage(
              RouteDetailScreen(routeId: s.pathParameters['id']!),
              s,
            ),
          ),
          // Shops
          GoRoute(
            path: '/shops',
            pageBuilder: (_, s) => _fadePage(const ShopsListScreen(), s),
          ),
          GoRoute(
            path: '/shops/new',
            pageBuilder: (_, s) => _slidePage(
              ShopFormScreen(
                preselectedRouteId: s.uri.queryParameters['routeId'],
              ),
              s,
            ),
          ),
          GoRoute(
            path: '/shops/:id/edit',
            pageBuilder: (_, s) =>
                _slidePage(ShopFormScreen(shopId: s.pathParameters['id']!), s),
          ),
          GoRoute(
            path: '/shops/:id',
            pageBuilder: (_, s) =>
                _fadePage(ShopDetailScreen(shopId: s.pathParameters['id']!), s),
          ),
          // Products
          GoRoute(
            path: '/products',
            pageBuilder: (_, s) => _fadePage(const ProductsListScreen(), s),
          ),
          GoRoute(
            path: '/products/new',
            pageBuilder: (_, s) => _slidePage(const ProductFormScreen(), s),
          ),
          GoRoute(
            path: '/products/:id/edit',
            pageBuilder: (_, s) => _slidePage(
              ProductFormScreen(productId: s.pathParameters['id']!),
              s,
            ),
          ),
          GoRoute(
            path: '/products/:id',
            pageBuilder: (_, s) => _fadePage(
              ProductDetailScreen(productId: s.pathParameters['id']!),
              s,
            ),
          ),
          GoRoute(
            path: '/products/:id/variants/new',
            pageBuilder: (_, s) => _slidePage(
              VariantFormScreen(productId: s.pathParameters['id']!),
              s,
            ),
          ),
          GoRoute(
            path: '/products/:id/variants/:vid/edit',
            pageBuilder: (_, s) => _slidePage(
              VariantFormScreen(
                productId: s.pathParameters['id']!,
                variantId: s.pathParameters['vid']!,
              ),
              s,
            ),
          ),
          // Inventory
          GoRoute(
            path: '/inventory',
            pageBuilder: (_, s) => _fadePage(const InventoryScreen(), s),
          ),
          // Invoices
          GoRoute(
            path: '/invoices',
            pageBuilder: (_, s) => _fadePage(const InvoicesListScreen(), s),
          ),
          GoRoute(
            path: '/invoices/new',
            pageBuilder: (_, s) => _slidePage(
              CreateSaleInvoiceScreen(
                preselectedShopId: s.uri.queryParameters['shopId'],
              ),
              s,
            ),
          ),
          GoRoute(
            path: '/invoices/:id',
            pageBuilder: (_, s) => _fadePage(
              InvoiceDetailScreen(
                invoiceId: s.pathParameters['id']!,
                backTo: s.uri.queryParameters['from'],
              ),
              s,
            ),
          ),
          // Users (admin-only)
          GoRoute(
            path: '/users',
            pageBuilder: (_, s) => _fadePage(const UsersListScreen(), s),
          ),
          // Reports
          GoRoute(
            path: '/reports',
            pageBuilder: (_, s) => _fadePage(const ReportsScreen(), s),
          ),
          // Profile
          GoRoute(
            path: '/profile',
            pageBuilder: (_, s) => _fadePage(const ProfileScreen(), s),
          ),
          // About
          GoRoute(
            path: '/about',
            pageBuilder: (_, s) => _fadePage(const AboutScreen(), s),
          ),
          // Settings
          GoRoute(
            path: '/settings',
            pageBuilder: (_, s) => _fadePage(const SettingsScreen(), s),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => _ErrorPage(error: state.error),
  );
});

// ─── 404 / Error ─────────────────────────────────────────────────────────────

class _ErrorPage extends ConsumerWidget {
  final Exception? error;
  const _ErrorPage({this.error});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                tr('error', ref),
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                tr('not_found', ref),
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () => context.go('/'),
                icon: const Icon(Icons.home_outlined),
                label: Text(tr('dashboard', ref)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
