# FootWear ERP

A mobile-first enterprise resource planning system for footwear distribution businesses. Built with Flutter (Android APK) and Firebase as the backend. Designed for route-based sales operations where an admin manages products, inventory, and sellers, while field sellers record customer transactions on their assigned routes.

---

## Features

### Admin

- **Dashboard** — live stats: revenue, outstanding balances, inventory levels
- **Products & Variants** — manage SKUs with size/color variants, carton/dozen/pair stock tracking
- **Routes** — define delivery routes and assign sellers
- **Customers & Shops** — full CRUD with balance ledger per customer
- **Inventory** — warehouse stock allocation and adjustment
- **Transactions** — cash-in / cash-out ledger with running balance
- **Reports** — account statement, seller summary report — exportable as PDF, Excel, or image
- **User Management** — create/edit admin and seller accounts
- **Settings** — company name, pairs-per-carton, business preferences

### Seller

- View assigned route and customers
- Record cash-in / cash-out transactions for assigned customers
- View account statements

### Multilingual

- English, Arabic (RTL), Urdu (RTL) — fully synced across all screens and PDF exports

---

## Tech Stack

| Layer | Technology |
| --- | --- |
| Mobile app | Flutter 3.x — Android APK only |
| State management | Riverpod |
| Navigation | go_router |
| Backend / Auth | Firebase (Firestore, Auth, Functions, Storage) |
| PDF export | `pdf` package — Noto Arabic + Noto Nastaliq Urdu fonts |
| Excel export | `excel` package |
| Print / Share | `printing` package |

---

## Project Structure

```text
shoeserp/
├── app/                    # Flutter Android app
│   ├── lib/
│   │   ├── core/           # constants, l10n, router, theme, utils
│   │   ├── models/         # Firestore data models
│   │   ├── providers/      # Riverpod state notifiers
│   │   ├── screens/        # all UI screens
│   │   └── widgets/        # shared UI components
│   └── android/            # Android-specific config
├── functions/              # Firebase Cloud Functions
├── firestore.rules         # Firestore security rules
├── firestore.indexes.json  # Composite indexes
└── firebase.json           # Firebase project config
```

---

## Setup

### Prerequisites

- Flutter SDK 3.x
- Android Studio / Android SDK
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
flutter build apk --release --target-platform android-arm,android-arm64
# Output: app/build/app/outputs/flutter-apk/app-release.apk
```

---

## Backend Deployment

```bash
# Deploy Firestore rules and indexes
firebase deploy --only firestore:rules,firestore:indexes

# Deploy Cloud Functions
cd functions
npm install
firebase deploy --only functions
```

---

## Roles & Permissions

| Action | Admin | Seller |
| --- | --- | --- |
| Manage products / variants | ✅ | ❌ |
| Manage routes | ✅ | ❌ |
| Manage users | ✅ | ❌ |
| View all customers | ✅ | Assigned route only |
| Create / update customers | ✅ | Assigned route only |
| Create transactions | ✅ | Assigned route only |
| View reports | ✅ | ❌ |
| Adjust inventory | ✅ | ❌ |

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

## Canonical Docs

- AGENTS.md
- CLAUDE.md
- SYSTEM_DEEP_DIVE_2026-03-27.md
- app/README.md
