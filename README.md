# FootWear ERP — v3.9.83+709

A mobile-first enterprise resource planning system for footwear distribution businesses. Built with Flutter (Android + Web) and Firebase. Designed for route-based sales operations where an admin manages products, inventory, and sellers, while field sellers record customer transactions on their assigned routes.

> **v3.7.5+53 (2026-04-15)** — Current baseline includes the post-audit hardening pass: provider admin guards, invoice and rules validation tightening, export query caps, model `copyWith`/equality cleanup, theme-safe shimmer, and workflow normalization on Flutter 3.41.6 with expanded test reporting.
> **v3.9.50+89 (2026-08-18)** — Tenant permissions are enforced across business collections, invoice-generated ledger records carry workspace identity, and Google Drive backup configuration is shared by web and Android builds.
> **v3.9.53+92 (2026-10-03)** — Tenant admins merge encrypted backups into their own workspace; selected platform admins can prune only within their active support workspace. Unsupported roles and workspace-less accounts receive recovery guidance instead of being treated as sellers.
> **v3.9.54+93 (2026-10-03)** — Status labels are localized and high-contrast status colors are more legible.
> **v3.9.58+97 (2026-10-03)** — Encrypted file and Drive backup destinations are explicit, workspace restore matches access scope, local archives can be deleted, and workspace archival revokes member access.
> **v3.9.59+98 (2026-10-03)** — Workspace-admin and seller sign-in now use scoped device-session records; workspace setup errors remain visible, and login system-bar contrast follows the active theme.
> **v3.9.60+99 (2026-10-10)** — Sign-in waits for access registration; device pairing, renewal, stale-device recovery, and platform-operator sessions have explicit controls. Session records remain client-enforced under the Spark architecture.
> **v3.9.61+100 (2026-10-15)** — Invoice creation supports stock sales, non-stock catalog sales, and cash receipt invoices. Workspace admins configure bilingual invoice headers, and generated PDFs retain the header snapshot.
> **v3.9.75+102 (2026-10-15)** — Sign-in and session renewal are guarded against stale records and account-switch races. Sellers use workspace-specific dynamic device/session limits; workspace-admin limits are shared and controlled by the platform super-admin; platform sessions remain separate. Invoice voiding is atomic and long invoice PDFs paginate. Android updates can be installed over the device's current package without removing app data.
> **v3.9.76+702 (2026-10-16)** — Workspace-admin sign-in no longer follows seller pairing approval. Session re-registration, renewal, and logout handle revoked and pending records more reliably.
> **v3.9.77+703 (2026-10-16)** — Non-stock invoicing is disabled until explicitly enabled per workspace. Sale, receipt, return, and invoice-number updates are transactionally linked to ledger, balance, and stock changes; shop transaction descriptions accept multiple lines.
> **v3.9.78+704 (2026-10-16)** — Workspace owners are selected within the active workspace, editing requires active platform access, save errors are classified accurately, and launcher icon sizing is consistent across Android and web.
> **v3.9.79+705 (2026-10-17)** — Workspace setup provisions an owner account; workspace admins can disable sellers and revoke or block their device/session access; PWA icon URLs refresh installed artwork.
> **v3.9.81+707 (2026-10-22)** — Firebase Authentication remains the only sign-in mechanism, without app-managed device pairing or custom session approvals. Workspace admins retain tenant-scoped routes, shops, and transaction CRUD. Firestore Rules enforce active tenants, zero-balance shop creation, and atomic standalone ledger/shop balance links.
> **v3.9.83+709 (2026-10-23)** — Multi-currency account and seller reports preserve route currencies and group PDF totals without adding unlike amounts. Screen workflows include retryable route/workspace loading, export progress/error feedback, safe form loading, and reduced-motion/accessibility improvements. Full Flutter suite: 567 tests passed. Web and split APKs built; Hosting and Firestore Rules/indexes deployed; ARM64 APK installed on R5GL22RGT9V. Authenticated visual acceptance remains pending.
> **Unreleased 2026-10-24 source** — Invoice idempotency and first-allocation reads of missing documents are now explicitly tenant/role scoped in Firestore Rules; workspace creation may read a missing settings document only before its tenant exists. Seller invoice authorization was simplified to preserve Rules expression headroom. Admins without available self-allocated stock receive localized guidance. Local Rules Emulator: 128 passing; focused invoice widget tests: 2 passing. Production deployment and release operations remain pending.
> **Unreleased 2026-10-24 lifecycle recovery** — Selected platform super-admins can restore an inactive workspace using an audited support context and explicit confirmation. Archive/restore changes the tenant lifecycle record only; member profiles are preserved, and business access remains denied until restoration. Client-side bulk reset and legacy plaintext utilities remain disabled.
> **Unreleased 2026-10-24 frontend hardening** — Shared animation presets and custom router fade/slide transitions honor reduced-motion preferences; the responsive login layout caps content to the available viewport. Regression tests cover six widths in EN/AR/UR. Full Flutter suite: `01:01 +589: All tests passed!`; `flutter analyze lib --no-pub`: `No issues found! (ran in 102.3s)`; `dart analyze test/`: `No issues found!`. The signed-out local browser render was checked. A debug APK attempt failed at `:app:mergeDebugJavaResource` because of insufficient system resources; no release APK or production operation was performed.
>
> Prior version bullets below are historical release notes.

---

## Features

### Admin

- **Dashboard** — live stats with shimmer loading, cash flow BarChart, alerts banner, admin speed-dial FAB
- **Products & Variants** — manage SKUs with size/colour variants, carton/dozen/pair stock tracking, share button
- **Routes** — define delivery routes and assign sellers, performance strip, shops sorted by debt
- **Shops (Customers)** — full CRUD with balance ledger, balance trend LineChart, days-overdue indicator
- **Inventory** — warehouse stock allocation with low-stock warning badges
- **Transactions** — cash-in / cash-out ledger with running balance
- **Invoices** — stock and non-stock sales, cash receipt invoices, credit notes, void/paid lifecycle, and workspace-configurable bilingual PDF headers
- **Reports** — monthly cash flow BarChart, outstanding PieChart, PDF/Excel/image export
- **User Management** — create/edit permitted admin and seller accounts, disable/reactivate accounts, and send password-reset emails
- **Settings** — workspace-scoped company name, logo (base64 ≤50 KB), pairs-per-carton, and business preferences
- **Profile** — name, language, theme and password controls for all users

### Seller

- View assigned route and shops
- Record cash-in / cash-out transactions for assigned shops
- Create stock sales, workspace-enabled non-stock invoices, and cash receipt invoices from a shop
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
| PDF export | Shared `pdf` builders embed Noto Sans Arabic; Arabic shaping requires `--dart-define=use_arabic=true` and otherwise fails closed |
| Excel export | Custom xlsx writer (`excel_export.dart`) using `archive ^4.0.0` |
| Print / Share | `printing` + share_plus 13.0.0 |
| Image compression | `flutter_image_compress` (base64 logo) |
| Animations | `flutter_animate` + `shimmer` |

Shared interactive controls use the design system's minimum target token.
Optional shared animation presets, empty/error/status transitions, stat-card
entrances and value changes, and custom router fade/slide transitions honor the
operating system's reduced-motion preference; balance badges expose localized
semantics.
Focused widget tests cover RTL target sizing, locale labels, motion suppression,
and semantic color contrast; these checks do not claim full WCAG conformance.

PDF, print, share, and PNG exports reuse the same shaped PDF bytes. Urdu PDFs
use a Naskh-style font because the current renderer does not implement full
Nastaliq OpenType shaping. XLSX preserves Unicode and RTL worksheet direction,
but its font is chosen by the spreadsheet application and is not embedded.
Every Flutter action that can generate PDFs must include
`--dart-define=use_arabic=true`.

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
flutter run --dart-define=use_arabic=true
```

### Build release APK (split-per-ABI for phone delivery)

```bash
cd app
flutter build apk --release --split-per-abi --dart-define=USE_PLAY_INTEGRITY=true --dart-define=use_arabic=true
# Output: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
#         build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
#         build/app/outputs/flutter-apk/app-x86_64-release.apk
#         build/app/outputs/flutter-apk/app-release.apk
```

### Install the release APK to a connected phone

```bash
cd app
adb push build/app/outputs/flutter-apk/app-arm64-v8a-release.apk /sdcard/Download/
adb install --streaming -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

### Build web

```bash
cd app
flutter build web --release --dart-define=use_arabic=true
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

- The `tenants` collection stores workspace metadata, plan flags, and owner user.
- Every tenant-scoped business document (`users`, `routes`, `customers`/`shops`, `products`, `seller_inventory`, `transactions`, `invoices`, etc.) must carry `tenant_id`.
- `tenant_admin` is scoped to a single tenant. `super_admin` is a platform operator and sees workspace metadata globally, but sees no workspace business records by default.
- Super-admin business support requires selecting one active workspace and entering a reason; the app records access start/end in append-only `platform_access_logs`. Firestore rules enforce the selected workspace regardless of client navigation.
- Platform super-admin accounts cannot be created or promoted from the client. Arbitrary-user Firebase Auth administration is not performed with client-held service-account keys; admins send password-reset email and account owners complete credential changes themselves.
- `TenantScope` in `app/lib/core/utils/tenant_scope.dart` is the canonical helper for query and write gating.
- `__global__` is reserved for global/system documents only.

### Tenant Gating Checklist

1. Use `TenantScope.applyToQuery(..., tenantId: ...)` for every business collection query.
2. Use `TenantScope.applyToData(..., tenantId: ...)` or explicit `tenant_id` on every tenant-scoped write.
3. Keep `tenant_admin` tenant-scoped. Keep `super_admin` platform-only unless an explicit, reasoned workspace support context is active.
4. Use `Collections.tenants` for workspace documents; avoid hardcoded `tenants` collection strings.
5. Verify Firestore rules enforce tenant ownership for each tenant-scoped collection.
6. Treat shops as `Collections.shops` (`customers` collection alias) with tenant partitioning, not as a separate customer model.
7. Ensure providers select current user tenant context from `authUserProvider` and do not leak cross-tenant streams.
8. Document new tenant-scoped collections and any tenant gating rule changes in both this README and `MASTER_BLUEPRINT.md`.
9. Prefer evolving the canonical governance files already in the repo instead of creating additional markdown artifacts for each follow-up pass.

### Verified Runtime Invariants

- Mutations require a concrete tenant; missing tenant identity is an error, never a `__global__` fallback. Unassigned users contact their workspace administrator instead of self-provisioning.
- Firebase Auth sign-in is not gated by device registration, pairing approval, or custom session slots. Firestore Rules continue to enforce active profiles, role permissions, concrete tenant scope, and audited super-admin workspace context.
- Transaction corrections use soft deletion only. Workspace admins can reverse standalone cash-in/cash-out transactions only with an exact same-batch shop-balance update; seller deletes and invoice-linked deletes are denied.
- Super-admin business access expires after 8 hours and remains enforced by Firestore rules. Legacy admins manage seller profiles; workspace-admin role changes require an active super-admin support context.
- Seller stock reductions must match exact same-batch invoice deductions. Warehouse stock movements and returns append tenant-scoped inventory audit records atomically.
- Financial corrections preserve prior values, actor, and a correction reason; invoice-linked transactions are corrected through invoice void/credit-note flows.
- Exports page to exhaustion. Tenant-admin restore is upsert-only; selected super-admin restore upserts before pruning obsolete documents. Plaintext legacy archives are rejected.
- Transient token-refresh failures do not sign users out. If Firebase initialization fails, the app shows a retry state rather than opening an unusable shell.

### Data Maintenance and Workspace Lifecycle

- Supported backups are created and restored through the app's encrypted, workspace-scoped workflow. Tenant administrators merge records without pruning; selected super-admins may replace only the active support workspace. Sellers may save encrypted assigned-route archives to phone storage; restore imports only their own eligible unlinked cash ledger rows with atomic shop-balance reconciliation. Saved files can be explicitly uploaded to configured Google Drive when online; this is not background synchronization.
- Bulk database flush/reset controls and the legacy plaintext export, whole-collection restore, and direct-balance reset scripts fail closed. Multi-batch client cleanup can leave financial links, balances, inventory, or references inconsistent.
- Workspace lifecycle is archive/restore only. Firestore Rules deny hard deletion of a tenant root so business records cannot be orphaned by deleting the workspace document.
- To restore an archived workspace, select it from the workspace list with a support reason of at least 10 characters, then confirm Restore. The selected context is recorded in `platform_access_logs`; active tenant status remains required by business-data Rules.
- No production cleanup or backup was run as part of this source audit. A safe general-purpose transactional maintenance workflow remains a separate operational design.

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
2. **Stock sale:** `CreateSaleInvoiceScreen` → `InvoiceNotifier.createSaleInvoice()` — invoice, cash ledger entries, exact inventory deductions, and shop balance update.
3. **Non-stock sale:** same invoice notifier with `fulfillment_mode: non_stock` — catalog items are recorded without inventory deductions and only when the workspace setting permits it.
4. **Cash receipt:** `InvoiceNotifier.createCashReceipt()` — tenant-scoped receipt number, receipt invoice, `cash_in` ledger row, and balance reduction in one Firestore transaction.
5. **Ledger-only collection:** `ShopDetailScreen` → `TransactionNotifier.create(type: 'cash_in')` remains available when no receipt document is needed.
6. **Void/return:** `InvoiceNotifier.voidInvoice()` — admin only; stock returns only for stock-backed invoices, with one reversal transaction.
7. Never create a sale invoice for cash-only collection. Never create a standalone transaction for a new goods sale.
8. Client transaction reads of missing invoice/transaction IDs require an active profile and concrete active tenant; selected super-admins must retain valid support context. Missing seller-inventory reads are admin-equivalent only. Workspace-creation settings reads are limited to missing documents whose tenant has not yet been created. Existing-document reads remain governed by normal tenant and route rules.

---

## Code Quality

```bash
cd app

# Must return "No issues found!"
flutter analyze lib --no-pub

# All tests must pass
flutter test -r expanded --dart-define=use_arabic=true

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
4. `flutter test -r expanded --dart-define=use_arabic=true` → quote pass count.
5. `flutter build web --release --dart-define=use_arabic=true` → confirm `EXIT: $LASTEXITCODE` = 0.
6. `firebase deploy --only hosting` after the web build.
7. `flutter build apk --release --split-per-abi --dart-define=USE_PLAY_INTEGRITY=true --dart-define=use_arabic=true` → quote the generated ABI APK path(s) and size(s).
8. `firebase deploy --only firestore:rules,firestore:indexes` on every signoff, before commit/push is considered complete.
9. `git log --oneline -5`, `git status --short`, and `git diff --stat HEAD` → confirm only expected local changes remain.
10. `git add -A`, `git commit -m "type: summary — vX.Y.Z+N"`, and `git push` → quote commit hash and push output.
11. `adb push build/app/outputs/flutter-apk/app-arm64-v8a-release.apk /sdcard/Download/` followed by `adb install --streaming -r /sdcard/Download/app-arm64-v8a-release.apk` to install the phone-delivery APK to a connected device when Android delivery is part of the request.

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
