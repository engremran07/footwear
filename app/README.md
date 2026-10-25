# FootWear ERP — Flutter App (v3.10.3+1114)

Mobile-first Android + Web ERP for footwear distribution. Admins manage products, routes, inventory and users. Field sellers record shop transactions on assigned routes. Full multilingual support: English, Arabic, Urdu.

## v3.10.3 Workspace Roster Completeness

Active and inactive workspace user lists now sort the queried profiles on-device
instead of using Firestore `orderBy(display_name)`. That ordering omits legacy
documents where the optional display-name field is absent. Seat reconciliation
uses the same complete tenant-scoped active roster, so it no longer writes an
under-count. This query-only hotfix does not change Firestore Rules or indexes;
the Rules/indexes were deployed with v3.10.2.

Verification for `3.10.3+1114`: full Flutter suite `01:21 +623: All tests
passed!`; `flutter analyze lib --no-pub`: `No issues found! (ran in 15.3s)`;
`dart analyze test/`: `No issues found!`; Firestore Rules Emulator:
`146 passing (37s)`. Web `EXIT: 0`; Hosting deployment reported
`Deploy complete!`. Split APKs built at 30.7/32.2/33.6 MB. ARM64 installed on
`R5GL22RGT9V` (`Success`, versionCode `3103414`).

## v3.10.2 Workspace and Receipt Improvements

Workspace administrators can create admin and seller accounts and promote or
demote eligible same-workspace admin/seller accounts. They cannot alter the
permanent workspace owner or platform roles, or deactivate peer administrators.
Seat changes remain atomic with profile changes. Selected platform super-admins
can reconcile a workspace's stored seat counter against its live active roster;
the free-tier cap remains 10 non-platform members.

Workspace logos are resized locally on the device, preserving transparency and
reducing dimensions until the encoded logo fits the Firestore limit. This uses
deterministic image processing and does not require an AI model or network
service.

Cash-receipt detail and PDFs use a compact bilingual table layout. Receipt PDFs
are deliberately single-page and omit the account-balance-movement block; the
underlying receipt, ledger, and shop-balance transaction remains atomic and
unchanged. Invoice, receipt, and statement documents continue using the
configured English-Arabic or English-Urdu language pair and shared compact
workspace header.

Verification for `3.10.2+1113`: full Flutter suite `01:26 +623: All tests
passed!`; `flutter analyze lib --no-pub`: `No issues found! (ran in 103.6s)`;
`dart analyze test/`: `No issues found!`; Firestore Rules Emulator:
`145 passing (31s)`. Web `EXIT: 0`; Hosting and Firestore Rules/indexes
deployments reported `Deploy complete!`. Split APKs built at 30.7/32.2/33.6
MB. ARM64 installed on `R5GL22RGT9V` (`Success`, versionCode `3103313`).

> **v3.9.81+707 (2026-10-22)** — Firebase Authentication remains the only sign-in mechanism; app-managed device pairing and custom session approvals are removed. Workspace-admin CRUD and tenant-scoped financial safeguards remain.

Unreleased local source hardening (2026-10-24): Firestore Rules permit
invoice/transaction idempotency reads of missing documents only for an active
profile in a concrete active tenant, while preserving selected-workspace support
context for super-admins. First-time seller-inventory reads are admin-equivalent
only; the workspace-creation flow can read missing settings only before the
tenant document exists. Seller invoice authorization avoids redundant
route/shop checks to keep atomic sale writes within the Rules expression budget.
Admins with no available stock now see localized allocation and non-stock-mode
guidance. Local Rules Emulator: `128 passing`; focused invoice widget tests:
`00:01 +2: All tests passed!`. Production Rules deployment and release
operations were not performed.

The v3.9.84+710 backup follow-up reads workspace settings by the selected
tenant document ID, separates selectable backup categories from serialized
collection keys, and verifies seller inventory ownership in imported archives.
Selected super-admin backup remains workspace-scoped; seller restore remains
limited to eligible own cash transactions. Role tests: `00:07 +16: All tests
passed!`; full suite: `01:15 +603: All tests passed!`; both analyzers are clean;
Rules Emulator: `132 passing (48s)`. Firestore Rules/indexes deployed. Split APKs built (30.4/32.0/33.4 MB); the
ARM64 APK installed on `R5GL22RGT9V` (`Success`, versionCode `3101110`).
Hosting deployment and Git publication remain pending because pushing to
`main` triggers the Hosting workflow.

In v3.9.85+711, workspace administrators can select English-Arabic
(default) or English-Urdu as the paired language for financial PDFs. New
invoice snapshots preserve that choice; invoice, receipt, account statement,
seller, multi-shop, and flat financial-report PDFs use paired labels. Ledger
summary and table cells render each language line with explicit text direction.
Seller invoice Rules validate provider-shaped optional header fields and bind
the saved language pair to the active workspace setting.

Route, shop, product, and variant edit forms wait for the active profile and
matching record before enabling inputs or saving. Errors can be retried,
missing records are not presented as empty forms, and existing values are
prefilled before saving. Provider role/tenant checks are unchanged.

Inventory add/transfer dialogs show loading, empty, and retryable error states
for product, variant, and seller choices. The inventory screen waits for
workspace settings before showing quantity actions, so a settings failure
cannot silently assume the default carton size. Stock writes remain in the
existing provider notifiers.

The 2026-10-23 screen-state sweep also groups invoice summary amounts by
currency, waits for route scope before applying currency-filtered shop lists,
surfaces invoice-profile and notification bulk-action failures, and resets
profile dirty state when the saved name is restored. Stat-card entrance motion
respects reduced-motion settings. A follow-up source review and focused tests
cover report-export progress/errors, user route-option retries, shop-form route
query retry, backup/flush workspace readiness and errors, and tenant-admin
metadata-only presentation. The screen register covers all 32 registered
route patterns. The 2026-10-24 follow-up also makes every shared animation
preset honor reduced-motion settings while keeping press actions available.
Release v3.9.83+709 passed the full Flutter suite
(`02:13 +567: All tests passed!`) and both analyzers. Authenticated
role/locale/theme visual acceptance remains pending.

The 2026-10-24 login follow-up caps the narrow form width to the lesser of its
420-logical-pixel design maximum and the available viewport. This prevents
invalid constraints when the window is wider than a phone but still below the
navigation-rail breakpoint. The regression covers six widths in English,
Arabic, and Urdu; a public local-browser render was checked after the fix.
Authenticated role/theme review and Android device acceptance remain pending.

The 2026-10-24 router motion follow-up also makes the custom route fade/scale
and form slide transitions return their page child directly when
`MediaQuery.disableAnimations` is enabled. Enabled-motion behavior is retained.
Router tests: `00:05 +6: All tests passed!`; current full suite:
`01:01 +589: All tests passed!`; `flutter analyze lib --no-pub`:
`No issues found! (ran in 102.3s)`; `dart analyze test/`: `No issues found!`.
The debug APK attempt failed at `:app:mergeDebugJavaResource` with insufficient
system resources; no release APK or device install was produced.

The 2026-10-24 unreleased data-freshness pass keeps invoice-header and workspace
settings forms synchronized with live Firestore snapshots while preserving
unsaved edits. Shops, invoices, shop ledgers, and settings support pull-to-
refresh. Shop flow totals are grouped by route currency and show full values;
invoice Pending filters outstanding sales. Voided invoice-linked entries and
their reversals are hidden from customer statements/exports, but remain in
admin transaction history; collected cash remains visible as customer credit
when applicable. Voids query all tenant-scoped ledger rows linked by invoice
ID, including settlement transactions created by older app versions; current
settlement writes also append their IDs to the invoice atomically. Receipt
PDFs emphasize the received amount and provide
payment, balance, received-by, and signature details. Ledger summary labels
follow the active RTL direction, and statement/report PDFs use the complete
workspace invoice header. Focused tests and both analyzers pass; full-suite and
rendered device acceptance remain pending. The final full suite reports
`01:08 +599: All tests passed!`; the invoice-void suite reports
`00:00 +22: All tests passed!`. No production deployment or release operation
was performed for this unreleased source change.

Account-statement exports resolve the selected shop's route currency before
building both spreadsheet rows and PDF output. Seller reports keep transaction
rows in their route currency, assign current balances to the shop's current
route currency, and group PDF grand totals by currency. This prevents SAR and
PKR values from being added under one label.

For v3.9.83+709, the web release built with `EXIT: 0` and deployed to
Firebase Hosting. Split-per-ABI APKs were built (ARMv7 30.3 MB, ARM64 31.9 MB,
x86_64 33.4 MB); the ARM64 artifact was copied to and installed on
`R5GL22RGT9V` (`Success`, versionName `3.9.83`, versionCode `3101009`).
Firestore Rules/index deployment completed; the source Rules and indexes had
no delta, and remote-only indexes and field overrides were preserved.

Workspace backup restore is tenant-scoped. Tenant admins merge encrypted backup records into their own workspace without deleting records missing from the archive; selected platform super-admins retain replacement/pruning access for the active support workspace. Sellers can save encrypted assigned-route archives through the phone's system file picker and later restore only their own eligible, unlinked cash-in/cash-out rows. Each restored ledger row and same-route shop-balance delta commit atomically; invoices, inventory, and other sellers' transactions are not restored by this path. A saved file may be explicitly uploaded to configured Google Drive when online; background synchronization is not provided. Unsupported role values are blocked from business navigation and show localized recovery guidance.

Workspace data flush/reset actions are disabled. The legacy plaintext
whole-project export, whole-collection restore, and direct shop-balance reset
scripts also fail closed; these client-side operations cannot preserve linked
financial and inventory records atomically. Workspace documents use the
archive/restore lifecycle, and Firestore Rules deny hard deletion of a tenant
root. Use only the encrypted, workspace-scoped app backup for supported
restore operations.

Platform super-admins can restore an archived workspace from the workspace
list by selecting it with a reason of at least 10 characters and confirming
the lifecycle action. The archive/restore provider updates only the tenant
status fields; member profiles are preserved. Firestore Rules continue to
deny business access until the workspace is active.

Status chips display localized text and use high-contrast state colors when that theme is selected.

Encrypted backup export and Google Drive upload are separate actions; Drive uploads do not create duplicate local archives. Restore behavior follows workspace scope, and local backup files can be deleted from the device restore picker. Workspace archival preserves member profiles; inactive tenant status blocks business access until a selected super-admin restores the workspace.
Firebase Authentication is the only sign-in mechanism. Successful sign-in is followed by active-profile, role, and tenant validation; no app-managed device registration, pairing approval, slot registration, renewal, or session-security gate is required. Workspace create/edit failures remain visible in the form, and the workspace list tolerates temporary auth-profile loading.

Business-data Rules also require the tenant itself to be active; an active member profile cannot access business documents in an inactive workspace. Shop creation must start at a zero balance without seeded transaction-summary fields. Standalone ledger entries are validated against the same atomic shop/balance update, while invoice batches retain multi-row aggregate balance checks.

Invoice creation supports stock sales, workspace-enabled non-stock catalog sales, and cash receipt invoices. Non-stock invoices preserve catalog item details without reducing inventory. Receipt numbering, receipt ledger entries, and shop balance changes are atomic and workspace-scoped. Workspace administrators configure bilingual invoice headers; generated PDFs use the header snapshot stored on each invoice. Shop detail provides a preselected invoice entry point while retaining ledger-only cash-in.

Non-stock invoicing is disabled for new and legacy workspaces unless an administrator explicitly enables it. Sale and credit-note creation commit the workspace invoice counter, invoice, ledger, shop balance, and stock movements in one Firestore transaction. Firestore Rules require invoice/ledger/shop links for sales, receipts, and credit notes; seller sales also validate the exact balance delta. Voiding a credit note reverses its stock movement and the original invoice's cumulative credit total. Transaction descriptions accept multiline notes.

Standalone cash-in/cash-out corrections use audited soft deletion only. The provider records the actor, reverses the exact shop-balance delta, and clears the cached latest-transaction summary when it points to the deleted row, all in the same batch. Workspace admins may perform this correction; sellers cannot delete transactions, hard deletion is denied, and invoice-linked transactions remain immutable outside invoice void/credit-note flows.

Invoice voiding commits status, shop balance, inventory restoration, and reversal rows atomically. Receipt counter values are verified by Firestore Rules. Invoice PDFs localize receipt methods, distinguish non-stock lines, and paginate with dynamic page numbering.

---

Workspace creation does not wait for a global user list. Owner choices during edits are limited to users in the selected workspace, and full workspace edits require active platform-super-admin access. Workspace administrators retain tenant-scoped business settings and CRUD permissions; no device or custom session caps are configured. Save failures remain in the dialog with the correct mapped error; launcher artwork is generated from one source with matching Android/web scale.

## Requirements

- Flutter 3.41.6 (Dart >=3.11.0)
- Android SDK (API 21+)
- Java 17
- Firebase project with Firestore and Auth enabled (no Storage, no Cloud Functions needed)
- Workspace ownership: each tenant has its own branding and business settings

---

## Getting Started

```bash
flutter pub get
flutter analyze lib --no-pub
flutter run --dart-define=use_arabic=true
flutter test -r expanded --dart-define=use_arabic=true
```

The VS Code Android, Chrome, and test launch configurations also enable the
Arabic shaping flag. Keep this flag on every Flutter run, test, and build that
can generate PDFs; without it the PDF renderer reorders RTL text without
shaping Arabic-script letters. The shared PDF builder now fails closed with a
localized error instead of exporting unshaped RTL text when the flag is absent.
PDF, print, share, and PNG exports reuse the same generated PDF bytes.

PDFs embed Noto Sans Arabic for Arabic and Urdu. Urdu PDFs use a readable
Naskh-style font; full Nastaliq OpenType shaping is not supported by the
current PDF renderer. The app UI uses Noto Nastaliq Urdu. XLSX preserves
Unicode text and RTL worksheet direction, but fonts are selected by the
spreadsheet application and are not embedded in the file.

Invoice, cash-receipt, account-statement, and seller-report PDFs reuse one
workspace brand header: English business information is left-aligned and the
selected Arabic/Urdu information is right-aligned independently of app locale.
Current workspace logo bytes take priority, with an invoice/receipt snapshot
fallback when they are unavailable and the configured logo visibility allows
it. Cash receipts use an A5 page and remain single-page. Font metadata tests
and rendered-layout checks are separate; an embedded font does not prove
correct glyph appearance. Rows use an explicit LTR `Directionality` wrapper
because the page may be RTL and `pdf` 3.12.0 `Row` has no direction argument.
The current Urdu renderer remains Naskh-style; a Nastaliq prototype has not
passed logo, text-extraction, pagination, and cross-platform report parity
gates.

Place `google-services.json` in `android/app/` before running (obtain from Firebase Console — gitignored).

Google Drive backup requires a Google OAuth web client and Android client for package `footwear.pk.com`. Configure the release SHA-1 in Google Cloud/Firebase, then provide `GOOGLE_DRIVE_CLIENT_ID` and `GOOGLE_DRIVE_SERVER_CLIENT_ID` as `--dart-define` values for web and Android builds. The app requests only the `drive.file` scope.

---

## Build

```bash
# Sync or bump the release version first.
grep -E "^version:|appVersion|buildNumber" pubspec.yaml lib/core/constants/app_brand.dart

# Web release
flutter build web --release --dart-define=use_arabic=true
firebase deploy --only hosting

# Release APK (split-per-ABI binaries for device delivery)
flutter build apk --release --split-per-abi --dart-define=USE_PLAY_INTEGRITY=true --dart-define=use_arabic=true
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
| Exports (PDF) | `pdf` package + `Isolate.run()` — Arabic shaping enabled with `--dart-define=use_arabic=true` |
| Exports (Excel) | Custom xlsx writer (`excel_export.dart`) using `archive ^4.0.0` |
| Print / Share | `printing` + share_plus 13.0.0 (`SharePlus.instance.share(ShareParams(...))`) |
| Image compression | `flutter_image_compress` (base64 logo ≤50 KB) |
| Animations | `flutter_animate` + `shimmer` |

Shared filter chips use the 48-logical-pixel minimum target token. All shared
animation presets, empty/error illustrations, stat-card transitions, and
status-chip transitions respect `MediaQuery.disableAnimations`. Balance badge
semantics follow the selected English, Arabic, or Urdu locale.

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
| `admin` | Full business access within the assigned scope |
| `manager` | Admin-equivalent (legacy) |
| `tenant_admin` | Full CRUD within the tenant, subject to financial and role-management safeguards |
| `super_admin` | Platform metadata globally; business data only in the explicitly selected, audited workspace |
| `seller` | Assigned route only — read + create transactions |

Dashboard and inventory suppress transient permission-denied states during auth/profile stream warm-up. Role-scoped providers stay in loading or cached fallback until access is confirmed.

Workspace business access for platform super-admins expires after 8 hours and remains enforced by Firestore rules. Mutations require a concrete tenant; local admins manage seller accounts only; seller-stock reductions must match a same-batch invoice deduction. Financial corrections preserve prior values, actor, and reason. Exports cursor-page to exhaustion; tenant-admin restore is upsert-only, while selected super-admin restore can prune after upserting. Plaintext legacy backup archives are rejected. Transient Firebase Auth token-refresh failures do not sign users out, and Firebase initialization failure shows a retry state.

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

## Workspace Owner and Seat Overview

The selected workspace's live management view presents owner name, email,
phone/WhatsApp contact, email-verification state, and account status alongside
current member counts by role. The free-tier capacity is 10 active
non-platform-super-admin members. User activation and deactivation update the
tenant seat count atomically with the matching profile transition; rejected
over-cap changes remain visible to the administrator.

## Cash Receipt Detail

Cash receipt detail screens and PDFs present the receipt identifier, shop and
payment context, amount received, resulting balance, and receiver/signature
information where available. Receipt creation and all financial values continue
to use the existing atomic invoice, ledger, and shop-balance pipeline.

---

## v3.10.4 Bilingual PDF and Support-Access Release

Super-admin workspace support-access start, switch, and end actions now show
distinct localized outcomes and use the active audited context. Shared
financial PDF rows pin English-left/Arabic-or-Urdu-right order with explicit
LTR `Directionality`; actual Arabic and Urdu statement samples were inspected
in Chrome. Production Urdu remains Naskh-style. The separate Nastaliq proof is
not integrated because image/logo embedding, text extraction, pagination, and
full Web/Android report parity remain unverified.

Release verification: full Flutter suite `01:16 +628: All tests passed!`;
`flutter analyze lib --no-pub`: `No issues found! (ran in 132.4s)`;
`dart analyze test/`: `No issues found!`; Rules Emulator: `147 passing (29s)`.
Web `EXIT: 0`; Hosting and Rules/indexes reported `Deploy complete!`. Split
APKs were built at 30.7/32.2/33.6 MB. No Android device was connected, so
phone installation was skipped.

---

## Translations

All UI strings live in `lib/core/l10n/app_locale.dart`. Three locales:

- `en` — English (LTR)
- `ar` — Arabic (RTL) — PDF uses the bundled Noto Sans Arabic font
- `ur` — Urdu (RTL) — PDF uses the bundled Noto Sans Arabic font because the
  current PDF renderer does not support Nastaliq's complex OpenType shaping;
  the app UI uses the bundled Noto Nastaliq Urdu font

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
flutter test -r expanded --dart-define=use_arabic=true

# 4 — No StateProvider
grep -rn "StateProvider\b" lib/ --include="*.dart"

# 5 — Web (confirm EXIT: $LASTEXITCODE = 0)
flutter build web --release --dart-define=use_arabic=true

# 6 — Hosting deploy
firebase deploy --only hosting

# 7 — APK (quote file size)
flutter build apk --release --split-per-abi --dart-define=USE_PLAY_INTEGRITY=true --dart-define=use_arabic=true

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
