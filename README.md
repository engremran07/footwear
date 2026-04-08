# FootWear ERP — v3.4.0

A mobile-first enterprise resource planning system for footwear distribution businesses. Built with Flutter (Android + Web) and Firebase as the backend. Designed for route-based sales operations where an admin manages products, inventory, and sellers, while field sellers record customer transactions on their assigned routes.

> **v3.4.0+30** — Autonomous 20-agent CI/CD self-healing system: GitHub Actions (ci.yml hygiene gates, build-apk.yml, release.yml, deploy-web.yml), GitHub prompts (20-agent audit, post-impl checklist), GitHub instructions (collections, financial-integrity, testing, code-quality), 7 skill file updates/additions. Security: seller transaction rules restricted to description+updated_at only; new updateTransactionNote() provider; role-aware edit dialog (seller annotation-only, delete hidden). Session UX: 7h30m warning dialog before 8h hard cutoff, L10n parity across EN/AR/UR.

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
- **User Management** — create/edit admin and seller accounts, soft-delete; **email + password changeable from the app** via the 4-way Auth Pipeline; email-verified badge + send-verification button per user
- **Settings** — company name, logo (base64 ≤50KB), pairs-per-carton, business preferences
- **Profile** — name, language, theme and password controls for all users

### Seller

- View assigned route and customers
- Record cash-in / cash-out transactions for assigned customers
- View account statements
- Dashboard and inventory suppress transient permission startup errors and wait for role-scoped streams to settle before showing access state

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
flutter build apk --release
# Output: app/build/app/outputs/flutter-apk/app-release.apk (fat APK)
```

---

## Backend Deployment

```bash
# Deploy Firestore rules and indexes
firebase deploy --only firestore:rules,firestore:indexes
```

> Note: No Cloud Functions deployment needed. User creation runs via secondary FirebaseApp. Admin email/password management uses a Service Account key stored in Firestore (`admin_config/sa_credentials`) — see [Admin Auth Pipeline](#admin-auth-pipeline) below.

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
| `seller_inventory` | Seller-allocated stock per variant |
| `inventory_transactions` | Stock movement audit trail |
| `settings` | Global business settings |
| `admin_config` | Service Account credentials (admin-read only) |

---

## Admin Auth Pipeline

Version 3.3.7 introduces a fully autonomous 4-way authentication sync pipeline. Admin can change **any user's email or password** directly from the app — no Firebase Console required.

### Architecture

```
Admin taps Save in Edit User dialog
         │
         ▼
 AdminIdentityService (app/lib/core/services/admin_identity_service.dart)
         │
         ├─ 1. Reads SA key from Firestore admin_config/sa_credentials
         │      (base64-encoded Service Account JSON — admin-read-only rule)
         │
         ├─ 2. Builds RS256 JWT signed with SA private key
         │
         ├─ 3. Exchanges JWT → OAuth2 access token
         │      POST https://oauth2.googleapis.com/token
         │      (cached 55 min; cleared on sign-out)
         │
         ├─ 4. Calls Identity Toolkit Admin REST API
         │      POST .../v1/projects/{proj}/accounts:update
         │      { localId, email?, password? }
         │      (Bearer: SA OAuth2 token)
         │
         └─ 5. On Auth success → Firestore batch update (email, updated_at)
                │
                └─ Riverpod allUsersProvider stream auto-fires
                         │
                         └─ UI re-renders instantly (4-way sync complete)
```

### What syncs atomically

| Layer | Field | Sync method |
| --- | --- | --- |
| Firebase Auth | `email`, `password` | Identity Toolkit Admin REST (SA token) |
| Firestore `users/{uid}` | `email`, `updated_at` | Batch write after Auth success |
| Riverpod `allUsersProvider` | full UserModel | StreamProvider auto-fires on Firestore change |
| UI (Edit User dialog) | email chip, verified badge | Rebuilds from updated stream |

### Email Verified badge

Each user shows a **Verified** (green) or **Unverified** (orange) chip.
- On admin sign-in, `emailVerified` is synced from `FirebaseAuth.currentUser.emailVerified` → Firestore.
- The **Send Verification** button calls `accounts:sendOobCode` with `VERIFY_EMAIL` action code.

### Free-tier security model

- SA key lives in Firestore `admin_config/sa_credentials` with rule `allow read: if isAdmin(); allow write: if false;`
- Only active admins (role == 'admin' | 'manager') can read it.
- The SA key is **never bundled in the APK** — it is fetched at runtime on demand.
- OAuth2 token is cached in-memory for 55 minutes, cleared on sign-out.
- **Blaze upgrade path**: migrate to Cloud Functions `onCall` — move SA JWT logic server-side for zero client exposure.

### Provisioning (one-time setup)

The SA key is already stored in Firestore for this project. To re-provision on a new project:

```powershell
# 1. Download SA JSON from Firebase Console → Project Settings → Service Accounts
# 2. Encode and store in Firestore
$json = Get-Content 'path\to\sa-key.json' -Raw
$b64  = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
# 3. Run in Firebase Console → Firestore:
#    Collection: admin_config  Doc: sa_credentials  Field: sa_json_b64 = <$b64>
```

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
3. If web and APK are both being shipped, bump the release version/build first and keep `app/pubspec.yaml` plus `AppBrand.versionDisplay` aligned
4. Build web and deploy Hosting from that release candidate
5. Build release APK from the same release candidate
6. Deploy firestore rules and indexes when backend behavior changed
7. Validate admin and seller write-path behavior on live project users
8. Verify About/version/contact content is the same on web and APK for user-facing release changes

## v3.3.8+29 Auth Pipeline Hardening

- **`VERIFY_EMAIL` fix**: `sendOobCode` always requires a user `idToken` — admin SA bearer alone is rejected. Correct 3-step flow: SA private key → Firebase custom token (RS256) → `signInWithCustomToken` → ephemeral `idToken` → `sendOobCode`. Zero extra cost, zero SDK state change.
- **OAuth2 scope**: upgraded from `auth/firebase` to `auth/cloud-platform` (covers both `accounts:update` and project-scoped `sendOobCode`).
- **UI overflow fix**: email-verified chip + Send Verification button row replaced with `Wrap` — wraps gracefully on narrow screens.
- **`sendPasswordResetEmail`**: simplified to public `accounts:sendOobCode?key=` endpoint (no admin token needed for `PASSWORD_RESET`).
- **SA credentials cache**: added in-memory `_cachedCreds` (cleared on sign-out) to avoid repeated Firestore reads.
- **Tests**: 335 passing.

## v3.3.7+28 Auth Pipeline

- **AdminIdentityService**: SA key → RS256 JWT → OAuth2 → Identity Toolkit Admin REST
- **4-way sync**: Auth ↔ Firestore ↔ Riverpod ↔ UI — real-time, no manual refresh
- **Email verified** field added to `UserModel` + Firestore `users` docs
- **Edit User dialog**: email + password editable; email-verified chip; send-verification button
- **Firestore rules**: `admin_config` collection added (admin-read / no-write)
- **L10n**: 10 new keys × 3 languages (EN/AR/UR)
- **Tests**: 335 tests passing (no regressions)
- **Version**: `3.3.7+28` in `pubspec.yaml` + `app_brand.dart`

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
- **Release**: v3.0.0+7, fat APK built, tested on Samsung A56 + V2247

---

## Canonical Docs

- AGENTS.md
- CLAUDE.md
- SYSTEM_DEEP_DIVE_2026-03-27.md
- app/README.md
