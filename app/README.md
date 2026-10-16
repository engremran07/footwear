# FootWear ERP — Flutter App (v3.9.79+705)

Mobile-first Android + Web ERP for footwear distribution. Admins manage products, routes, inventory and users. Field sellers record shop transactions on assigned routes. Full multilingual support: English, Arabic, Urdu.

> **v3.7.5+53 (2026-04-15)** — Current app baseline includes the post-audit hardening pass: stricter provider guards, tighter invoice and Firestore validation, export query caps, model utility cleanup, theme-safe loading widgets, and workflow normalization on Flutter 3.41.6 with expanded test reporting.

Workspace backup restore is tenant-scoped. Tenant admins merge encrypted backup records into their own workspace without deleting records missing from the archive; selected platform super-admins retain replacement/pruning access for the active support workspace. Unsupported role values are blocked from business navigation and show localized recovery guidance.

Status chips display localized text and use high-contrast state colors when that theme is selected.

Encrypted backup export and Google Drive upload are separate actions; Drive uploads do not create duplicate local archives. Restore behavior follows workspace scope, and local backup files can be deleted from the device restore picker. Workspace archival revokes member access records before the workspace is marked archived.
Workspace-admin and seller sign-in registers device access through tenant/user-scoped queries and links each application session to its registered device slot. Workspace create/edit failures remain visible in the form, and the workspace list tolerates temporary auth-profile loading.
Sign-in stays on the login screen until access registration completes. Seller devices use pending approval when workspace pairing is enabled; workspace administrators register without seller approval and use shared platform caps, defaulting to three devices and two sessions if the platform policy document is absent. Administrators can remove, block, or reset devices with related active-session revocation. Sessions renew while foregrounded and show a five-minute expiry warning. These records support client-side device/seat controls; Firestore Rules do not bind requests to an active session ID under the current Spark architecture.

Invoice creation supports stock sales, workspace-enabled non-stock catalog sales, and cash receipt invoices. Non-stock invoices preserve catalog item details without reducing inventory. Receipt numbering, receipt ledger entries, and shop balance changes are atomic and workspace-scoped. Workspace administrators configure bilingual invoice headers; generated PDFs use the header snapshot stored on each invoice. Shop detail provides a preselected invoice entry point while retaining ledger-only cash-in.

Non-stock invoicing is disabled for new and legacy workspaces unless an administrator explicitly enables it. Sale and credit-note creation commit the workspace invoice counter, invoice, ledger, shop balance, and stock movements in one Firestore transaction. Firestore Rules require invoice/ledger/shop links for sales, receipts, and credit notes; seller sales also validate the exact balance delta. Voiding a credit note reverses its stock movement and the original invoice's cumulative credit total. Transaction descriptions accept multiline notes.

Access limits are role-scoped: sellers use each workspace's configured cap, workspace admins share the cap configured by the platform super-admin, and super-admins use separate platform-only limits of two devices and one active session. Device/session rules are not a server authorization boundary under the current Spark architecture.

Invoice voiding commits status, shop balance, inventory restoration, and reversal rows atomically. Receipt counter values are verified by Firestore Rules. Invoice PDFs localize receipt methods, distinguish non-stock lines, and paginate with dynamic page numbering.

---

Workspace creation does not wait for a global user list. Owner choices during edits are limited to users in the selected workspace, and full workspace edits require active platform-super-admin access. Save failures remain in the dialog with the correct mapped error; launcher artwork is generated from one source with matching Android/web scale.

## Requirements

- Flutter 3.41.6 (Dart >=3.11.0)
- Android SDK (API 21+)
- Java 17
- Firebase project with Firestore and Auth enabled (no Storage, no Cloud Functions needed)
- Workspace ownership: each tenant has its own branding and seller device/session limits; workspace-admin caps are platform-configured

---

## Getting Started

```bash
flutter pub get
flutter analyze lib --no-pub
flutter run
```

Place `google-services.json` in `android/app/` before running (obtain from Firebase Console — gitignored).

Google Drive backup requires a Google OAuth web client and Android client for package `footwear.pk.com`. Configure the release SHA-1 in Google Cloud/Firebase, then provide `GOOGLE_DRIVE_CLIENT_ID` and `GOOGLE_DRIVE_SERVER_CLIENT_ID` as `--dart-define` values for web and Android builds. The app requests only the `drive.file` scope.

---

## Build

```bash
# Sync or bump the release version first.
grep -E "^version:|appVersion|buildNumber" pubspec.yaml lib/core/constants/app_brand.dart

# Web release
flutter build web --release
firebase deploy --only hosting

# Release APK (split-per-ABI binaries for device delivery)
flutter build apk --release --split-per-abi --dart-define=USE_PLAY_INTEGRITY=true
# Output: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
#         build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
#         build/app/outputs/flutter-apk/app-x86_64-release.apk
#         build/app/outputs/flutter-apk/app-release.apk

# From the repo root, deploy Firestore rules/indexes before commit/push completes.
# firebase deploy --only firestore:rules,firestore:indexes

# Install to connected device
adb push build/app/outputs/flutter-apk/app-arm64-v8a-release.apk /sdcard/Download/
adb install --streaming -r /sdcard/Download/app-arm64-v8a-release.apk
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

Super-admin is platform-only by default: workspace metadata is global, but workspace business records are unavailable until one workspace is explicitly selected with a support reason. The active context is visible in the shell and start/end events are written to append-only `platform_access_logs`; Firestore rules enforce this boundary.

Platform super-admin accounts are provisioned out of band. The client never embeds service-account credentials or changes another user's Firebase Auth credentials. Administrators may send password-reset emails; account owners control password and email changes.

| Role value | Access level |
| --- | --- |
| `admin` | Full access |
| `manager` | Admin-equivalent (legacy) |
| `seller` | Assigned route only — read + create transactions |

Dashboard and inventory suppress transient permission-denied states during auth/profile stream warm-up. Role-scoped providers stay in loading or cached fallback until access is confirmed.

Workspace business access for platform super-admins expires after 8 hours and remains enforced by Firestore rules. Mutations require a concrete tenant; local admins manage seller accounts only; seller-stock reductions must match a same-batch invoice deduction. Financial corrections preserve prior values, actor, and reason. Exports cursor-page to exhaustion; tenant-admin restore is upsert-only, while selected super-admin restore can prune after upserting. Plaintext legacy backup archives are rejected. Transient token-refresh failures preserve the session, and Firebase initialization failure shows a retry state.

---

## State Management Rules

- **Never use `StateProvider`** — Riverpod 3.x removed it. Use `NotifierProvider<T, S>` with an explicit `Notifier` subclass.
- Every mutable state needs a `build()` method + explicit setter on the notifier.
- Write sites: `.notifier).state =` → `.notifier).set(value)`.
- Verify: `grep -rn "StateProvider\b" app/lib/ --include="*.dart"` → must return zero.

---

## Financial Pathways (never mix)

```text
Pathway 1 — STOCK SALE
  CreateSaleInvoiceScreen → InvoiceNotifier.createSaleInvoice()
  Invoice + cash_out tx + optional cash_in tx + seller_inventory deduction (one atomic batch)
  USE WHEN: new goods delivered and stock must decrease

Pathway 2 — NON-STOCK SALE
  CreateSaleInvoiceScreen → InvoiceNotifier.createSaleInvoice(fulfillmentMode: non_stock)
  Invoice + ledger writes + shop balance update; no inventory deduction
  USE WHEN: recording a catalog sale without stock movement and workspace setting allows it

Pathway 3 — CASH RECEIPT INVOICE
  CreateSaleInvoiceScreen → InvoiceNotifier.createCashReceipt()
  Receipt sequence + invoice + cash_in tx + shop balance update (one atomic transaction)
  USE WHEN: collecting old debt and issuing a receipt document

Pathway 4 — LEDGER-ONLY CASH COLLECTION
  ShopDetailScreen → TransactionNotifier.create(type: 'cash_in')
  Cash_in ledger entry only. No invoice. No stock movement.
  USE WHEN: collecting payment without a receipt document

VOID / RETURN (admin only)
  InvoiceNotifier.voidInvoice()
  Returns stock only for stock-backed invoices; issues one reversal transaction.
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
# 1 — Version sync / bump
grep -E "^version:|appVersion|buildNumber" pubspec.yaml lib/core/constants/app_brand.dart

# 2 — Zero analyze issues (quote exact final line)
flutter analyze lib --no-pub

# 3 — All tests green (quote pass count)
flutter test -r expanded

# 4 — No StateProvider
grep -rn "StateProvider\b" lib/ --include="*.dart"

# 5 — Web (confirm EXIT: $LASTEXITCODE = 0)
flutter build web --release

# 6 — Hosting deploy
firebase deploy --only hosting

# 7 — APK (quote file size)
flutter build apk --release

# 8 — Firestore deploy (run from repo root)
# firebase deploy --only firestore:rules,firestore:indexes
```

---

## Version History Highlights

- **v3.7.0+48 (2026-04-13):** Dep stack fully upgraded; 30 lint issues fixed; all 4 CI workflows on Flutter 3.41.6; StateProvider banned (Riverpod 3); Anti-Bypass Enforcement Matrix; audit 79→85/100
- **v3.6.0+47 (2026-04-13):** Riverpod 2→3 migration (flutter_riverpod 3.3.1, go_router 17.2.0); StateProvider converted to NotifierProvider; dead dev deps removed; 0 analyze issues
- **v3.5.0+43 (2026-04-11):** Governance layer; CI/CD hardened (11 hygiene gates, APK size gate); colour hygiene; auth-flow smoke tests
- **v3.4.0+30 (2026-04-07):** 20-agent CI/CD self-healing system; seller transaction rules restricted; 7h30m session warning; audit workflow
- **v3.3.7+28:** Legacy admin Auth management used an embedded service-account signing design; that insecure client pathway was removed in v3.9.52+91.
- **v3.0.0+7:** Enterprise upgrade — design system, 14 widgets, 5 list screens, 7 forms, PDF isolate export, session guard, Firestore rules hardening
