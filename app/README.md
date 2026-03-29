# FootWear ERP — Flutter App

Mobile-first Android ERP for footwear distribution. Admins manage products, routes, inventory and users. Field sellers record customer transactions on assigned routes. Full multilingual support: English, Arabic, Urdu.

---

## Requirements

- Flutter 3.x
- Android SDK (API 21+)
- Java 17
- Firebase project with Firestore, Auth, and Functions enabled (no Storage needed)

---

## Getting Started

```bash
flutter pub get
flutter analyze lib --no-pub
flutter run
```

Place `google-services.json` in `android/app/` before running (obtain from Firebase Console — file is gitignored).

---

## Build

```bash
# Release APK (arm + arm64)
flutter build apk --release --target-platform android-arm,android-arm64
# Output: build/app/outputs/flutter-apk/app-release.apk

# Install to connected device
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

---

## Architecture

| Concern | Choice |
| --- | --- |
| State | Riverpod (`AsyncNotifier`, `StreamProvider`) |
| Navigation | go_router with role-based redirect guards |
| Backend | Cloud Firestore (realtime streams) |
| Auth | Firebase Auth (email/password) |
| Exports (PDF) | `pdf` package — Arabic + Urdu fonts embedded |
| Exports (Excel) | `excel` package |
| Print / Share | `printing` package |

### Key directories

```text
lib/
├── core/
│   ├── constants/   # AppBrand, AppCollections
│   ├── l10n/        # app_locale.dart — EN / AR / UR translations
│   ├── router/      # app_router.dart — all routes + auth guards
│   ├── theme/       # AppTheme
│   └── utils/       # pdf_export, excel_export, error_mapper, formatters
├── models/          # Firestore data models (fromJson / toJson)
├── providers/       # Riverpod notifiers — all Firestore writes happen here
├── screens/         # Full-page UI screens
└── widgets/         # Reusable UI components
```

---

## Screens

| Route | Screen | Access |
| --- | --- | --- |
| `/login` | Login | Public |
| `/` | Dashboard | All |
| `/profile` | Profile | All |
| `/routes` | Routes list | Admin |
| `/routes/:id` | Route detail | Admin |
| `/shops` | Shops list | All |
| `/shops/:id` | Shop detail + ledger | All |
| `/customers` | Customers list | All |
| `/customers/:id` | Customer detail + ledger | All |
| `/products` | Products list | Admin |
| `/products/:id` | Product detail + variants | Admin |
| `/inventory` | Inventory screen | Admin |
| `/invoices` | Invoices list | All |
| `/invoices/:id` | Invoice detail | All |
| `/reports` | Reports (PDF / Excel) | Admin |
| `/settings` | Settings | Admin |

---

## Roles

| Role value | Access level |
| --- | --- |
| `admin` | Full access |
| `manager` | Admin-equivalent (legacy) |
| `seller` | Assigned route only — read + create transactions |

Seller accounts must be provisioned by admin with assigned route.

---

## Translations

All UI strings live in `lib/core/l10n/app_locale.dart`. Three locales:

- `en` — English (LTR)
- `ar` — Arabic (RTL) — PDF uses Noto Sans Arabic
- `ur` — Urdu (RTL) — PDF uses Noto Nastaliq Urdu

Switch locale at runtime via `appLocaleProvider`.

---

## Firestore Rules & Indexes

Managed at repo root:

```bash
# From repo root
firebase deploy --only firestore:rules,firestore:indexes
```

---

## Pre-Release Checklist

```bash
flutter analyze lib --no-pub        # No issues found
flutter test -r expanded            # All tests pass
flutter build apk --release         # APK builds cleanly
```
