---
name: navigation-routing
description: "Use when: adding routes, fixing navigation guards, breadcrumb issues, go_router redirect logic, or role-based screen access."
---

# Skill: Navigation & Routing

## Domain
go_router navigation for Flutter ShoesERP with role-based redirect guards.

## Key File
- `app/lib/core/router/app_router.dart` — single source of route truth

## Canonical Routes
```
/login         → LoginScreen
/              → DashboardScreen  (shell route)
/routes        → RouteListScreen
/routes/new    → RouteFormScreen
/routes/:id    → RouteDetailScreen
/routes/:id/edit → RouteFormScreen
/shops         → ShopListScreen   (alias for /customers for sellers)
/shops/new     → CustomerFormScreen
/shops/:id     → ShopDetailScreen (shop = customer in route context)
/customers     → CustomerListScreen
/customers/new → CustomerFormScreen
/customers/:id → CustomerDetailScreen
/customers/:id/edit → CustomerFormScreen
/products      → ProductListScreen
/products/new  → ProductFormScreen
/products/:id  → ProductDetailScreen
/products/:id/edit → ProductFormScreen
/products/:id/variants/new → VariantFormScreen
/products/:id/variants/:vid/edit → VariantFormScreen
/inventory     → InventoryScreen
/reports       → ReportsScreen
/settings      → SettingsScreen
```

## Shell + Breadcrumb
- `AppShell` wraps all authenticated routes with bottom nav + AppBar
- `_BreadcrumbTitle` computes title from current route name segments
- NavigationBar items: Dashboard, Routes, Customers/Shops, Products, Reports

## Role Guard Pattern
```dart
redirect: (context, state) {
  final user = ref.read(authUserProvider).valueOrNull;
  if (user == null) return '/login';
  if (adminOnlyPaths.contains(state.matchedLocation) && !user.isAdmin) return '/';
  return null;
}
```

## Common Pitfalls
- Use `context.go()` for bottom-nav tabs (replace stack); `context.push()` for detail pages
- `GoRouter.of(context).pop()` only works if there is a page to pop — use `canPop()` guard
- Shell routes do NOT support `context.pop()` back to login — use `context.go('/login')` on sign-out
