# FootWear ERP — Flutter App (v3.0.0)

Mobile-first Android ERP for footwear distribution. Admins manage products, routes, inventory and users. Field sellers record customer transactions on assigned routes. Full multilingual support: English, Arabic, Urdu.

> **v3.0.0** — Enterprise upgrade with design system, animations, hardened security, Isolate PDF export, session guard, dark mode + RTL QA.

---

## Requirements

- Flutter >=3.5.0 <4.0.0
- Android SDK (API 21+)
- Java 17
- Firebase project with Firestore and Auth enabled (no Storage, no Cloud Functions needed)

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
# Release APKs (split per ABI)
flutter build apk --release --split-per-abi
# Output: build/app/outputs/flutter-apk/
#   app-armeabi-v7a-release.apk  (~27MB)
#   app-arm64-v8a-release.apk   (~29MB)
#   app-x86_64-release.apk      (~31MB)

# Install to connected device
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

---

## Architecture

| Concern | Choice |
| --- | --- |
| State | Riverpod (`AsyncNotifier`, `StreamProvider`) |
| Navigation | go_router with role-based redirect guards |
| Backend | Cloud Firestore (realtime streams) |
| Auth | Firebase Auth (email/password) |
| Design system | AppTokens, AppAnimations, AppSanitizer, AppInputFormatters |
| Charts | fl_chart (BarChart, LineChart, PieChart) |
| Exports (PDF) | `pdf` package + `Isolate.run()` — Arabic + Urdu fonts |
| Exports (Excel) | `excel` package |
| Print / Share | `printing` + `share_plus` |
| Image compression | `flutter_image_compress` (base64 logo ≤50KB) |
| Animations | `flutter_animate` + `shimmer` |

### Key directories

```text
lib/
├── core/
│   ├── constants/   # AppBrand, AppCollections
│   ├── l10n/        # app_locale.dart — EN / AR / UR (372+ keys)
│   ├── router/      # app_router.dart — all routes + auth guards
│   ├── theme/       # AppTheme, AppTokens, AppAnimations
│   └── utils/       # pdf_export (Isolate), excel_export, error_mapper, formatters, sanitizer
├── models/          # Firestore data models (fromJson / toJson)
├── providers/       # Riverpod notifiers — all Firestore writes happen here
├── screens/         # Full-page UI screens (login, dashboard, 5 lists, 7 forms, 5 details, reports)
└── widgets/         # 14 shared components (6 upgraded + 8 new) with accessibility tooltips
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

Dashboard and inventory flows must suppress transient permission-denied states during auth/profile stream warm-up. Admin-only providers should be role-guarded before subscription, and seller/admin startup for `/` and `/inventory` should be verified after related edits.

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

If the release includes both web and APK:

- keep `pubspec.yaml` version and `AppBrand.versionDisplay` aligned first
- rebuild web and APK from that same versioned source tree
- avoid immutable Hosting cache for Flutter web shell files
- verify user-facing About/version/contact data matches on both surfaces

---

## v3.0.0 Enterprise Features

- **Design tokens**: `AppTokens` (spacing s2–s48, radii brSM/brMD/brLG, elevation), `AppAnimations` extension with screenEntry(), listEntry(i), pressable(), successFlash(), errorShake()
- **14 widgets**: StatusBadge, AppSearchBar, FilterChipBar, ShimmerList, StatStripCard, ConfirmDialog, EmptyState, AppDateRangePicker — all with Semantics/Tooltip
- **5 enriched list screens**: search bar, filter chips, shimmer placeholders, pull-to-refresh, staggered entry animations, stat summary strips
- **7 standardized forms**: PopScope dirty-check, AppSanitizer input cleaning, haptic feedback (vibrate on error, mediumImpact on save)
- **5 enriched detail screens**: fl_chart charts, status badges, grouped card sections
- **PDF isolate export**: all 4 PDF functions use `Isolate.run()`, font bytes pre-loaded on main isolate, `_s()` sanitizer for all interpolated strings (S-08)
- **Session guard**: `AppLifecycleListener` replaces deprecated observer, 8h admin hard timeout (S-10)
- **Base64 logo**: 256×256 + flutter_image_compress + ≤50KB Firestore cap (S-07)
- **Firestore rules**: `docSizeOk()` <50KB on all creates/updates, `withinWriteRate()` 1s cooldown
- **Dark mode**: theme-aware colors, no hardcoded Colors.white/grey
- **RTL**: EdgeInsetsDirectional throughout, no hardcoded left/right
- **Security**: deny-by-default rules, admin defense-in-depth, provider write guards, `_normalizePath()` in router
- **Release**: v3.0.0+7, 3 split-per-abi APKs, tested Samsung A56 (API 36) + V2247 (API 34)
