# FootWear ERP — v3.0.0

A mobile-first enterprise resource planning system for footwear distribution businesses. Built with Flutter (Android APK) and Firebase as the backend. Designed for route-based sales operations where an admin manages products, inventory, and sellers, while field sellers record customer transactions on their assigned routes.

> **v3.0.0** — Enterprise upgrade: design system, animations, hardened security, PDF isolate export, session guard, dark mode + RTL QA, 3 split-per-abi release APKs.

---

## Features

### Admin

- **Dashboard** — live stats with shimmer loading, cash flow BarChart, alerts banner, admin speed-dial FAB
- **Products & Variants** — manage SKUs with size/color variants, carton/dozen/pair stock tracking, share button
- **Routes** — define delivery routes and assign sellers, performance strip, shops sorted by debt
- **Customers & Shops** — full CRUD with balance ledger, balance trend LineChart, days-overdue indicator
- **Inventory** — warehouse stock allocation with low-stock warning badges, drag-to-reorder
- **Transactions** — cash-in / cash-out ledger with running balance
- **Invoices** — sale invoices, credit notes, void/paid lifecycle, 3-step payment progression bar
- **Reports** — monthly cash flow BarChart, outstanding PieChart, PDF/Excel/image export
- **User Management** — create/edit admin and seller accounts, soft-delete, password reset via email
- **Settings** — company name, logo (base64 ≤50KB), pairs-per-carton, business preferences
- **Profile** — name, language, theme and password controls for all users

### Seller

- View assigned route and customers
- Record cash-in / cash-out transactions for assigned customers
- View account statements

### Multilingual

- English, Arabic (RTL), Urdu (RTL) — 372+ translation keys fully synced across all screens and PDF exports

---

## Tech Stack

| Layer | Technology |
| --- | --- |
| Mobile app | Flutter 3.5+ — Android APK only |
| State management | Riverpod (AsyncNotifier, StreamProvider) |
| Navigation | go_router with role-based redirect guards |
| Backend / Auth | Firebase (Firestore, Auth) — no Storage, no Cloud Functions |
| Design system | AppTokens, AppAnimations, AppSanitizer, AppInputFormatters |
| Charts | fl_chart (BarChart, LineChart, PieChart) |
| PDF export | `pdf` package + Isolate.run() — Arabic + Urdu fonts |
| Excel export | `excel` package |
| Print / Share | `printing` + `share_plus` |
| Image compression | `flutter_image_compress` (base64 logo) |
| Animations | `flutter_animate` + `shimmer` |

---

## Project Structure

```text
shoeserp/
├── app/                    # Flutter Android app
│   ├── lib/
│   │   ├── core/           # constants, l10n, router, theme, utils, design tokens
│   │   ├── models/         # Firestore data models
│   │   ├── providers/      # Riverpod state notifiers — all Firestore writes
│   │   ├── screens/        # all UI screens
│   │   └── widgets/        # 14 shared UI components (6 upgraded + 8 new)
│   └── android/            # Android-specific config
├── firestore.rules         # Security rules (docSizeOk, withinWriteRate)
├── firestore.indexes.json  # 17 composite indexes
└── firebase.json           # Firebase project config
```

---

## Setup

### Prerequisites

- Flutter SDK >=3.5.0 <4.0.0
- Android Studio / Android SDK (API 21+)
- Firebase project (`firebase login`)
- Java 17+

### Install dependencies

```bash
cd app
flutter pub get
```

### Firebase config

Place your `google-services.json` in `app/android/app/` (not committed — add via Firebase Console).

### Run (debug)

```bash
cd app
flutter run
```

### Build release APK

```bash
cd app
flutter build apk --release --split-per-abi
# Output: 3 APKs in app/build/app/outputs/flutter-apk/
#   app-armeabi-v7a-release.apk  (~27MB)
#   app-arm64-v8a-release.apk   (~29MB)
#   app-x86_64-release.apk      (~31MB)
```

---

## Backend Deployment

```bash
# Deploy Firestore rules and indexes
firebase deploy --only firestore:rules,firestore:indexes
```

> Note: No Cloud Functions deployment needed — user management runs entirely client-side via secondary FirebaseApp.

---

## Roles & Permissions

| Action | Admin | Seller |
| --- | --- | --- |
| Manage products / variants | ✅ | ❌ |
| Manage routes | ✅ | ❌ |
| Delete routes / shops / customers | ✅ | ❌ |
| Manage users | ✅ | ❌ |
| Delete users | ✅ (seller only, admin protected) | ❌ |
| View all customers | ✅ | Assigned route only |
| Create / update customers | ✅ | Assigned route only |
| Create transactions | ✅ | Assigned route only |
| View reports | ✅ | ❌ |
| Adjust inventory | ✅ | ❌ |
| Profile (name/theme/language/password) | ✅ | ✅ |

> Seller user creation requires assigned route allocation.
>
> `manager` role is treated as admin-equivalent for legacy data compatibility.

---

## Firestore Collections

| Collection | Purpose |
| --- | --- |
| `users` | Auth user profiles, roles, route assignments |
| `products` | Product catalogue |
| `product_variants` | SKU variants with `quantity_available` |
| `routes` | Delivery routes with assigned seller |
| `customers` | Customers / shops with running balance |
| `transactions` | Cash ledger entries per customer |
| `invoices` | Sale invoices and credit notes |
| `seller_inventory` | Seller-allocated stock per variant |
| `inventory_transactions` | Stock movement audit trail |
| `settings` | Global business settings |

---

## Code Quality

```bash
cd app
flutter analyze lib --no-pub   # must return "No issues found"
flutter test -r expanded
```

1. permission-denied:

- verify users/{uid}.active == true
- verify users/{uid}.role value is canonical (admin/seller/manager legacy)
- verify deployed firestore.rules

1. resource-exhausted:

- verify dashboard fallback cache is active
- reduce repeated dashboard refreshes
- monitor Firestore usage and index scan patterns

1. empty list views:

- check where+orderBy provider query
- add composite index and deploy firestore:indexes

## Production Signoff Checklist

1. Run flutter analyze lib --no-pub
2. Run flutter test -r expanded
3. Build release APK
4. Deploy firestore rules and indexes
5. Validate admin and seller write-path behavior on live project users

## v3.0.0 Enterprise Upgrade Highlights

- **Design system**: AppTokens (spacing, radii, elevation), AppAnimations (screenEntry, listEntry, pressable, successFlash, errorShake)
- **14 widgets**: 6 upgraded + 8 new — StatusBadge, AppSearchBar, FilterChipBar, ShimmerList, StatStripCard, ConfirmDialog, EmptyState, AppDateRangePicker — all with accessibility tooltips
- **5 list screens**: search, filter chips, shimmer loading, pull-to-refresh, staggered list animations, stat strips
- **7 forms**: PopScope dirty-check, AppSanitizer, haptic feedback on submit/error, unified validation
- **5 detail screens**: enriched with fl_chart charts, badges, grouped sections
- **PDF export**: all 4 functions run in `Isolate.run()` with sanitized string interpolation (S-08)
- **Session guard**: `AppLifecycleListener`, 8-hour admin hard session limit (S-10)
- **Base64 logo**: 256×256 + flutter_image_compress + ≤50KB cap (S-07)
- **Firestore rules**: `docSizeOk()` <50KB, `withinWriteRate()` 1s cooldown on all writes
- **Dark mode QA**: theme-aware colors throughout — no hardcoded Colors.white/grey
- **RTL QA**: EdgeInsetsDirectional throughout — no hardcoded left/right padding
- **Zero-cost Firebase**: Firestore + Auth only — no Storage, no Cloud Functions
- **Release**: v3.0.0+7, 3 split-per-abi APKs, tested on Samsung A56 + V2247

---

## Canonical Docs

- AGENTS.md
- CLAUDE.md
- SYSTEM_DEEP_DIVE_2026-03-27.md
- app/README.md
