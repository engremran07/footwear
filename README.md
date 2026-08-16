# FootWear ERP — v3.7.5+53

A mobile-first enterprise resource planning system for footwear distribution businesses. Built with Flutter (Android + Web) and Firebase. Designed for route-based sales operations where an admin manages products, inventory, and sellers, while field sellers record customer transactions on their assigned routes.

> **v3.7.5+53 (2026-04-15)** — Current baseline includes the post-audit hardening pass: provider admin guards, invoice and rules validation tightening, export query caps, model `copyWith`/equality cleanup, theme-safe shimmer, and workflow normalization on Flutter 3.41.6 with expanded test reporting.

---

## Features

### Admin

- **Dashboard** — live stats with shimmer loading, cash flow BarChart, alerts banner, admin speed-dial FAB
- **Products & Variants** — manage SKUs with size/colour variants, carton/dozen/pair stock tracking, share button
- **Routes** — define delivery routes and assign sellers, performance strip, shops sorted by debt
- **Shops (Customers)** — full CRUD with balance ledger, balance trend LineChart, days-overdue indicator
- **Inventory** — warehouse stock allocation with low-stock warning badges
- **Transactions** — cash-in / cash-out ledger with running balance
- **Invoices** — sale invoices, credit notes, void/paid lifecycle, 3-step payment progression bar
- **Reports** — monthly cash flow BarChart, outstanding PieChart, PDF/Excel/image export
- **User Management** — create/edit admin and seller accounts, soft-delete; password reset by email
- **Settings** — company name, logo (base64 ≤50 KB), pairs-per-carton, business preferences
- **Profile** — name, language, theme and password controls for all users

### Seller

- View assigned route and shops
- Record cash-in / cash-out transactions for assigned shops
- View account statements and invoices
- Dashboard and inventory suppress transient permission errors during startup

### Multilingual

English, Arabic (RTL), Urdu (RTL) — 372+ translation keys synced across all screens and PDF exports.

---

## Tech Stack

| Layer | Technology |
| --- | --- |
| Mobile + Web | Flutter 3.41.6 — Android split-per-ABI APKs + Firebase Hosting web |
| Dart SDK | >=3.11.0 |
| State management | flutter_riverpod 3.3.1 (`NotifierProvider`, `AsyncNotifierProvider`, `StreamProvider`) |
| Navigation | go_router 17.2.0 with role-based redirect guards |
| Backend / Auth | Firebase (Firestore + Auth only) — zero Storage, zero Cloud Functions |
| Design system | AppTokens, AppAnimations, AppSanitizer, AppInputFormatters |
| Charts | fl_chart 1.2.0 (BarChart, LineChart, PieChart) |
| PDF export | `pdf` package + `Isolate.run()` — Arabic + Urdu fonts |
| Excel export | Custom xlsx writer (`excel_export.dart`) using `archive ^4.0.0` |
| Print / Share | `printing` + share_plus 13.0.0 |
| Image compression | `flutter_image_compress` (base64 logo) |
| Animations | `flutter_animate` + `shimmer` |

---

## Project Structure

```text
shoeserp/
├── app/                    # Flutter app (Android APK + Web)
│   ├── lib/
│   │   ├── core/           # constants, l10n, router, theme, utils, design tokens
│   │   ├── models/         # Firestore data models
│   │   ├── providers/      # Riverpod notifiers — ALL Firestore writes happen here
│   │   ├── screens/        # all UI screens
│   │   └── widgets/        # shared UI components
│   └── android/            # Android-specific config + signing
├── firestore.rules         # Security rules (deny-by-default, docSizeOk, withinWriteRate)
├── firestore.indexes.json  # Composite indexes for every where+orderBy query pair
└── firebase.json           # Firebase Hosting + Firestore config
```

---

## Setup

### Prerequisites

- Flutter SDK 3.41.6
- Android Studio / Android SDK (API 21+)
- Firebase project (`firebase login`)
- Java 17+

### Install dependencies

```bash
cd app
flutter pub get
```

### Firebase config

Place your `google-services.json` in `app/android/app/` (not committed — obtain from Firebase Console).

### Run (debug)

```bash
cd app
flutter run
```

### Build release APK (split-per-ABI for phone delivery)

```bash
cd app
flutter build apk --release --split-per-abi --dart-define=USE_PLAY_INTEGRITY=true
# Output: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
#         build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
#         build/app/outputs/flutter-apk/app-x86_64-release.apk
#         build/app/outputs/flutter-apk/app-release.apk
```

### Install the release APK to a connected phone

```bash
cd app
adb push build/app/outputs/flutter-apk/app-arm64-v8a-release.apk /sdcard/Download/
adb install -r /sdcard/Download/app-arm64-v8a-release.apk
```

### Build web

```bash
cd app
flutter build web --release
firebase deploy --only hosting
```

Canonical release order: sync or bump the version first, then build web,
deploy Hosting, build the split-per-ABI Android APK set, deploy Firestore
rules/indexes, review the local git delta, and only then commit/push.

---

## Backend Deployment

```bash
# Deploy Firestore security rules and composite indexes
firebase deploy --only firestore:rules,firestore:indexes
```

No Cloud Functions deployment needed. User creation uses a secondary `FirebaseApp` instance. No Firebase Storage — logos are stored as base64 in Firestore; product images use external HTTP URLs.

---

## SaaS Architecture

ShoesERP is designed as a single-project SaaS app. All tenant data lives in one Firebase project and is partitioned by `tenant_id` to support multiple workspaces on the Spark free tier.

- The `tenants` collection stores workspace metadata, plan flags, owner user, and device-pairing policy.
- Every tenant-scoped business document (`users`, `routes`, `customers`/`shops`, `products`, `seller_inventory`, `transactions`, `invoices`, etc.) must carry `tenant_id`.
- `tenant_admin` is scoped to a single tenant; `super_admin` is the global SaaS operator.
- `TenantScope` in `app/lib/core/utils/tenant_scope.dart` is the canonical helper for query and write gating.
- `__global__` is reserved for global/system documents only.

### Tenant Gating Checklist

1. Use `TenantScope.applyToQuery(..., tenantId: ...)` for every business collection query.
2. Use `TenantScope.applyToData(..., tenantId: ...)` or explicit `tenant_id` on every tenant-scoped write.
3. Keep `tenant_admin` tenant-scoped and reserve `super_admin` for global access.
4. Use `Collections.tenants` for workspace documents; avoid hardcoded `tenants` collection strings.
5. Verify Firestore rules enforce tenant ownership for each tenant-scoped collection.
6. Treat shops as `Collections.shops` (`customers` collection alias) with tenant partitioning, not as a separate customer model.
7. Ensure providers select current user tenant context from `authUserProvider` and do not leak cross-tenant streams.
8. Document new tenant-scoped collections and any tenant gating rule changes in both this README and `MASTER_BLUEPRINT.md`.

---

## Roles & Permissions

| Action | Admin | Seller |
| --- | --- | --- |
| Manage products / variants | ✅ | ❌ |
| Manage routes | ✅ | ❌ |
| Delete routes / shops | ✅ | ❌ |
| Manage users | ✅ | ❌ |
| View all shops | ✅ | Assigned route only |
| Create / update shops | ✅ | Assigned route only |
| Create transactions | ✅ | Assigned route only |
| View reports | ✅ | ❌ |
| Adjust inventory | ✅ | ❌ |
| Profile (name/theme/language/password) | ✅ | ✅ |

> `manager` role is treated as admin-equivalent for legacy data compatibility.

---

## Firestore Collections

| Constant (`Collections.*`) | Firestore name | Purpose |
| --- | --- | --- |
| `Collections.users` | `users` | Auth user profiles, roles, route assignments |
| `Collections.products` | `products` | Product catalogue |
| `Collections.productVariants` | `product_variants` | SKU variants with `quantity_available` (stored in pairs) |
| `Collections.routes` | `routes` | Delivery routes with assigned seller |
| `Collections.shops` | `customers` | Shops/customers with running `balance` field |
| `Collections.transactions` | `transactions` | Cash ledger entries per shop |
| `Collections.invoices` | `invoices` | Sale invoices and credit notes |
| `Collections.sellerInventory` | `seller_inventory` | Seller-allocated stock per variant |
| `Collections.inventoryTransactions` | `inventory_transactions` | Stock movement audit trail |
| `Collections.settings` | `settings` | Global business settings |

> **Note:** `Collections.shops` maps to the Firestore collection named `customers` — legacy name preserved for backward compatibility.

---

## Financial Integrity Rules

1. `shop.balance` is the **sole source of truth** for all monetary displays. It is mutated **only** by `InvoiceNotifier` or `TransactionNotifier` via atomic Firestore batch writes.
2. **Pathway 1 (Sale with stock):** `CreateSaleInvoiceScreen` → `InvoiceNotifier.createSaleInvoice()` — invoice + cash ledger entry + stock deduction in one batch.
3. **Pathway 2 (Cash collection, no new goods):** `ShopDetailScreen` → `TransactionNotifier.create(type: 'cash_in')` — ledger entry only, no invoice.
4. **Void/return:** `InvoiceNotifier.voidInvoice()` — admin only, stock returned, one reversal transaction.
5. Never create an invoice for cash-only collection. Never create a standalone transaction for a new stock sale.

---

## Code Quality

```bash
cd app

# Must return "No issues found!"
flutter analyze lib --no-pub

# All tests must pass
flutter test -r expanded

# No raw Firestore collection strings
grep -rn "\.collection('" app/lib/ | grep -v "Collections\."

# No StateProvider (banned — Riverpod 3 removed it)
grep -rn "StateProvider\b" app/lib/ --include="*.dart"
```

---

## Production Signoff Checklist

1. Atomic version bump or explicit version-sync verification: `app/pubspec.yaml` and `app/lib/core/constants/app_brand.dart` must match before release artifacts are built.
2. `flutter analyze lib --no-pub` → quote exact final line.
3. `dart analyze test/` → quote `No issues found!`.
4. `flutter test -r expanded` → quote pass count.
5. `flutter build web --release` → confirm `EXIT: $LASTEXITCODE` = 0.
6. `firebase deploy --only hosting` after the web build.
7. `flutter build apk --release --split-per-abi --dart-define=USE_PLAY_INTEGRITY=true` → quote the generated ABI APK path(s) and size(s).
8. `firebase deploy --only firestore:rules,firestore:indexes` on every signoff, before commit/push is considered complete.
9. `git log --oneline -5`, `git status --short`, and `git diff --stat HEAD` → confirm only expected local changes remain.
10. `git add -A`, `git commit -m "type: summary — vX.Y.Z+N"`, and `git push` → quote commit hash and push output.
11. `adb push build/app/outputs/flutter-apk/app-arm64-v8a-release.apk /sdcard/Download/` followed by `adb install -r /sdcard/Download/app-arm64-v8a-release.apk` to install the phone-delivery APK to a connected device when Android delivery is part of the request.

---

## Troubleshooting

**permission-denied:**

- Verify `users/{uid}.active == true`
- Verify `users/{uid}.role` is canonical (`admin` / `seller`; `manager` is legacy admin-equivalent)
- Verify `firestore.rules` is deployed

**resource-exhausted:**

- Dashboard fallback cache is active (`_lastGoodDashboardStatsProvider`)
- Reduce aggressive refresh loops

**Empty list views:**

- Check `where + orderBy` query shape in provider
- Add composite index to `firestore.indexes.json` and deploy

---

## Canonical Docs

- [AGENTS.md](AGENTS.md) — runtime contract and permission matrix
- [CLAUDE.md](CLAUDE.md) — coding rules, financial pathways, breakage chains
- [SYSTEM_DEEP_DIVE_2026-03-27.md](SYSTEM_DEEP_DIVE_2026-03-27.md) — audit findings
- [app/README.md](app/README.md) — Flutter app architecture detail
