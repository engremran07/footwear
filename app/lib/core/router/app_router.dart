import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../screens/login_screen.dart';
import '../../screens/dashboard_screen.dart';
import '../../screens/products_list_screen.dart';
import '../../screens/product_form_screen.dart';
import '../../screens/product_detail_screen.dart';
import '../../screens/inventory_batch_list_screen.dart';
import '../../screens/inventory_batch_form_screen.dart';
import '../../screens/inventory_batch_detail_screen.dart';
import '../../screens/orders_list_screen.dart';
import '../../screens/order_form_screen.dart';
import '../../screens/order_detail_screen.dart';
import '../../screens/customers_list_screen.dart';
import '../../screens/customer_form_screen.dart';
import '../../screens/customer_detail_screen.dart';
import '../../screens/workers_list_screen.dart';
import '../../screens/worker_form_screen.dart';
import '../../screens/worker_detail_screen.dart';
import '../../screens/worker_payment_form_screen.dart';
import '../../screens/expenses_list_screen.dart';
import '../../screens/expense_form_screen.dart';
import '../../screens/cash_screen.dart';
import '../../screens/approvals_screen.dart';
import '../../screens/purchase_orders_list_screen.dart';
import '../../screens/purchase_order_form_screen.dart';
import '../../screens/purchase_order_detail_screen.dart';
import '../../screens/suppliers_list_screen.dart';
import '../../screens/supplier_form_screen.dart';
import '../../screens/supplier_detail_screen.dart';
import '../../screens/qc_screen.dart';
import '../../screens/waste_screen.dart';
import '../../screens/pnl_screen.dart';
import '../../screens/reports_screen.dart';
import '../../screens/settings_screen.dart';
import '../../screens/returns_list_screen.dart';
import '../../screens/return_form_screen.dart';
import '../../screens/return_detail_screen.dart';
import '../../widgets/app_shell.dart';

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

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final isLoggedIn = authState.valueOrNull != null;
      final isLoginRoute = state.matchedLocation == '/login';

      if (!isLoggedIn && !isLoginRoute) return '/login';
      if (isLoggedIn && isLoginRoute) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        pageBuilder: (_, s) => _fadePage(const LoginScreen(), s),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
              path: '/',
              pageBuilder: (_, s) => _fadePage(const DashboardScreen(), s)),
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
          // Inventory
          GoRoute(
              path: '/inventory',
              pageBuilder: (_, s) =>
                  _fadePage(const InventoryBatchListScreen(), s)),
          GoRoute(
              path: '/inventory/new',
              pageBuilder: (_, s) =>
                  _fadePage(const InventoryBatchFormScreen(), s)),
          GoRoute(
              path: '/inventory/:id',
              pageBuilder: (_, s) => _fadePage(
                  InventoryBatchDetailScreen(batchId: s.pathParameters['id']!),
                  s)),
          // Orders
          GoRoute(
              path: '/orders',
              pageBuilder: (_, s) => _fadePage(const OrdersListScreen(), s)),
          GoRoute(
              path: '/orders/new',
              pageBuilder: (_, s) => _fadePage(const OrderFormScreen(), s)),
          GoRoute(
              path: '/orders/:id',
              pageBuilder: (_, s) => _fadePage(
                  OrderDetailScreen(orderId: s.pathParameters['id']!), s)),
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
          // Workers
          GoRoute(
              path: '/workers',
              pageBuilder: (_, s) => _fadePage(const WorkersListScreen(), s)),
          GoRoute(
              path: '/workers/new',
              pageBuilder: (_, s) => _fadePage(const WorkerFormScreen(), s)),
          GoRoute(
              path: '/workers/:id/edit',
              pageBuilder: (_, s) => _fadePage(
                  WorkerFormScreen(workerId: s.pathParameters['id']!), s)),
          GoRoute(
              path: '/workers/:id',
              pageBuilder: (_, s) => _fadePage(
                  WorkerDetailScreen(workerId: s.pathParameters['id']!), s)),
          GoRoute(
              path: '/workers/:id/pay',
              pageBuilder: (_, s) => _fadePage(
                  WorkerPaymentFormScreen(workerId: s.pathParameters['id']!),
                  s)),
          // Expenses
          GoRoute(
              path: '/expenses',
              pageBuilder: (_, s) => _fadePage(const ExpensesListScreen(), s)),
          GoRoute(
              path: '/expenses/new',
              pageBuilder: (_, s) => _fadePage(const ExpenseFormScreen(), s)),
          // Financial
          GoRoute(
              path: '/cash',
              pageBuilder: (_, s) => _fadePage(const CashScreen(), s)),
          GoRoute(
              path: '/approvals',
              pageBuilder: (_, s) => _fadePage(const ApprovalsScreen(), s)),
          // Purchase Orders
          GoRoute(
              path: '/purchase-orders',
              pageBuilder: (_, s) =>
                  _fadePage(const PurchaseOrdersListScreen(), s)),
          GoRoute(
              path: '/purchase-orders/new',
              pageBuilder: (_, s) =>
                  _fadePage(const PurchaseOrderFormScreen(), s)),
          GoRoute(
              path: '/purchase-orders/:id',
              pageBuilder: (_, s) => _fadePage(
                  PurchaseOrderDetailScreen(id: s.pathParameters['id']!), s)),
          // Suppliers
          GoRoute(
              path: '/suppliers',
              pageBuilder: (_, s) => _fadePage(const SuppliersListScreen(), s)),
          GoRoute(
              path: '/suppliers/new',
              pageBuilder: (_, s) => _fadePage(const SupplierFormScreen(), s)),
          GoRoute(
              path: '/suppliers/:id/edit',
              pageBuilder: (_, s) => _fadePage(
                  SupplierFormScreen(supplierId: s.pathParameters['id']!), s)),
          GoRoute(
              path: '/suppliers/:id',
              pageBuilder: (_, s) => _fadePage(
                  SupplierDetailScreen(id: s.pathParameters['id']!), s)),
          // Returns
          GoRoute(
              path: '/returns',
              pageBuilder: (_, s) => _fadePage(const ReturnsListScreen(), s)),
          GoRoute(
              path: '/returns/new',
              pageBuilder: (_, s) => _fadePage(const ReturnFormScreen(), s)),
          GoRoute(
              path: '/returns/:id',
              pageBuilder: (_, s) => _fadePage(
                  ReturnDetailScreen(returnId: s.pathParameters['id']!), s)),
          // Operations
          GoRoute(
              path: '/qc',
              pageBuilder: (_, s) => _fadePage(const QcScreen(), s)),
          GoRoute(
              path: '/waste',
              pageBuilder: (_, s) => _fadePage(const WasteScreen(), s)),
          // Reports
          GoRoute(
              path: '/pnl',
              pageBuilder: (_, s) => _fadePage(const PnlScreen(), s)),
          GoRoute(
              path: '/reports',
              pageBuilder: (_, s) => _fadePage(const ReportsScreen(), s)),
          // Admin
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
