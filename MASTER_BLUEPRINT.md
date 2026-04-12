# ShoesERP Master Blueprint

**Version:** v3.5.1+44  
**Last updated:** 2026-04-11 — Audit v13  
**Purpose:** Architecture handoff document — living reference for structure, conventions, and runtime contracts.

---

## 1. System Overview

ShoesERP is a route/seller distribution ERP for a footwear distribution business operating in Saudi Arabia. It manages inventory, routes, shop (customer) management, invoicing, cash collection, and financial reporting.

**Tier:** Firebase Spark (free). No Cloud Functions, no Firebase Storage.  
**Platforms:** Android (fat APK) + Web (Firebase Hosting)  
**State management:** Riverpod 2.x (StreamProvider.autoDispose, AsyncNotifier)  
**Navigation:** GoRouter (21 routes, auth guard)  
**Auth:** Fire base Auth (email+password) + secondary FirebaseApp for safe user creation

---

## 2. Role Model

| Role value (Firestore) | Permissions |
|------------------------|-------------|
| `admin` | Full write access to all collections. Can act as field seller (has own seller_inventory). |
| `manager` | Treated as admin-equivalent in all app + rules logic (legacy value). |
| `seller` | Read active business docs. Create/update shops in assigned route. Create transactions for assigned route. Update own profile. No write to routes/products/settings. |

**Normalization rule:** All role values are written `trim().toLowerCase()`. Rules use `isAdminRole()` regex `/(admin|manager)/i`.

**First-user bootstrap risk:** The Firestore rule `isBootstrapAdminCreate()` allows the very first document in `/users/` to be written with `role: 'admin'` only when no `/users/` docs and no `/settings/global` doc yet exist. This is a one-time window — once any user doc or settings doc is present, the bootstrap path is permanently closed. **Never delete all user/settings documents in production**, as this re-opens the bootstrap window and allows a rogue actor to self-promote to admin.

---

## 3. Collection Map

| Logical name | Firestore collection | Constants key |
|---|---|---|
| users | `users` | `Collections.users` |
| products | `products` | `Collections.products` |
| product_variants | `product_variants` | `Collections.productVariants` |
| seller_inventory | `seller_inventory` | `Collections.sellerInventory` |
| inventory_transactions | `inventory_transactions` | `Collections.inventoryTransactions` |
| routes | `routes` | `Collections.routes` |
| shops (customers) | `customers` | `Collections.shops` |
| transactions | `transactions` | `Collections.transactions` |
| invoices | `invoices` | `Collections.invoices` |
| settings | `settings` | `Collections.settings` |

> `Collections.*` constants are in `app/lib/core/constants/collections.dart`. No raw `.collection('string')` calls permitted anywhere in `app/lib/`.

---

## 4. Financial Pipeline (Non-Negotiable)

```text
Pathway 1 — Sale with stock:
  CreateSaleInvoiceScreen
    → InvoiceNotifier.createSaleInvoice()
    → Invoice + cash_out tx + optional cash_in tx + seller_inventory deduction
       (ONE atomic Firestore batch)

Pathway 2 — Cash collection (old debt, no goods):
  ShopDetailScreen
    → TransactionNotifier.create(type: 'cash_in')
    → Cash_in ledger entry ONLY — no invoice, no stock movement

Void/Return (admin only):
  → InvoiceNotifier.voidInvoice()
  → Returns stock. cashRefund mode: 2 transactions. creditBalance mode: 1 transaction.
```

`shop.balance` is **the sole monetary source of truth**. Every balance mutation goes through InvoiceNotifier or TransactionNotifier via atomic batch. Direct writes to `shop.balance` are prohibited.

---

## 5. Provider Graph (key providers)

| Provider | Type | Scope | Notes |
|---|---|---|---|
| `authStateProvider` | StreamProvider | global | Firebase Auth `idTokenChanges()` |
| `currentUserProvider` | StreamProvider.autoDispose | global | Firestore user doc stream |
| `dashboardStatsProvider` | FutureProvider.autoDispose | admin | Aggregate counts; cached in `_lastGoodDashboardStatsProvider` |
| `allTransactionsProvider` | StreamProvider.autoDispose | admin | **Must be in `_invalidateRoleScopedProviders()`** |
| `allInvoicesProvider` | StreamProvider.autoDispose | admin | Must be in `_invalidateRoleScopedProviders()` |
| `adminAllSellerInventoryProvider` | StreamProvider.autoDispose | admin | Must be in `_invalidateRoleScopedProviders()` |
| `sellerInventoryProvider` | StreamProvider.autoDispose | seller | Scoped to seller_id |
| `shopTransactionsProvider` | StreamProvider.autoDispose | admin+seller | Capped 150 docs |
| `shopsAnalyticsProvider` | StreamProvider.autoDispose | admin | Capped 500 docs |
| `routesProvider` | StreamProvider.autoDispose | admin+seller | |
| `productsProvider` | StreamProvider.autoDispose | admin+seller | |

All admin-scoped providers **must** appear in `_invalidateRoleScopedProviders()` in `auth_provider.dart` to prevent data leaks across sessions.

---

## 6. Router Map (GoRouter)

Defined in `app/lib/core/router/app_router.dart`. Auth guard redirects unauthenticated users to `/login`.

```text
/login              — LoginScreen (public)
/                   — DashboardScreen (admin) / SellerHomeScreen (seller)
/routes             — RoutesListScreen
/routes/new         — CreateRouteScreen
/routes/:id         — RouteDetailScreen
/routes/:id/edit    — EditRouteScreen
/shops              — ShopsListScreen
/shops/new          — CreateShopScreen
/shops/:id          — ShopDetailScreen
/shops/:id/edit     — EditShopScreen
/products           — ProductsListScreen
/products/new       — CreateProductScreen
/products/:id       — ProductDetailScreen
/products/:id/edit  — EditProductScreen
/products/:id/variants/new       — CreateVariantScreen
/products/:id/variants/:vid/edit — EditVariantScreen
/inventory          — InventoryScreen
/invoices           — InvoicesListScreen
/invoices/:id       — InvoiceDetailScreen
/reports            — ReportsScreen
/profile            — ProfileScreen
/settings           — SettingsScreen (admin-only)
```

---

## 7. Stock Units

- `quantity_available` in Firestore stores **PAIRS** (legacy compat)
- UI always shows and accepts **dozens** as primary unit
- 1 dozen = 12 pairs; extra pairs (0–11) optional per entry
- `canHaveSellerInventory` getter always returns `true` (admin and seller can own stock)

---

## 8. CI/CD Workflow Map

| File | Trigger | Key steps |
|------|---------|-----------|
| `.github/workflows/ci.yml` | push/PR to main | analyse (3.29.2) → test --coverage → hygiene (13 gates) |
| `.github/workflows/build-apk.yml` | workflow_dispatch | fat APK build + monotonic versionCode check |
| `.github/workflows/deploy-web.yml` | push to main | analyze → test → build web → Firebase Hosting deploy |
| `.github/workflows/release.yml` | tag push / workflow_dispatch | validate → build APK + web → deploy → GitHub Release |

**Hygiene gates (ci.yml):**

1. No raw `.collection('` strings in app/lib/
2. `allTransactionsProvider` in auth_provider.dart
3. No `--split-per-abi` in docs/scripts
4. No Firestore writes in screens/widgets
5. L10n key parity (EN ⊆ AR ⊆ UR)
6. PDF export uses Isolate.run
7. No hardcoded Colors.white/grey/red/black in lib/screens/ or lib/widgets/
8. App version in pubspec.yaml == app_brand.dart
9. widget_test.dart is not a placeholder (no `'OK'` text)
10. No `Colors.black` with opacity patterns in screens/widgets
11. Zero markdown lint issues (`markdownlint-cli@0.43.0` — zero violation tolerance)
12. No untracked TODO/FIXME — all must reference `RR-/PI-` registry entries
13. No raw SnackBar — use `infoSnackBar`/`errorSnackBar`/`successSnackBar`/`warningSnackBar` helpers

---

## 9. Deferred Risks (P0/P1)

| ID | Risk | Mitigation | Unblocked by |
|----|------|-----------|--------------|
| RR-001 | RSA private key in Flutter heap | Admin flow still secure; key is in server-side admin_identity_service; documented P0 | Blaze tier upgrade |
| RR-002 | Float currency arithmetic | ±0.01 epsilon tolerance in invoice provider | Accounting sprint |
| RR-003 | Lock overlay tap-to-dismiss | Sessions still expire; 8h hard cutoff applies | local_auth sprint |
| RR-004 | Hard pagination caps | 150 tx / 500 shops is sufficient for current scale | Scale sprint |

---

## 10. Version + Build

| Field | Current | File |
|-------|---------|------|
| `appVersion` | `3.5.2` | `app/lib/core/constants/app_brand.dart` |
| `buildNumber` | `45` | `app/lib/core/constants/app_brand.dart` |
| `version` | `3.5.2+45` | `app/pubspec.yaml` |

Both files **must stay in sync** before every release. Bump both together.

---

## 11. Environment / Secrets Required

| Secret name | Used by |
|-------------|---------|
| `FIREBASE_OPTIONS_DART` | All workflows |
| `GOOGLE_SERVICES_JSON` | APK build workflow |
| `KEYSTORE_FILE` | APK build + release workflows |
| `KEYSTORE_PASSWORD` | APK build + release workflows |
| `KEY_PASSWORD` | APK build + release workflows |
| `KEY_ALIAS` | APK build + release workflows |
| `FIREBASE_SERVICE_ACCOUNT_SHOESERP` | deploy-web + release workflows |

---

## 12. Audit Score Progression

| Version | Score | Key fixes |
|---------|-------|-----------|
| v1.0.0 | ~30/100 | Initial codebase |
| v3.0.0 | ~52/100 | Enterprise upgrade, Storage removed, L10n |
| v3.2.6 | ~62/100 | 62-issue audit, security fixes, financial integrity |
| v3.4.0 | ~68/100 | 20-agent CI/CD system, session UX, rules hardening |
| v3.4.11 | ~72/100 | Spark hardening, ledger correctness, i18n cleanup |
| v3.5.0 | ~78/100 | Governance layer, CI hardening, color fixes, version pin |
