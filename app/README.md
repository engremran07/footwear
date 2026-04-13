# FootWear ERP — Flutter App (v3.7.0+48)

Mobile-first Android + Web ERP for footwear distribution. Admins manage products, routes, inventory and users. Field sellers record shop transactions on assigned routes. Full multilingual support: English, Arabic, Urdu.

> **v3.7.0+48 (audit v14)** — fl_chart 1.2.0, share_plus 13.0.0, permission_handler 12.0.1, dart_jsonwebtoken 3.4.0, flutter_lints 6.0.0 upgraded. 30 lint issues fixed. CI standardised on Flutter 3.41.6. All StateProvider instances replaced (Riverpod 3 ban). Anti-Bypass Enforcement Matrix added.

---

## Requirements

- Flutter 3.41.6 (Dart >=3.11.0)
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

Place `google-services.json` in `android/app/` before running (obtain from Firebase Console — gitignored).

---

## Build

```bash
# Release APK (fat, universal — never split-per-abi)
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk

# Install to connected device
adb install -r build/app/outputs/flutter-apk/app-release.apk

# Web release
flutter build web --release
firebase deploy --only hosting
```

---

## Architecture

| Concern | Choice |
| --- | --- |
| State | flutter_riverpod 3.3.1 (`NotifierProvider`, `AsyncNotifierProvider`, `StreamProvider`) — **StateProvider is BANNED** |
| Navigation | go_router 17.2.0 with role-based redirect guards |
| Backend | Cloud Firestore (realtime streams) |
| Auth | Firebase Auth (email/password) via secondary `FirebaseApp` for user creation |
| Design system | AppTokens, AppAnimations, AppSanitizer, AppInputFormatters |
| Charts | fl_chart 1.2.0 (BarChart, LineChart, PieChart) |
| Exports (PDF) | `pdf` package + `Isolate.run()` — Arabic + Urdu fonts |
| Exports (Excel) | Custom xlsx writer (`excel_export.dart`) using `archive ^4.0.0` |
| Print / Share | `printing` + share_plus 13.0.0 (`SharePlus.instance.share(ShareParams(...))`) |
| Image compression | `flutter_image_compress` (base64 logo ≤50 KB) |
| Animations | `flutter_animate` + `shimmer` |

### Key directories

```text
lib/
├── core/
│   ├── constants/   # AppBrand (version, colours), Collections (Firestore names)
│   ├── l10n/        # app_locale.dart — EN / AR / UR (372+ keys)
│   ├── router/      # app_router.dart — all routes + auth guards
│   ├── theme/       # AppTheme, AppTokens, AppAnimations
│   └── utils/       # pdf_export (Isolate), excel_export, error_mapper, formatters, sanitizer
├── models/          # Firestore data models (fromJson / toJson)
├── providers/       # Riverpod notifiers — ALL Firestore writes happen here
├── screens/         # Full-page UI screens
└── widgets/         # Shared components with accessibility tooltips
```

---

## Screens & Routes

| Route | Screen | Access |
| --- | --- | --- |
| `/login` | Login | Public |
| `/` | Dashboard | All |
| `/profile` | Profile | All |
| `/routes` | Routes list | Admin |
| `/routes/new` | New route | Admin |
| `/routes/:id` | Route detail | Admin |
| `/routes/:id/edit` | Edit route | Admin |
| `/shops` | Shops list | All |
| `/shops/new` | New shop | All |
| `/shops/:id` | Shop detail + ledger | All |
| `/shops/:id/edit` | Edit shop | All |
| `/products` | Products list | Admin |
| `/products/new` | New product | Admin |
| `/products/:id` | Product detail + variants | Admin |
| `/products/:id/edit` | Edit product | Admin |
| `/products/:id/variants/new` | New variant | Admin |
| `/products/:id/variants/:vid/edit` | Edit variant | Admin |
| `/inventory` | Inventory screen | All |
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

Dashboard and inventory suppress transient permission-denied states during auth/profile stream warm-up. Role-scoped providers stay in loading or cached fallback until access is confirmed.

---

## State Management Rules

- **Never use `StateProvider`** — Riverpod 3.x removed it. Use `NotifierProvider<T, S>` with an explicit `Notifier` subclass.
- Every mutable state needs a `build()` method + explicit setter on the notifier.
- Write sites: `.notifier).state =` → `.notifier).set(value)`.
- Verify: `grep -rn "StateProvider\b" app/lib/ --include="*.dart"` → must return zero.

---

## Financial Pathways (never mix)

```text
Pathway 1 — SALE WITH STOCK
  CreateSaleInvoiceScreen → InvoiceNotifier.createSaleInvoice()
  Invoice + cash_out tx + optional cash_in tx + seller_inventory deduction (one atomic batch)
  USE WHEN: new goods delivered to shop, stock deduction required

Pathway 2 — CASH COLLECTION (old debt, no new goods)
  ShopDetailScreen → TransactionNotifier.create(type: 'cash_in')
  Cash_in ledger entry ONLY. No invoice. No stock movement.
  USE WHEN: collecting outstanding balance, no new delivery

VOID / RETURN (admin only)
  InvoiceNotifier.voidInvoice()
  Returns stock to inventory; issues one reversal transaction.
  Cash refund mode adds a second cash_out tx.
```

`shop.balance` is the sole monetary source of truth. It is updated **only** inside `InvoiceNotifier` or `TransactionNotifier` via atomic Firestore batch writes. Never write `shop.balance` from screens or widgets.

---

## Translations

All UI strings live in `lib/core/l10n/app_locale.dart`. Three locales:

- `en` — English (LTR)
- `ar` — Arabic (RTL) — PDF uses Noto Sans Arabic
- `ur` — Urdu (RTL) — PDF uses Noto Nastaliq Urdu

Locale is controlled by `appLocaleProvider` (a `NotifierProvider`, not `StateProvider`).

---

## Firestore Rules & Indexes

```bash
# From repo root
firebase deploy --only firestore:rules,firestore:indexes
```

Every `where(A) + orderBy(B)` query pair where `A != B` requires a composite index entry in `firestore.indexes.json`.

---

## Pre-Release Checklist

```bash
# 1 — Zero analyze issues (quote exact final line)
flutter analyze lib --no-pub

# 2 — All tests green (quote pass count)
flutter test -r expanded

# 3 — No StateProvider
grep -rn "StateProvider\b" lib/ --include="*.dart"

# 4 — Version sync (pubspec.yaml + app_brand.dart must match)
grep -E "^version:|appVersion|buildNumber" pubspec.yaml lib/core/constants/app_brand.dart

# 5 — APK (quote file size)
flutter build apk --release

# 6 — Web (confirm EXIT: $LASTEXITCODE = 0)
flutter build web --release
```

---

## Version History Highlights

- **v3.7.0+48 (2026-04-13):** Dep stack fully upgraded; 30 lint issues fixed; all 4 CI workflows on Flutter 3.41.6; StateProvider banned (Riverpod 3); Anti-Bypass Enforcement Matrix; audit 79→85/100
- **v3.6.0+47 (2026-04-13):** Riverpod 2→3 migration (flutter_riverpod 3.3.1, go_router 17.2.0); StateProvider converted to NotifierProvider; dead dev deps removed; 0 analyze issues
- **v3.5.0+43 (2026-04-11):** Governance layer; CI/CD hardened (11 hygiene gates, APK size gate); colour hygiene; auth-flow smoke tests
- **v3.4.0+30 (2026-04-07):** 20-agent CI/CD self-healing system; seller transaction rules restricted; 7h30m session warning; audit workflow
- **v3.3.7+28:** Admin 4-way auth pipeline (SA key → RS256 JWT → OAuth2 → Identity Toolkit REST)
- **v3.0.0+7:** Enterprise upgrade — design system, 14 widgets, 5 list screens, 7 forms, PDF isolate export, session guard, Firestore rules hardening
