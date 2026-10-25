# ShoesERP AGENTS Runtime Contract

Last updated: 2026-10-25

## 1) Runtime Truth (Authoritative)

This repository is a route/seller distribution ERP.

- Roles: admin, supervisor, seller
- Legacy role value manager must be treated as admin-equivalent in app and rules
- Tenant-aware roles tenant_admin and super_admin are now supported and must be treated as privileged, tenant-scoped roles in app and rules
- Supervisor is a tenant-scoped operational role: routes, shops, products, inventory, invoices, and reports are available, but user administration, notifications, settings, backup, financial corrections, invoice voids, route-seller assignment, and shop route reassignment remain restricted.
- Super-admin is a platform operator, not a global business-data reader. By default it may access workspace metadata only; client business data requires an explicit `active_workspace_id`, a support reason of at least 10 characters, and an append-only `platform_access_logs` event. Access ends by clearing the active workspace context.
- New tenant-scoped users carry a tenant_id and must not cross tenant boundaries in rules or providers. Firebase Authentication is the app's only sign-in/session mechanism; the app does not register devices, require pairing, or maintain custom access slots.
- Business access requires both an active user profile and an active tenant
  document. Inactive tenants block ordinary admin/seller business access; the
  selected super-admin restoration path is the narrowly scoped exception.
- Workspace settings are tenant-scoped. No workspace or platform device-pairing, device-cap, or custom session-cap policy is used.
- Canonical collections:
  - users (Firebase Auth-linked profiles)
  - products
  - product_variants
  - seller_inventory
  - inventory_transactions
  - routes
  - shops [Firestore collection: 'customers' — legacy name, use Collections.shops]
  - transactions
  - invoices
  - settings
  - tenants
  - platform_access_logs

Source of collection truth: app/lib/core/constants/collections.dart

## 2) Required Route Map

Defined in app/lib/core/router/app_router.dart:

- /login
- /bootstrap-profile
- /
- /routes
- /routes/new
- /routes/:id
- /routes/:id/edit
- /shops
- /shops/new
- /shops/:id
- /shops/:id/edit
- /products
- /products/new
- /products/:id
- /products/:id/edit
- /products/:id/variants/new
- /products/:id/variants/:vid/edit
- /inventory
- /invoices
- /invoices/new
- /invoices/:id
- /users
- /tenants
- /history
- /notifications
- /reports
- /profile
- /about
- /settings
- /settings/invoice-header
- /settings/flush
- /settings/backup

## 3) Permission Matrix

Admin-equivalent (admin/manager):

- Full write access to all business collections

Workspace admin (tenant_admin):

- Full CRUD within the assigned tenant, subject to financial and user-role safeguards

Platform super-admin:

- Platform workspace metadata globally; business data only in the explicitly selected, audited workspace

Seller:

- Read active business documents
- Create/update shops only inside assigned route constraints
- Create transactions for assigned route
- Update own profile (name, theme, locale, password)
- No writes to routes/products/product_variants/settings

Supervisor:

- Tenant-scoped access to operational routes, shops, products, inventory,
  invoices, and reports
- Cannot manage users, workspace/platform settings, notifications, or backups
- Cannot change route seller assignments or move shops between routes
- Cannot perform financial corrections, approve transaction edits, or void invoices

## 4) Non-Negotiable Engineering Rules

1. Role alignment is mandatory in all three layers: app/lib/models/user_model.dart, firestore.rules, and provider write guards on security-critical fields.

1. Firebase Authentication is the only authentication mechanism. Do not add app-managed device registration, pairing approval, session slots, session renewal, or device/session policy fields. Keep active-profile, role, tenant, and super-admin support-context checks.

1. Business reads and writes require an active tenant as well as an active
  profile. A selected super-admin may restore an inactive workspace only
  through the explicit tenant-lifecycle restoration path; ordinary business
  reads/writes remain denied until the tenant is active.

1. Shop creation must begin with `balance == 0` and cannot seed cached
  last-transaction fields. Standalone transaction creation must be linked to
  the exact same-batch shop and balance update. Invoice operations may contain
  multiple ledger rows and must preserve their validated invoice references
  and aggregate shop-balance delta.

1. Super-admin business access is workspace-scoped. Never let a super-admin read tenant routes, shops, products, inventory, invoices, transactions, reports, users, or tenant settings without an explicit active workspace context. Platform workspace metadata may remain globally visible. Record support access starts/ends in the append-only `platform_access_logs` collection; never use UI visibility as the security boundary.

1. Super-admin business context expires after 8 hours. Firestore rules must enforce the TTL on every business-data path, and no generic admin-role branch may bypass it. Workspace admins may change only their workspace-scoped business settings; workspace lifecycle and platform configuration remain platform-controlled.

1. New business writes must require a concrete tenant via `TenantScope.requireTenant`; `__global__` is never a missing-tenant fallback. Unassigned non-platform users must be stopped at sign-in with an actionable message, not silently provisioned into a shared workspace.

1. Legacy `admin`/`manager` users may manage seller accounts only. Tenant admins may create or assign only supervisor and seller roles to eligible non-owner profiles; admin, tenant-admin, and platform roles remain reserved to the selected platform-super-admin path. Tenant admins cannot deactivate peer administrators.

1. Service-account credentials must never be stored in Firestore, backups, client code, or APK/web defines. Arbitrary-user Firebase Auth administration requires a trusted backend; client code must use owner-controlled Firebase Auth flows. Never create/promote super-admin accounts from the client.

1. Do not invent collections; use constants only.

1. All Firestore writes must happen in provider notifiers.

1. Dashboard must degrade gracefully under resource-exhausted.

1. Dashboard and inventory must not show transient permission-denied errors
  during auth/profile loading; role-scoped providers must stay in loading,
  empty, or cached fallback state until access is confirmed.

1. Web and APK release surfaces must stay version-synced. If user-visible
  changes are shipped to both, bump version/build when needed and rebuild both
  surfaces from the same source tree before calling them aligned.

1. Firebase Hosting must not cache Flutter web shell files (`index.html`,
  `flutter.js`, `flutter_bootstrap.js`, `main.dart.js`,
  `flutter_service_worker.js`, `version.json`, `manifest.json`) as immutable.

1. Every where(A)+orderBy(B) (A != B) must have composite index in firestore.indexes.json.

1. If runtime behavior changes, update these docs in same change set:
   - AGENTS.md
   - CLAUDE.md
   - README.md
   - app/README.md
   - SYSTEM_DEEP_DIVE_2026-03-27.md

1. Admin-only screens must still enforce admin checks in submit/write methods
  (defense in depth), even when router guards already restrict access.

1. Provider methods that write security-relevant fields (for example
  created_by, route_id, shop_id) must validate non-empty identifiers before
  committing batched writes.

1. Seller inventory may only decrease in the same batch as a sale invoice whose `seller_inventory_deductions` map matches the exact quantity delta. Warehouse transfers, adjustments, and returns must atomically update stock and append tenant-scoped `inventory_transactions` records.

1. Financial transaction corrections must preserve the previous amount/type/date in an append-only `edit_history` entry with actor and a reason of at least 10 characters. Invoice-linked ledger rows are corrected only by void/credit-note flows.

1. Standalone cash-in/cash-out transaction deletion is soft-delete only. A tenant admin-equivalent may delete only an unlinked cash row with an exact same-batch `shop.balance` reversal and correction transaction ID. Clear cached last-transaction fields only when they point to the deleted row. Sellers, invoice-linked rows, and hard deletes are denied.

1. Full exports must cursor-page until exhausted; hard limits remain appropriate only for live UI windows that visibly communicate truncation. Full restore must upsert all backup data before pruning obsolete tenant documents. Plaintext backup archives are not accepted for restore.

1. Startup must not sign users out for transient token-refresh/network failures. If Firebase initialization fails, show a retry/failure state instead of mounting the authenticated app against an uninitialized SDK.

1. No Firebase Storage usage — the app runs on Firestore + Auth + Functions
  only (zero-cost tier). Company logos are stored as base64 in Firestore.
  Product images use external HTTP URLs. Do not introduce firebase_storage.

1. Firebase Auth SDK owns credential and token lifecycle. Do not introduce custom device/session enrollment or client-side session enforcement as an authorization boundary. Firestore Rules must continue to enforce active-user, role, tenant, and selected super-admin workspace scope on every business-data path.

1. Any provider that reads admin-only data (e.g. `allTransactionsProvider`,
  `allInvoicesProvider`, `adminAllSellerInventoryProvider`) MUST be added to
  `_invalidateRoleScopedProviders()` in `auth_provider.dart`. Failing to do so
  leaks admin data to seller sessions across hot-restarts and re-logins.

1. All Firestore collection references MUST use `Collections.*` constants from
  `app/lib/core/constants/collections.dart`. No raw `.collection('string')`
  calls are permitted anywhere in `app/lib/`.

1. If multiple temporary fixes were applied for one bug, and QA/user confirms
  the real culprit fix, run the Band-Aid Loop Reversal protocol before signoff:
  keep only root-cause + mandatory guards, rollback non-culprit mitigations,
  and document final keep/remove reasoning.

1. **`shop.balance` is the sole financial source of truth for a shop.**
  It must ONLY be mutated by `InvoiceNotifier` or `TransactionNotifier` methods
  through atomic Firestore batch/transaction writes. Balance is NEVER written
  from screens, widgets, or direct Firestore calls. Every monetary display
  (shop detail Total In/Out, route detail outstanding, dashboard AR) derives
  from this single field — either by reading it directly or by summing the
  live transactions stream that drives it. Manual Firestore operations that
  delete or modify financial documents (transactions, invoices) WITHOUT
  updating the corresponding `shop.balance` WILL produce stale UI. Do not use
  client-side bulk flush/reset tools or direct Firestore scripts to delete
  ledger rows or rewrite balances. The app flush screen and legacy
  backup/restore/reset scripts fail closed because multi-batch client
  operations cannot preserve financial links atomically. Workspace lifecycle
  is archive/restore only; tenant-root hard deletion is denied by Rules.

1. **`StateProvider` is BANNED.** Riverpod 3.x removed `StateProvider` from
  the main export. All mutable reactive state must use
  `NotifierProvider<T extends Notifier<S>, S>` with an explicit `Notifier`
  subclass. Catch-all: `grep -rn "StateProvider" app/lib/` must return zero.

1. **Firestore rules MUST be deployed before signoff.** Any PR or autonomous
  agent session that changes `firestore.rules` or `firestore.indexes.json`
  MUST end with `firebase deploy --only firestore:rules,firestore:indexes`.
  Uncommitted local rule changes that are not deployed are treated as
  incomplete work and block signoff.

1. **AI agents MUST provide verifiable evidence for every signoff claim.**
  Acceptable evidence formats:
   - `flutter analyze lib --no-pub` → must quote exact final line
   - `flutter test -r expanded --dart-define=use_arabic=true` → must quote pass count line
   - APK build → must quote file size from output
   - Web build → must state `EXIT: 0`
  Claims of "tests pass" or "no issues" without quoting the actual tool
  output are invalid and block signoff. This rule is non-bypassable.

1. **Version sync is atomic.** `app/pubspec.yaml` version field and
  `app/lib/core/constants/app_brand.dart` `appVersion`/`buildNumber` MUST
  be updated in the same edit operation. Version drift between these two
  files is a P0 regression. Verify with:
  `grep -E "^version:|appVersion|buildNumber" app/pubspec.yaml app/lib/core/constants/app_brand.dart`

1. **All export/report user-name resolution MUST use `NameResolver`.**
  `app/lib/core/utils/name_resolver.dart` is the single source of truth for
  resolving Firestore UIDs to display names in PDFs, Excel, and images.
  Never build ad-hoc `entryByMap` maps. Never fall back to a raw UID string.
  Fallback must always be a localized `unknown_user` label or `'—'`.
  Export string literals (page footers, column headers, timestamps) must
  use `trRead()` with the current locale — no hardcoded English. Every Flutter
  test, run, and build that can generate PDFs must pass
  `--dart-define=use_arabic=true`; the `pdf` package otherwise performs bidi
  reordering without Arabic-script letter shaping. The shared PDF font loader
  must fail closed with a localized configuration error when the flag is
  missing; it must never return a success-shaped, unshaped RTL report. PDF
  output embeds Noto Sans Arabic for Arabic and Urdu; full Nastaliq shaping is
  unsupported by the current renderer. PNG, print, and PDF share the same PDF
  bytes; XLSX does not embed a font and relies on the spreadsheet application.

1. **Every `ExportSheet.show()` call MUST provide `pdfBytesBuilder`** when the
  data is a ledger, account statement, or seller report. The generic
  `buildPdfTable()` fallback is only acceptable for simple flat tables
  (inventory list, shops list). If the export contains running balances,
  debit/credit columns, or an Entry By column, the caller MUST supply a
  custom `pdfBytesBuilder` that calls the appropriate builder
  (`buildPdfLedger`, `buildPdfSellerReport`, `buildPdfMultiShopLedger`).
  Grep gate: every `ExportSheet.show(` call site must be auditable.

1. Bilingual financial PDF columns must keep English physically left and the
  selected Arabic/Urdu content physically right, regardless of page locale.
  With `pdf` 3.12.0, `pw.Row` has no `textDirection` argument; wrap the row in
  `pw.Directionality(textDirection: pw.TextDirection.ltr)` and set each text
  widget's direction explicitly. Verify actual Arabic and Urdu output.

1. **`changelog_data.dart` MUST be updated on every version bump.** When
  `app/pubspec.yaml` version is bumped, a corresponding entry MUST be added
  to `app/lib/core/data/changelog_data.dart` with trilingual
  (EN/AR/UR) descriptions. The `whats_new_sheet.dart` auto-displays the
  latest changelog on first launch after update. Skipping this means users
  see stale "What's New" content. Verify:
  `grep -c "ChangelogVersion" app/lib/core/data/changelog_data.dart`

1. **Task continuity is mandatory.** When a user adds new work mid-session,
  the agent MUST merge new tasks into the existing todo list — never discard,
  replace, or forget previous tasks. Review conversation history and session
  memory before creating a new todo list. Incomplete tasks from prior prompts
  carry forward automatically. If a prior task is no longer relevant, mark it
  explicitly as "dropped — reason: ..." rather than silently removing it.

1. **AI account/session continuity is repository-backed, not account-merged.** Copilot chat history and request IDs are not portable between GitHub identities by a repository change. Persist durable decisions, pending work, audit IDs, and exact verification evidence in `SESSION_LOG.md` and the current audit report; on account/profile changes, read those files plus `git status`/`git diff` before continuing. Never store credentials or full chat transcripts in the repo, and do not claim cloud session sync merged separate accounts.

1. **Vibe Debugging Discipline is mandatory for all bug fixes.** Before
  writing any fix code, the agent MUST: (a) read the FULL execution path
  from screen → provider → Firestore/builder, (b) grep ALL instances of the
  bug pattern before fixing any single one, (c) trace the exact call stack
  to the root cause — not the error message. The 5 banned anti-patterns are:
  Whack-a-Mole Debugging, Symptom Chasing, Regression Spiral, Vibe Debt,
  Confidence Theater. Load `.claude/skills/vibe-debugging-discipline/SKILL.md`
  before any bug fix session.

1. **Missing-document Firestore reads must remain scoped.** Invoice and
  transaction idempotency reads require an active profile, a concrete active
  tenant, and a permitted role; super-admin access additionally requires the
  selected workspace, support reason, and unexpired context. Missing
  seller-inventory reads are admin-equivalent only. A super-admin may read a
  missing settings document only when its tenant document does not yet exist
  for workspace creation. Never use a blanket `resource == null` allowance.
  Rules tests must replay the relevant read inside the client transaction and
  then validate its complete write set.

1. Financial PDFs must reuse the shared workspace brand header: English
  business information is on the left and the selected Arabic/Urdu information
  is on the right, independent of app locale. Prefer current workspace logo
  bytes; if current bytes are unavailable, invoice and receipt PDFs may use
  the saved invoice logo while still honoring `visibleFields`. Cash receipts
  use an A5 page and remain one page. Keep `use_arabic=true`, assert PDF font,
  image, page-count, and page-size resources, and inspect rendered output when
  available; font embedding alone is not visual proof.

## 5) Known Failure Signatures

1. permission-denied on route create/inventory add

- role value drift (Admin/manager casing, trailing spaces, legacy values)
- user doc inactive
- rules not deployed

1. resource-exhausted on dashboard

- aggregate query quota pressure
- repeated refresh hitting count/sum endpoints

1. lists empty without obvious UI error

- missing composite index

1. export/PDF generates empty data or crashes

- `ref.read(authUserProvider).value` in async/provider context → null during loading
- Fix: use `await ref.read(authUserProvider.future)` in ALL export providers and screen export methods
- Grep gate: `grep -rn "ref\.read(authUserProvider)\.value" app/lib/providers/` must return zero in export contexts

### Google Drive OAuth and tenant backup contract

- Drive backup uses the least-privilege `drive.file` scope and must be filtered by the authenticated Firebase user and workspace.
- Tenant admins may back up and merge-restore their own workspace; they do not prune records absent from a backup. A selected super-admin may replace/prune only the active workspace. Sellers may back up assigned-route data and restore only their own transactions for a route that is currently assigned.
- Seller archives are encrypted and route-scoped. Seller restore imports only the seller's own unlinked cash-in/cash-out rows and atomically reconciles each same-route shop balance; it never restores invoice, inventory, or other sellers' ledger records. Mobile users may save an encrypted archive to phone storage, restore an archive selected from storage, or explicitly retry Drive upload when online and OAuth is configured. This is not background sync.
- Super admins must select a concrete workspace before backup or restore; a global all-workspace client snapshot is forbidden.
- Web builds require `GOOGLE_DRIVE_CLIENT_ID`; Android builds require the matching web `GOOGLE_DRIVE_SERVER_CLIENT_ID` and a registered Android OAuth client for package `footwear.pk.com`.
- The release keystore SHA-1 must be registered in Firebase/Google Cloud before Google Sign-In can authorize Drive on the APK.

## 6) Mandatory Triage Order

1. Verify active user doc exists and role is canonical
2. Verify app role parsing + rule role checks align
3. Verify rules/indexes are deployed
4. Verify provider query shape and index coverage
5. Verify screen writes only call provider notifier methods

## 7) Commands

Deploy rules and indexes:

```bash
firebase deploy --only firestore:rules,firestore:indexes
```

Deploy functions:

```bash
cd functions
npm install
firebase deploy --only functions
```

Flutter:

```bash
cd app
grep -E "^version:|appVersion|buildNumber" pubspec.yaml lib/core/constants/app_brand.dart
flutter pub get
flutter analyze lib --no-pub
dart analyze test/
flutter test -r expanded --dart-define=use_arabic=true
flutter build web --release --dart-define=use_arabic=true
firebase deploy --only hosting
# Split-per-ABI Android APKs (canonical phone-delivery artifact set)
flutter build apk --release --split-per-abi --dart-define=USE_PLAY_INTEGRITY=true --dart-define=use_arabic=true
cd ..
firebase deploy --only firestore:rules,firestore:indexes
git log --oneline -5
git status --short
git diff --stat HEAD
```

## 8) Scope-Aware Verification and Release Checklist

Run checks that match the requested change. Emulator tests, analyzers, and
local builds are separate from production deployment and publication. Never
deploy, modify production data, build a release, install, commit, push, or tag
unless the user explicitly authorizes that operation.

### Before writing code

- Read AGENTS.md and CLAUDE.md
- Validate role/rules/collection alignment

### Release Sequence (Only When an End-to-End Release Is Authorized)

Use these steps as a release checklist only when the user requests a release.
For local-only implementation tasks, run relevant local tests and clearly list
unperformed release/production operations. Emulator output is not proof of
production deployment.

#### Step 1 — Version bump + sync

```powershell
Select-String -Path "app\pubspec.yaml","app\lib\core\constants\app_brand.dart" -Pattern '^version:|appVersion|buildNumber'
```

Evidence required: quote the matching version/build lines and confirm the
intended release version/build is synchronized before any artifact is built.

#### Step 2 — Flutter analyze (zero issues)

```powershell
cd app; flutter analyze lib --no-pub
```

Evidence required: quote exact final line `No issues found! (ran in Xs)`

#### Step 3 — Dart analyze test (zero issues)

```powershell
dart analyze test/
```

Evidence required: `No issues found!`

#### Step 4 — All tests green

```powershell
flutter test -r expanded --dart-define=use_arabic=true
```

Evidence required: quote `All N tests passed!` with N count

#### Step 5 — Hygiene grep gates (all must return zero results)

```powershell
# 5a — No raw collection strings
grep -rn "\.collection\('" app/lib/ | grep -v "Collections\."
# 5b — allTransactionsProvider in invalidation list
grep -q "allTransactionsProvider" app/lib/providers/auth_provider.dart
# 5c — No Firestore writes in screens/widgets
grep -rn "FirebaseFirestore\|\.collection(" app/lib/screens/ app/lib/widgets/
# 5d — No StateProvider (banned Riverpod 3)
grep -rn "StateProvider\b" app/lib/ --include="*.dart"
# 5e — No temp artifacts in git status
git status --short | grep -E "auth-users\.json|\.txt$|\.log$|\.flag$|check_locale\."
```

#### Step 6 — Zero markdown lint issues

```powershell
markdownlint "**/*.md" ".claude/**/*.md" ".github/**/*.md" --ignore node_modules --ignore app/build --ignore functions/node_modules
```

Evidence required: zero output (exit 0)

#### Step 7 — Web release build

```powershell
$ErrorActionPreference='Continue'
cd app; flutter build web --release --dart-define=use_arabic=true
Write-Host "EXIT: $LASTEXITCODE"
```

Evidence required: `EXIT: 0` (check `$LASTEXITCODE` directly; PowerShell
pipe artefacts do not reflect flutter's real exit code)

#### Step 8 — Firebase Hosting deploy

```bash
firebase deploy --only hosting
```

Evidence required: quote "Deploy complete!" from output.
Run only when Hosting deployment is explicitly authorized.

#### Step 9 — APK release build

```powershell
flutter build apk --release --split-per-abi --dart-define=USE_PLAY_INTEGRITY=true --dart-define=use_arabic=true
```

Evidence required: quote the generated ABI APK path(s) and size(s), for example `Built build\app\outputs\flutter-apk\app-arm64-v8a-release.apk (XXmb)`.

#### Step 10 — Firestore rules + indexes deploy

```bash
firebase deploy --only firestore:rules,firestore:indexes
```

Evidence required: quote "Deploy complete!" from output.
Run only when production Rules/indexes deployment is explicitly authorized.

#### Step 11 — GitHub local audit

```powershell
git log --oneline -5      # review last 5 commits
git status --short        # confirm only expected files are staged/modified
git diff --stat HEAD      # confirm scope of changes matches intent
```

Evidence required: quote `git log --oneline -5` output and confirm
no unexpected files appear in `git status --short` or `git diff --stat HEAD`.

#### Step 12 — Commit with descriptive message

```powershell
git add -A
git commit -m "<type>: <summary> — v<version>"
```

Commit only when explicitly requested. Evidence required when performed: quote
the commit hash from output.
Commit message must follow: `type: summary` where type ∈
{feat, fix, chore, style, refactor, test, docs, ci, release}.

#### Step 13 — Push to remote

```powershell
git push
```

Push only when explicitly requested. A push to `main` triggers
`.github/workflows/deploy-web.yml`; a version tag or manual release dispatch
can trigger `.github/workflows/release.yml`, including production deployment.

#### Step 14 — APK install to device (only when Android delivery is requested)

Install only when Android delivery is in scope and explicitly authorized. If
no APK was requested or built, do not run this step.

```powershell
adb devices   # if any device listed below header, MUST proceed with install
adb -s <device-id> push "app\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk" /sdcard/Download/
adb -s <device-id> install --streaming -r "app\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
```

Evidence required: quote `Success` from adb output, OR quote exact `adb devices`
output showing only the header (`List of devices attached`) with no devices — in
which case document as "No device connected — install skipped".

#### Step 15 — Final verification (when applicable)

- Verify admin and seller startup for `/` and `/inventory` after
  auth/router/provider/rules edits; no transient permission-denied UI acceptable
- Update AGENTS.md §10 audit status if runtime assumptions changed
- If bug resolution involved multiple candidate fixes, run band-aid-loop-reversal
  skill before committing

### Evidence and Scope

Report exact output for checks actually run. State explicitly when production
deployment, release builds, data migration, device installation, commit, or
push were not authorized or performed. Do not call local-only work a deployed
release or a complete production signoff.

## 9) Runtime Document Hierarchy

Conflict resolution order for instructions:

1. AGENTS.md (runtime contract)
2. CLAUDE.md (coding rules)
3. .claude/CLAUDE.md (local mirror/override helper)
4. Skill files under .claude/skills/

For Flutter UI implementation, `.github/instructions/frontend-design-system.instructions.md`
is the authoritative visual/accessibility contract. Use the
`.claude/skills/flutter-frontend-modernization/SKILL.md` orchestrator for
cross-screen work; specialists must reference that contract instead of
maintaining duplicate token, theme, route, or accessibility standards.
Shared interactive controls use `AppTokens.minTouchTarget` where applicable.
Optional shared-component transitions honor `MediaQuery.disableAnimations`
through `AppMotion`; router fade/slide transitions must also bypass optional
effects when reduced motion is enabled. Visible-value semantics use the active
locale. Cover these contracts, actual color pairs, and RTL direction in focused
widget tests.

## 10) Current Audit Status

2026-10-24 operational data freshness and financial presentation — local,
unreleased source:

- Workspace invoice-header and business-settings forms now rehydrate from
  Firestore snapshots while clean and preserve unsaved edits. The invoice
  header is the editable branding source; settings saves remove the legacy
  `company_name` field while older records remain readable during migration.
- Pull-to-refresh covers shop lists, invoice lists (including empty filters),
  shop ledgers, and settings forms. Firestore-backed views remain live streams.
  Shop flow totals are full precision and grouped by route currency; invoice
  lists have an outstanding-sale filter. Shop detail places location and
  overdue age on one compact row.
- Voiding atomically tags invoice-linked transactions and reversal rows for
  exclusion from customer-facing ledgers and exports; admin transaction
  history retains the audit rows. A collected payment remains visible as
  customer credit when a sale is voided in credit-balance mode.
- Receipt PDFs emphasize the received amount and include payment, balance,
  received-by, and signature details. Ledger summary labels now use the
  document's locale direction; statements/reports render the configured
  workspace invoice header.
- Focused invoice/currency/model/PDF suite: `00:03 +43: All tests passed!`;
  live settings hydration: `00:01 +2: All tests passed!`;
  `flutter analyze lib --no-pub`: `No issues found! (ran in 52.6s)`;
  `dart analyze test/`: `No issues found!`. Full-suite validation is pending.
  Firestore Rules were not changed or deployed; no release build, device
  install, commit, or push was performed.

2026-10-24 invoice permission re-audit — local source, not deployed:

- Firestore Rules now allow scoped reads of missing invoice/transaction IDs,
  admin-only missing seller-inventory records, and missing workspace settings
  only for a super-admin while the tenant is not yet created. Existing-document
  reads still use their tenant/role rules; inactive tenants and unselected or
  expired super-admin contexts remain denied.
- Seller invoice authorization reuses a single scoped profile/shop check, and
  linked invoice transactions avoid a redundant shop-route lookup. This keeps
  the complete seller sale write set within the Rules expression budget.
  The invoice form explains stock allocation and the workspace-gated non-stock
  alternative to admins who have no available stock.
- Firestore Rules Emulator: `128 passing`; focused invoice widget tests:
  `00:01 +2: All tests passed!`. Production Rules/indexes deployment, release
  builds, device acceptance, commit, and push were not performed.

2026-10-24 inactive-workspace lifecycle recovery — unreleased source:

- Selected platform super-admins can establish audited support context for an
  existing inactive workspace, then restore it through the tenant lifecycle
  notifier and confirmation UI. Archive/restore changes the tenant lifecycle
  document only; it does not deactivate or reactivate member profiles.
  Firestore Rules continue denying business access while the tenant is
  inactive, and tenant-root hard deletion remains denied.
- Focused localization, error-mapping, and tenant-management tests:
  `00:04 +60: All tests passed!`; `flutter analyze lib --no-pub`:
  `No issues found! (ran in 262.6s)`; `dart analyze test/`:
  `No issues found!`; Rules Emulator: `129 passing (35s)`.
- Markdown lint and `git diff --check` exited 0. The three legacy maintenance
  scripts each exited 1 with a disabled message. No production Rules
  deployment, release build, device install, commit, or push was performed.

2026-10-24 seller phone backup and restricted restore — unreleased source:

- Sellers can create encrypted assigned-route archives, save them to phone
  storage, import them later, and explicitly upload saved archives to Drive
  when online and OAuth is configured. Drive upload is not background sync.
- Restore accepts only the seller's own eligible unlinked cash-in/cash-out
  rows for currently assigned routes. Each imported ledger row and matching
  shop-balance delta commit atomically; invoice, inventory, and other sellers'
  rows are not restored. Cached latest-transaction fields update only when the
  restored row is newer.
- Focused backup, policy, user-model, and transaction-provider suites:
  `00:07 +43: All tests passed!`; `flutter analyze lib --no-pub`:
  `No issues found! (ran in 28.9s)`; `dart analyze test/`:
  `No issues found!`. Release, deployment, visual-device acceptance, commit,
  and push were not performed.
- Router authorization now uses the same seller backup capability as the
  profile entry point. A route-level regression confirms assigned-route sellers
  can open `/settings/backup` and sellers without a route remain redirected.
  Combined router, backup-screen, destination, and role suite:
  `00:04 +33: All tests passed!`; `flutter analyze lib --no-pub`:
  `No issues found! (ran in 6.4s)`; `dart analyze test/`: `No issues found!`.
- Android debug build was attempted but Gradle could not resolve
  `androidx.lifecycle:lifecycle-runtime:2.10.0` because DNS lookups for
  `dl.google.com` and `repo.maven.apache.org` failed. It ended with
  `BUILD FAILED in 1m 17s`; no release build, deployment, or installation was
  performed.

Unreleased shared frontend accessibility foundation:

- `AppTokens.minTouchTarget` sets the shared 48-logical-pixel control target;
  the filter-chip bar uses it. `AppMotion` respects reduced-motion settings in
  empty/error illustrations, stat-card value transitions, and status-chip
  transitions. Balance badge semantics follow EN/AR/UR.
- Focused shared-widget suite: `00:05 +15: All tests passed!`. Full Flutter
  suite: `00:57 +538: All tests passed!`. `flutter analyze lib --no-pub`:
  `No issues found! (ran in 7.3s)`; `dart analyze test/`: `No issues found!`.
- Markdown lint and `git diff --check` exited 0. No authenticated browser/device
  visual review, release build, deployment, commit, or push was performed.

2026-10-24 reduced-motion preset hardening — unreleased source:

- All `AppAnimations` entrance, list, shimmer, shake, slide, fade, bounce,
  stagger, pop, and tab presets now bypass optional effects when
  `MediaQuery.disableAnimations` is enabled. `PressableWidget` retains its tap
  action without scale feedback.
- Both custom GoRouter page-transition builders now return the route child
  directly when reduced motion is enabled; normal fade/scale and form slide
  transitions remain unchanged when motion is allowed.
- Added widget coverage for disabled and enabled presets, visibility of their
  children, press action, semantic tap action, and route fade/slide behavior.
  Router regression: `00:05 +6: All tests passed!`; full Flutter suite:
  `01:01 +589: All tests passed!`. `flutter analyze lib --no-pub`:
  `No issues found! (ran in 102.3s)`; `dart analyze test/`: `No issues found!`.
- No business, provider, authorization, financial, inventory, route, or
  release-version behavior changed. Android device and authenticated visual
  acceptance remain unavailable. A local debug APK build failed during
  `:app:mergeDebugJavaResource` with an insufficient-system-resources error;
  no release build or production operation was performed.

2026-10-24 login responsive layout hardening — unreleased source:

- The narrow `/login` layout could construct invalid width constraints at
  intermediate window sizes (for example, a 620-pixel minimum with a 420-pixel
  maximum at 668 logical pixels). It now caps the content width to both 420
  logical pixels and the available window width.
- The regression covers 320, 360, 420, 668, 719, and 720 logical pixels in
  EN/AR/UR with locale directionality. The pre-fix test reproduced the
  normalized-constraints exception at 668 pixels. Focused login tests:
  `00:03 +3: All tests passed!`; full Flutter suite:
  `01:09 +585: All tests passed!`; `flutter analyze lib --no-pub`:
  `No issues found! (ran in 65.8s)`; `dart analyze test/`: `No issues found!`.
- The public login page was visually checked in the local browser after
  hot reload with no runtime errors. Authenticated role/theme acceptance,
  complete dialog/sheet interaction coverage, and Android device review
  remain pending. No release build, deployment, install, commit, or push was
  performed.

2026-10-22 CRUD edit-form loading hardening — unreleased source:

- Route, shop, product, and variant edit forms now wait for a usable auth
  profile and matching source record before exposing editable fields. Failed
  loads show mapped retry feedback; missing or out-of-scope records are not
  presented as editable defaults. Existing route assignments and form values
  are prefilled before submit is enabled.
- Provider role, tenant, and write safeguards are unchanged. Verification
  focused form suite: `00:08 +17: All tests passed!`; full Flutter suite:
  `01:03 +551: All tests passed!`; `flutter analyze lib --no-pub`:
  `No issues found! (ran in 43.2s)`; `dart analyze test/`: `No issues found!`.
  Markdown lint and `git diff --check` exited 0. No release build or
  production operation was performed. Details are in
  `docs/frontend/ui-ux-audit-report.md`.

2026-10-23 remaining screen-state sweep — unreleased source:

- The frontend register now maps all 32 registered route patterns and
  principal shell/contextual entry points. Invoice summaries group money by
  invoice currency; currency-filtered shop lists wait for route scope; invoice
  creation reports profile errors; profile dirty state resets when values are
  restored; notification mark-all exposes progress and mapped failures.
- Unlinked dashboard/history/notification rows no longer imply shop navigation.
  Stat-card entrance animation is suppressed when reduced motion is enabled.
  Provider, tenant, inventory, invoice, and authorization contracts are
  unchanged.
- Full Flutter suite: `01:20 +559: All tests passed!`;
  `flutter analyze lib --no-pub`: `No issues found! (ran in 99.6s)`;
  `dart analyze test/`: `No issues found!`. Details and the remaining
  unreviewed/visually unverified scope are in
  `docs/frontend/screen-register.md` and
  `docs/frontend/ui-ux-audit-report.md`.
- No authenticated browser page was shared, so rendered role/locale/theme
  acceptance remains pending. No release build, deployment, device install,
  version bump, commit, or push was performed.

2026-10-23 remaining screen-state review — unreleased source:

- Reviewed and dispositioned the named remaining route/screen findings:
  report export busy/error handling, seller route-option loading/error/retry
  and selection validation, shop-form route-query retry, backup/flush
  workspace readiness and query errors, and tenant-admin metadata-only
  presentation. Seller edit now checks both widget and dialog context
  lifetimes after awaiting the active profile.
- Follow-up currency tracing fixed account-statement PDF currency selection
  in both report and shop-detail exports. Seller report rows now retain their
  transaction route currency, current shop balances use the current route
  currency, Excel/PDF rows label their own currency, and PDF grand totals are
  grouped by currency. Admin export route metadata includes inactive routes
  so historical transaction rows can retain route currency context.
- Focused regressions passed for reports (`00:01 +1`), selected-workspace
  backup retry (`00:02 +1`), flush workspace/user retry (`00:01 +1`),
  tenant-admin role presentation (`00:00 +1`), user route options (`00:03 +1`),
  and shop-form route lookup (`00:00 +1`). `flutter analyze lib --no-pub`:
  `No issues found! (ran in 21.7s)`; `dart analyze test/`: `No issues found!`.
- Currency/PDF/export regressions: `00:07 +12: All tests passed!`;
  `flutter analyze lib --no-pub`: `No issues found! (ran in 10.7s)`;
  `dart analyze test/`: `No issues found!`.
- A serial run of the complete backup-screen test file exhausted the Dart VM
  after two cases with 1.71 GB free memory; the new retry regression passed
  when isolated. The current full Flutter suite was not rerun. Markdown lint
  and `git diff --check` are validated after this entry's documentation edits.
- Remaining scope: comprehensive dialog/sheet interaction inventory and
  authenticated browser/device acceptance across roles, themes, and locales.
  No release build, deployment, device install, version bump, commit, or push
  was performed.

2026-10-22 local RTL export hardening — unreleased source change:

- The shared PDF font-loading boundary now rejects builds without
  `--dart-define=use_arabic=true` and maps the typed failure to a localized
  message. Arabic and Urdu report tests verify the embedded Noto Sans Arabic
  font program and Urdu-specific characters; XLSX tests verify Unicode text
  and RTL worksheet direction. PDF, PNG, print, and share reuse the same PDF
  bytes. Noto Nastaliq remains a UI font only; full Nastaliq PDF shaping is
  unsupported by the current renderer.
- Verification: focused PDF/error/XLSX/image tests reported `All tests passed!`
  (54); locale parity reported `All tests passed!` (11);
  `flutter analyze lib --no-pub`: `No issues found! (ran in 23.3s)`;
  `dart analyze test/`: `No issues found!`; Markdown lint exited 0 with no
  output.
- Source-only work: release builds, production deployment, commit, and push
  have not been performed.

2026-10-22 financial workflows and RTL PDF release — v3.9.82+708:

- Workspace-admin transaction and invoice workflows now have regression coverage for standalone cash corrections, bad-debt write-off/recovery, sale invoices, receipts, credit notes, and voids. Financial rows remain linked to atomic shop-balance updates; invoice-linked transaction protections remain in place.
- Arabic/Urdu PDF shaping is enabled for local Flutter run/test actions, CI, release scripts, and web/APK builds. PDF label fallbacks use localized keys, and image export continues to rasterize the same shaped PDF bytes.
- `flutter analyze lib --no-pub`: `No issues found! (ran in 25.7s)`; `dart analyze test/`: `No issues found!`; Flutter tests: `01:14 +527: All tests passed!`; Firestore Rules Emulator: `117 passing (26s)`; Markdown lint and workflow YAML parsing completed without findings.
- Web build `EXIT: 0`; Firebase Hosting deploy completed. Split APKs: ARMv7 30.3 MB, ARM64 31.9 MB, x86_64 33.4 MB. Rules/indexes deployed successfully. Production has 23 indexes and 2 field overrides not listed locally; deployment did not force-delete them.
- ARM64 APK copied to `/sdcard/Download/app-arm64-v8a-release.apk` and installed on `R5GL22RGT9V` with `Success`; device reports versionName `3.9.82`, versionCode `3100908`. The app launched and the recent Flutter log filter showed no matching fatal or permission-denied entries; authenticated admin/seller workflow smoke tests were not performed.

2026-10-22 custom access purge, workspace CRUD, and Rules hardening — v3.9.81+707:

- Firebase Auth remains the sole sign-in mechanism; app-managed device pairing and custom session approvals were removed. Tenant-scoped workspace CRUD and existing sorting remain.
- Rules require active tenants, zero-balance shop creation without fabricated transaction summaries, and exact same-batch shop/balance links for standalone ledger entries. Invoice batches preserve their multi-row aggregate validation.
- Rules Emulator: `107 passing (25s)`; `flutter analyze lib --no-pub`: `No issues found! (ran in 109.5s)`; `dart analyze test/`: `No issues found!`; Flutter tests: `00:58 +528: All tests passed!`.
- Web `EXIT: 0`; Hosting and Rules/indexes deployment completed. Split APKs: 30.3/31.8/33.3 MB; ARM64 install on R5GL22RGT9V returned `Success`. No business-data migration was performed.
- The global Problems view retains diagnostics for deleted files; diagnostics scoped to current modified Dart files report no errors. Details are in SESSION_LOG.md.

2026-10-22 inactive-tenant and ledger creation Rules hardening — source version v3.9.80+706:

- Firestore Rules now require an active tenant for ordinary admin/seller
  business access, in addition to active user profiles. The selected
  super-admin tenant restoration path remains separately available.
- Shop creation rejects nonzero opening balances and seeded
  last-transaction metadata. Standalone transaction creates require a linked
  same-batch shop/balance update; seller invoice rows use the invoice/shop
  aggregate validation path to avoid duplicate per-row balance evaluation.
- Regression coverage reproduces tenant-active, opening-balance, orphan
  ledger, and mismatched-ledger findings. Full Rules Emulator suite:
  `107 passing (21s)`. Valid seller invoice batches initially exceeded the
  Rules expression limit; role-aware short-circuiting and reduced duplicate
  seller invoice checks resolved the failure, then the full suite passed.
- Rules and tests remain local. Production Firestore Rules/indexes, Hosting,
  and production data were not changed; no release build, commit, or push was
  performed.

2026-10-22 custom access removal and workspace CRUD verification — source version v3.9.80+706:

- Removed custom device registration, pairing approval, session-slot policy, client renewal/enforcement, related UI/routes/models/services, Firestore subcollection Rules, and obsolete composite indexes. Firebase Auth, active-profile/role checks, tenant boundaries, super-admin selected-workspace TTL, and append-only support-access logs remain.
- Workspace-admin route/shop/ledger Rules regressions cover tenant-scoped CRUD; shop creation and route-counter changes and ledger creation/balance updates are tested as atomic batches. Route/shop/transaction sort implementations were not rewritten. Standalone cash-in/cash-out corrections retain the mandated audited soft-delete and exact balance reversal; invoice-linked rows remain protected.
- `flutter analyze lib --no-pub`: `No issues found! (ran in 17.3s)`; `dart analyze test/`: `No issues found!`; full Flutter suite: `00:56 +528: All tests passed!`; Firestore Rules Emulator: `103 passing`; Markdown lint completed with exit 0 and no output.
- Focused test runner: 49 passed. App/rules/index source scan for custom access identifiers: no matches. Production Rules/Hosting were not deployed; no APK/web release was built, no production documents were deleted, and no commit/push was made.

2026-10-18 workspace access and transaction integrity — v3.9.80+706:

- Workspace admins use installation-keyed paired-device records without a device-count cap; active sessions remain bounded by the shared platform policy. Seller device/session limits and seller pairing approval remain workspace-scoped.
- The dedicated paired-device registry shows account name/email, device model, app version, Android/OS version, status, and timestamps. It deduplicates per user/installation and caps live registry/profile reads at 200 documents each.
- Pairing-disabled pending seller devices can self-activate; pairing-enabled devices still require administrator approval. Workspace settings toggles rebuild their dialog route correctly.
- Transaction deletion is soft-delete only. Workspace admins may reverse standalone cash-in/cash-out entries only in the same batch as an exact shop-balance correction; sellers and invoice-linked transactions cannot be deleted.
- Firestore Rules Emulator: `133 passing`. `flutter analyze lib --no-pub`: `No issues found! (ran in 8.4s)`; `dart analyze test/`: `No issues found!`; `flutter test -r expanded`: `All tests passed!` (577). Markdown lint produced no findings; Firestore indexes JSON parsed successfully.
- APK build was not started: free RAM was `2.64 GB`, below the required `3.2 GB` threshold, after stopping the project Gradle daemon (none were running). Production Rules/indexes and Hosting were not deployed; no device install was attempted.

2026-10-17 workspace owner and access controls — v3.9.79+705:

- Workspace creation provisions a tenant-scoped owner account after workspace creation; owner choices are limited to active tenant administrators.
- Workspace-admin seller deactivation atomically updates account status and revokes every bounded active session slot. The security registry supports per-device revoke/block and per-session termination, scoped to the selected workspace.
- Device/session slots are per user; shared hardware does not consume another account's capacity. Firestore Rules still do not bind ordinary business requests to a client session ID.
- Release verification is in progress; append exact analyzer, test, build, deployment, Git, and device evidence after the gates complete.

2026-10-16 workspace UX and branding — v3.9.78+704:

- Workspace owner selection is scoped to the selected workspace; creating a workspace no longer waits on a global users stream. Full workspace edit actions require active super-admin access, and save state is cleared on validation and write failures.
- Generic `StateError`/`No element` messages no longer map to PDF failure. Android adaptive icon foreground scale now matches the web artwork, and shop invoice actions have a visible gap.
- Flutter analysis: `No issues found! (ran in 10.9s)`; Dart test analysis: `No issues found!`; expanded Flutter suite: `All tests passed!` (564); Firestore Rules Emulator: 122 passing; Markdown lint: no output.
- Web build `EXIT: 0`; Hosting and rules/indexes deployment completed. Split APKs: ARMv7 30.5 MB, ARM64 32.1 MB, x86_64 33.6 MB. ARM64 install on R5GL22RGT9V reported `Success`; device reports versionName `3.9.78`, versionCode `3100504`.
- Changes remain uncommitted; no commit or push was requested.

2026-10-16 invoice integrity and transaction notes — v3.9.77+703:

- Non-stock invoices now default to disabled in the model, UI, provider, and Firestore Rules; workspaces must explicitly opt in.
- Sale and credit-note creation atomically update the tenant invoice counter, invoice, ledger, shop balance, and stock. Cash receipts and credit notes require linked ledger/shop writes; admin and seller paths validate role-specific balance deltas. Credit-note voids reverse original credit totals and stock movements, with inventory audit rows.
- Non-stock invoices default to disabled. Shop transaction descriptions support multiple lines. Rules Emulator: 122 passing; Flutter suite: 561 passing; `flutter analyze lib --no-pub` and `dart analyze test/` clean; Markdown lint clean. Web/APK builds, authorized deployment, and phone install are pending.

2026-10-16 session access recheck and remediation — v3.9.76+702 (deployed and installed):

- Workspace device pairing is a seller policy. Workspace admins use the shared platform cap, register active devices without seller approval, and can resume their own matching pending slot in place only while it remains within that cap. Sellers remain subject to approval when pairing is enabled; self-approval remains denied.
- Platform-session reactivation accepts removal of `revoked_at` and `terminated_by` only in the owner super-admin reactivation branch. Tenant and platform renewal reject revoked-only records but ignore unrelated old revoked slots when a valid live record exists for the same installation.
- Tenant logout revokes every active session for the current installation in one batch. A pending renewal ends the checked UID's session rather than looping. Renewal enforcement uses typed session-access errors.
- Missing `settings/platform_access_policy` uses the documented defaults (3 workspace-admin devices, 2 active sessions). Firestore Rules Emulator: 113 passing; Flutter tests: 562 passing; both analyzers clean. Rules/indexes deployment completed. Split APKs built: ARMv7 30.5 MB, ARM64 32.1 MB, x86_64 33.6 MB. ARM64 APK installed on `R5GL22RGT9V`; ADB reported `Success`, and the device reports versionName `3.9.76`, versionCode `3100302`. No authenticated sign-in smoke test or Firebase Hosting deployment was performed.

2026-10-15 auth/session and invoice completion — v3.9.75+102:

- Tenant registration resolves the actual paired device slot and validates its installation ID; local session models no longer cast unresolved Firestore server-timestamp sentinels to `Timestamp` after a successful write.
- `SessionGuard` defers missing-session enforcement through the registration grace, queues authoritative checks, scopes every automatic sign-out to the checked UID, and re-arms renewal on resume/role changes. Revoked tenant and platform sessions cannot be restored by renewal.
- Workspace-admin caps are platform-configured and shared across workspaces; sellers use per-workspace configurable caps; super-admin platform sessions use separate two-device/one-active-session slots. Rules and security UI enforce/display the same policy.
- Invoice void status, balance, stock restoration, and reversal transactions now commit atomically. Cash-refund ledger rows reconcile with the outstanding balance delta.
- Receipt sequences are bound to the same atomic workspace counter update by Rules. Invoice PDFs localize receipt methods, distinguish non-stock lines, and paginate with a dynamic page count.
- Android versionCode now exceeds the highest code reported by the connected phone, allowing an in-place upgrade without uninstalling app data.
- Firestore Rules Emulator: 106 passing. Focused auth, policy, invoice, PDF, dashboard, and localization regressions pass. Full release gates, deployment, install, commit, and push pending.

2026-10-15 workspace invoicing — v3.9.61+100:

- Invoice entry supports stock sale, tenant-enabled non-stock catalog sale, and cash receipt modes. Non-stock is selected by default, creates catalog line items without seller inventory deductions, and is available from shop detail with that shop preselected.
- Cash receipt numbering, receipt invoice, cash-in transaction, and shop balance delta are atomic and tenant-scoped. Firestore rules require invoice/transaction linkage, the matching receipt amount, and the exact balance change.
- Workspace administrators configure bilingual invoice branding, layout, accent, contact fields, and visibility. Invoice records capture a workspace header snapshot; seller-created snapshots must match workspace settings.
- Voiding non-stock sales does not restore warehouse inventory. Invoice list/detail and PDFs identify receipts separately.
- Firestore Rules Emulator: 102 passing. Focused settings/invoice/PDF/localization tests pass. Full release gates remain pending.

2026-10-10 authentication, sessions, and device pairing — v3.9.60+99:

- Login stays on `/login` until access registration completes, retains mapped failures, and counts only credential failures toward retry lockout.
- Active members can read their own workspace policy and missing access slots. Workspace registry collection-group reads have tenant-scoped rules and field indexes; legacy tenant records may omit the redundant `tenant_id`.
- Session checks use server-sourced records, renew while foregrounded and on resume, warn five minutes before expiry, detect device clock skew, and recover device registrations inactive for 30 days. New workspace defaults are three devices and two sessions.
- Pairing now follows pending/approved device slots. Workspace administrators can approve, remove, block, or reset devices; removal and related active-session revocation are atomic. Legacy per-user pairing fields and controls were removed.
- Super-admin login sessions use owner-scoped `users/{uid}/platform_sessions`, separate from tenant business sessions. Session enforcement remains client-side under the Spark architecture; it is not a Firestore authorization boundary.
- Firestore Rules Emulator: 95 passing. Focused Flutter auth/session/localization tests: 18 passing. Full release build/deploy/install and signoff remain pending.

2026-10-03 workspace login and frontend recovery — v3.9.59+98:

- Seller and workspace-admin login had a shared access-registration failure: the client read unallocated slot documents, while rules evaluate tenant fields on existing documents; the session stream was also unfiltered, and session writes omitted the paired `device_slot_id` required by the existing rules.
- Client access reads now query by `tenant_id` and `user_id`, transactionally refresh existing slots, create missing slots, and write the device-slot link. Rules and authorization semantics are unchanged.
- Registration errors retain their original mapped cause instead of being mislabeled as session-limit failures. A 15-second registration grace in `SessionGuard` prevents stale initial snapshots from signing out the current UID before registration settles.
- Workspace cards tolerate a temporarily unavailable auth profile; create/update failures remain visible; the owner selector uses the shared retryable error state; login status-bar icon contrast follows the active theme.
- Emulator tests cover the missing-slot denial and scoped-query allowance. Phone logs captured Firestore permission failures and the app returning to login; a post-fix authenticated login and workspace creation still require owner-entered credentials for visual verification.
- Broad UI audit: see `AUDIT_REPORT_FOOTWEAR_ERP.md`; unresolved multi-role, multi-theme, RTL, large-text, tablet, and performance profiling items are explicitly marked there.

2026-10-03 backup destinations and workspace archival — v3.9.58+97:

- Backup actions distinguish encrypted file export from Google Drive; Drive uploads do not create duplicate local copies, and automatic Drive backup stays unavailable until OAuth is configured.
- Restore confirmation reflects merge versus replacement scope, and local archives can be deleted from the device restore picker.
- Workspace archival revokes member device/session access before recording the archived state; Firestore rules bind session creation to a registered device and reject inactive users.

2026-10-03 frontend accessibility pass — v3.9.54+93:

- Status chips now render translated status text and localized screen-reader labels for EN/AR/UR. Unknown values use a localized fallback.
- High-contrast semantic status colors were raised to at least 4.5:1 against black and are applied only in high-contrast mode.
- Python workspace default is `C:\Python314\python.exe` (Python 3.14.2); Pylance reports it as the selected environment.
- Focused status-chip and locale-parity tests pass. Live visual verification remains blocked: no Android device is connected, and the local Flutter web debug VM exited with an out-of-memory error before rendering.

2026-09-26 security remediation — v3.9.52+91:

- Revoked exposed service-account key `e3e6afda...`; IAM lookup after revocation returned 404.
- Deleted `admin_config/sa_credentials` from the live Firestore project and removed the credential payload from the local backup; backup tooling no longer exports `admin_config`.
- Removed the client service-account/JWT Identity Toolkit service and direct arbitrary-user email/password/verification mutation methods. User editor now uses owner-controlled credentials and standard password-reset email.
- Super-admin now sees platform workspace metadata by default; business records require explicit `active_workspace_id` plus a reason of at least 10 characters. Start/end events are append-only in `platform_access_logs`.
- Firestore rules enforce selected-workspace scope; client super-admin creation/promotion is denied. User/business updates cannot change a document's tenant ID.
- Pending verification: emulator rules tests and production app release build/install for v3.9.52+91.

2026-04-XX audit v22 — v3.9.4+81:

- **Last-tx display fixed for all shops:** Root cause — `last_transaction_type`/`last_transaction_amount` fields only exist on shop docs written AFTER v3.9.2+79; pre-existing shops all had `null` → `_LastTxRow` and `_LastTxSubtitle` returned `SizedBox.shrink()` → nothing shown
- **Client-side analytics fallback:** Both `shops_list_screen.dart` and `route_detail_screen.dart` now pre-compute a `lastTxByShop` map from the already-loaded `shopsAnalyticsTransactionsProvider` (500-tx window, DESC order) — first entry per shop = most recent. Zero extra Firestore reads.
- **Sort improved for old shops:** Collective sort and route detail sort now use `shop.lastTransactionAt ?? lastTxByShop[shop.id]?.at` so shops with transactions but without the cached timestamp field still sort by real activity date.
- **Route number removed from shops tile subtitle:** `_ShopTile` subtitle line 1 no longer shows `R{routeNumber}` unconditionally; it only appears when `hasDuplicate == true` (to disambiguate shops with identical names). Subtitle line 2 now shows last-tx In/Out + amount for all shops.
- **Currency fix in route_detail_screen:** `_LastTxSubtitle` was reading from `settingsProvider` (wrong global currency); now accepts `currency` param and uses `route.currency` (the route's canonical currency, same as the trailing balance). Removed unused `settingsProvider` import.
- **`cloud_firestore` import added:** Both screens needed explicit `Timestamp` import for the record type; `sum` accumulator renamed to `acc` in 4 fold callbacks to resolve `avoid_types_as_parameter_names` lint (cloud_firestore exports `Sum` class).
- **All 422 tests passing**, `No issues found!` (flutter + dart analyze), web EXIT: 0, APK 75.2MB installed to R5GL22RGT9V, hosting + Firestore deployed, commit `6b97cfb` pushed to main
- **Audit score: 97/100 → 97/100** (bug fix — no new features)

2026-04-XX audit v21 — v3.9.3+80:

- **Tile subtitle deduplication:** Removed redundant `· Bal [balance]` suffix from `_LastTxSubtitle` (route_detail_screen) and `_LastTxRow` (shops_list_screen) — balance already visible in red trailing column; now shows only `[arrow] [In/Out] [amount]`; when no transaction yet shows `SizedBox.shrink()` instead of duplicating balance text
- **Sort by latest activity:** Both screens already had sort by `lastTransactionAt` DESC (null → bottom, tie-break by name) — confirmed correct and unchanged
- **Version bump:** 3.9.2+79 → 3.9.3+80 (versionCode 3090380); changelog entry added (trilingual EN/AR/UR)
- **All 422 tests passing**, `No issues found!` (flutter + dart analyze), web EXIT: 0, APK 75.1MB installed to R5GL22RGT9V (versionCode=3090380 versionName=3.9.3 confirmed), hosting + Firestore deployed, commit `c43c67d` pushed to main
- **Audit score: 96/100 → 97/100**

2026-04-XX audit v20 — v3.9.2+79:

- **11 audit findings resolved:** L10n keys `lbl_in`, `payment`, `no_access` added to all 3 locales; orphan composite index `invoices(customer_id+created_at)` removed from `firestore.indexes.json` and deleted from production Firestore; hardcoded "Notifications"/"Profile" strings in `app_shell.dart` replaced with L10n lookups; `Colors.white` in `notification_center_screen.dart` replaced with `AppBrand.onPrimary`
- **ShopModel extended:** `lastTransactionType: String?` + `lastTransactionAmount: double?` fields added (constructor, fromJson, toJson conditional, copyWith)
- **Write site completeness:** All 10 shop-update write sites now stamp `last_transaction_type` + `last_transaction_amount` (transaction_provider: 4 sites, invoice_provider: 4 sites, shop_provider: 2 sites — markAsBadDebt + recoverBadDebt)
- **Last-tx subtitle row added:** `_LastTxSubtitle` widget in `route_detail_screen.dart` and `_LastTxRow` widget in `shops_list_screen.dart` — both show `[arrow] [In/Out] [amount] · Bal [balance]` (or `Bal [balance]` when no transaction yet), live-updating via Riverpod stream
- **copyWith added to 3 models:** `InvoiceModel` (25 fields), `NotificationModel` (16 fields), `TransactionModel` (29 fields)
- **7 new tests added:** 4 in `shop_model_test.dart` (lastTransaction fields), 3 in `transaction_model_test.dart` (copyWith); **All 422 tests passing**, `No issues found!` (flutter + dart analyze), web EXIT: 0, APK 75.1MB, hosting + Firestore deployed, commit `9631d4d` pushed to main
- **Audit score: 94/100 → 96/100**

2026-04-18 audit v19 — v3.8.5+74:

- **L10n hardcoded string sweep:** Added 4 missing L10n keys (`lbl_out`, `no_data_available`, `share_product`, `open_source_sub`) to all 3 locale maps (EN/AR/UR); fixed 4 hardcoded strings in `product_detail_screen.dart` (share tooltip, In Stock label, Out label, quantity subtitle) and 1 in `about_screen.dart` (open source subtitle); `app_chart_card.dart` already referenced `no_data_available` key which was missing — now resolved
- **Firestore security hardening:** Products create/update rule now validates `image_url` must start with `https://` when set and is a non-empty string (null/absent/empty allowed); transaction seller-update rules now validate `edit_request_new_amount > 0` in both approval-required and direct-edit blocks — prevents sellers submitting zero or negative edit amounts
- **PNG codec safety:** `_withWhiteBackground()` in `export_sheet.dart` now wrapped in try-catch with `debugPrint` and rethrows `Exception('pdf_export_failed')` — prevents raw codec crashes surfacing as unhandled exceptions
- **Phase 2 provider safety:** Confirmed `alertCountsProvider` already invalidated in `_invalidateRoleScopedProviders()`; `productsProvider` is `autoDispose` (self-cancels); auth bootstrap direct write to `settings/global` documented as acceptable exception (bootstrap path, not screen/widget)
- **Changelog v3.8.5 entry added:** Trilingual EN/AR/UR, 2 bullet points (L10n + security)
- **All 398 tests passing**, `No issues found!` (flutter + dart analyze), web EXIT: 0, APK 75.1MB, hosting + Firestore deployed, commit `180858b` pushed to main
- **Audit score: 93/100 → 94/100**

2026-04-17 audit v18 — v3.7.9+57:

- **PDF font shaping fix (Arabic/Urdu):** Root cause — `ByteData.view(bytes.buffer)` in `_fontsFromBytes()` ignored `offsetInBytes`, corrupting font data when `rootBundle.load()` returns non-zero offset; fix: `Uint8List.fromList()` copy during loading + defense-in-depth offset params in `_fontsFromBytes`; Arabic/Urdu letter joining (GSUB tables) now parsed correctly
- **Shop detail PDF ledger export fixed:** Root cause — `ExportSheet.show()` in `shop_detail_screen.dart` had no `pdfBytesBuilder`; generic `buildPdfTable()` fallback failed → "PDF generation failed. Try Excel export instead."; fix: wired `buildPdfLedger()` with NameResolver, opening balance, 16-key labels map, locale-aware currency
- **Export governance established:** New AGENTS.md rules 23-25 (pdfBytesBuilder mandate, changelog_data.dart on every version bump, task continuity mandatory); CLAUDE.md Hard Rules 19-21 added; 3 new Vibe-Coded Debt Signal rows; analytics-reporting SKILL.md expanded with pdfBytesBuilder requirement table + call site audit; inline-audit SKILL.md checklist expanded (4 new items) + 3 new failure signatures; `.github/instructions/export-governance.instructions.md` created
- **Changelog backfilled:** v3.7.7, v3.7.8, v3.7.9 entries added to `changelog_data.dart` — total 6 version entries, all trilingual EN/AR/UR
- **ExportSheet.show() audit:** All 11 call sites verified — 3 ledger/report exports correctly pass `pdfBytesBuilder`, 8 flat table exports correctly use default generic fallback
- **All 396 tests passing**, zero analyze issues, web + APK built, hosting + Firestore deployed
- **Audit score: 91/100 → 93/100**

2026-04-16 audit v17 — v3.7.6+54:

- **WhatsApp-style changelog sheet shipped:** `whats_new_sheet.dart` — DraggableScrollableSheet (90% height), emoji bullets, trilingual EN/AR/UR, RTL-aware; auto-shown once per version via `app_shell.dart` postFrameCallback; accessible from About screen via "What's New" tile; `changelog_data.dart` with 3 version entries; `changelog_provider.dart` SharedPreferences-backed version tracking
- **PDF "Something went wrong" fixed:** Root cause — `allUsersProvider` autoDispose race → `StateError('Bad state: No element')`; fixed in `error_mapper.dart` (bad state → `err_pdf_failed`), `shop_detail_screen.dart` (`.value ?? []`, `_generatingPdf` guard, role-aware `showEntryBy: isAdmin`), `reports_screen.dart` (same `.value ?? []` fix)
- **80-agent audit completed:** Financial 100/100 PERFECT, Security 92/100, Code Quality 95/100, CI/CD 85/100, Firebase 88/100, L10n 85/100, Testing 65→75/100 (post-fix), Navigation 88/100
- **Security fix S7:** `sellerInventoryProvider` family added to `_invalidateRoleScopedProviders()` in `auth_provider.dart` — prevents seller-session data leak on signout (defense-in-depth)
- **Test coverage expanded:** `changelog_data_test.dart` (7 tests), `changelog_provider_test.dart` (6 tests), `error_mapper_test.dart` + 3 StateError/bad-state cases; total **396 tests all passing**
- **Import path bug fixed:** `whats_new_sheet.dart` had wrong `../constants/` paths (missing `core/`); corrected to `../core/constants/`, `../core/data/`, `../core/l10n/`, `../providers/`
- **Lint fixes:** `unnecessary_underscores` in errorBuilder lambda, `no_leading_underscores_for_local_identifiers` in `_tr()` local map — analyze clean
- **Deferred to v3.7.7:** L2 hardcoded tooltips (users_list_screen, about_screen, login_screen); N5 deep link intent filter in AndroidManifest; integration tests for auth/invoice/dashboard flows
- **Audit score: 90/100 → 91/100**

2026-04-15 audit v16 — v3.7.5+53:

- **Post-audit hardening sweep completed (this session):** route/shop form create guards tightened; auth and network stream providers now use `autoDispose`; transaction export queries capped at `2000` docs; inventory return dialog controller disposal fixed; shimmer placeholders now use theme-derived surface colors; offline indicator uses semantic error color
- **Model + widget resilience improved:** `ProductModel`, `RouteModel`, `SettingsModel`, `SellerInventoryModel`, and `InventoryTransactionModel` now expose `copyWith` / equality semantics where required; `TransactionModel` gained explicit `payment` / `write_off` constants and throws on unknown balance-impact types; export tiles, empty states, filter chips, stat cards, and amount field gained stable keys
- **Regression coverage expanded:** unit tests added for new model `copyWith` behavior, equality semantics, settings assertions, and transaction ledger edge cases (`payment`, `write_off`, unknown type)
- **Workflow drift corrected:** manual APK, CI, and release workflows aligned on Flutter `3.41.6` with expanded test reporting; release validation timeout increased; Firebase Hosting immutable cache rules now include `.wasm`

2026-04-14 audit v15 — v3.7.2+50:

- **Governance hardened (this session):** AGENTS.md §8 rewritten as 14-step mandatory signoff sequence (non-bypassable);
  CLAUDE.md "Six Non-Negotiable" expanded to "Twelve Non-Negotiable Pre-Signoff Steps"; Anti-Bypass Enforcement
  Matrix extended with 5 new rows (Dart analyze, Firestore rules deployed, Indexes deployed,
  Hosting deployed, Commit pushed, APK installed); ci.yml Gates 16–17 added (Firestore
  files valid, no temp artifacts); deploy-web.yml now deploys Firestore rules/indexes
  before Hosting; inline-audit SKILL.md §8 release sequence added; github-workflows SKILL.md
  updated to 17 gates + mandatory pre-signoff table
- **Email verification sync fixed:** `AuthNotifier.syncEmailVerification()` added;
  called from `_onAppResumed()` in `session_guard.dart` — catches the case where user
  verifies while app is backgrounded without requiring re-login
- **widget_test.dart lint fixed:** `library;` directive added — resolves
  `dangling_library_doc_comments` that was showing in VS Code Problems tab
- **Navbar logo streamlined:** App logo removed from `_WhatsAppBar` title area;
  `_UserAvatar` now renders the app logo image instead of text initials — more
  AppBar space, brand-consistent avatar
- **Crashlytics version key fixed:** was hardcoded `'3.5.2+45'`; replaced with
  `AppBrand.versionDisplay` (inline-audit catch)
- **Audit score: 88/100 → 90/100**

2026-04-13 audit v14 — v3.7.0+48:

- **Dep stack fully upgraded:** fl_chart 1.2.0 (backward-compat, zero code changes required), share_plus 13.0.0 (migrated to `SharePlus.instance.share(ShareParams(...))` at 4 sites + `download_helper_stub.dart`), permission_handler 12.0.1 (API unchanged), dart_jsonwebtoken 3.4.0 (API unchanged — only UTC DateTime for NumericDate; no code changes), flutter_lints 6.0.0
- **30 lint issues fixed:** 15 × `unnecessary_underscores` (new flutter_lints 6 rule — `(_, __)` → `(_, _)` across 9 files), 3 × `use_null_aware_elements` in `transaction_provider.dart` (`'key': ?value` syntax), 1 × `prefer_const_constructors` in `reports_screen.dart`, 8 × share_plus deprecations → `SharePlus.instance.share(ShareParams(...))` at 5 files; final: **No issues found!**
- **Navigation/gesture overhaul:** WhatsApp-style double-back exit implemented in AppShell; all shell-hosted screen AppBars stripped; detail screens converted to inline action rows; back gesture works from all nav destinations
- **flutter_lints 6 new rules in codebase:** `use_null_aware_elements`, `unnecessary_underscores` — both fully resolved
- **All 4 CI workflows standardized:** `build-apk.yml` corrected from Flutter 3.29.2 → 3.41.6; all 4 workflows now pin Flutter 3.41.6
- **CI Gate 15 added:** StateProvider banned — `grep -rn "StateProvider\b" app/lib/ --include="*.dart"` → zero
- **Markdown governance hardened:** `.markdownlint.json` updated (MD024 siblings_only, MD056 disabled); all 90 existing markdown issues auto-fixed to zero; `.claude/skills/markdown-governance/SKILL.md` created; `.github/instructions/markdown-governance.instructions.md` created; pre-commit checklist Gate 8 now includes temp-artifact check
- **Temp artifact cleanup:** `auth-users.json`, `check_locale.ps1`, `check_locale.py`, `debug.log` deleted; `.gitignore` updated to cover installer flags (`*.flag`)
- **Governance hardened:** AGENTS.md Rules 19–22 added; CLAUDE.md Chain 6 + Anti-Bypass Enforcement Matrix + Governance Notes updated; README.md × 2 fully rewritten
- **APK v3.7.0+48:** installed to CPH2621 (Android 16/API 36) via ADB; web deployed to Firebase Hosting
- **Audit score: 85/100 → 88/100**

2026-04-11 audit v13 — v3.5.0+43:

- Governance layer established: REGRESSION_REGISTRY.md (15 RR entries, 6 PI items), SESSION_LOG.md (8 sessions), MASTER_BLUEPRINT.md, CHANGELOG.md, AUDIT_REPORT_FOOTWEAR_ERP.md
- CI/CD hardened: all 4 workflows pinned to Flutter 3.29.2; timeout-minutes added (20/30/10/45 mins); test job now runs with --coverage; 11 hygiene gates (was 6); APK size gate in release.yml; .github/baselines/apk_size_kb.txt established
- Color hygiene: 15 hardcoded Colors.white/grey/red/black54/black.withAlpha instances in 6 screens replaced with `AppBrand.*` / `cs.*` constants (dark-mode safe) — RR-011 closed
- widget_test.dart placeholder replaced with auth-flow smoke tests + GoRouter absent-state check — RR-013 closed
- Firestore rules emulator test scaffold created: tests/firestore-rules/ (package.json + rules.test.js)
- Security fix RR-015: Firestore transaction rule approval-disabled path over-permissioned `amount`+`type` fields for sellers; restricted to `description`, `updated_at`, `updated_by`, `edit_request_*` only — prevents fraudulent amount/type manipulation
- Audit score: 72/100 → 79/100

2026-04-11 audit v12 — v3.4.11+42:

- Spark free-tier hardening: capped the shops analytics listener at 500 docs and the live shop-detail ledger listener at 150 docs, while preserving full-history account-statement exports through one-shot ordered queries
- Ledger display correctness: running-balance reconstruction now uses typed balance impact, return/payment/write-off entries no longer render like new debt, and the running-balance label is localized in the shop ledger UI
- Error/i18n + release workflow cleanup: role-aware invoices no longer depend on Riverpod's deprecated `.stream`, mapped localized `ErrorState` now replaces raw async exception text across the affected screens, invoice PDF totals labels and inactive badges are localized, hardcoded route `R` prefixes were removed from touched shop flows, inventory long-press no longer routes to itself, and `tool/release.ps1` is now compatible with Windows PowerShell 5.1

2026-04-11 audit v11 — v3.4.10+41:

- Shops analytics correction: `I got` / `I gave` chips on the shops screen now aggregate real `cash_in` / `cash_out` ledger entries, `I will get` stays tied to current outstanding balance, and seller analytics read route-scoped transactions via a dedicated `route_id + created_at` index

2026-04-11 audit v10 — v3.4.9+40:

- Invoice flow resilience: preselected shop auto-selection now uses a one-shot guard, and invoice detail supports back-context routing to the originating shop after invoice creation
- Seller edit approval hardening: sellers cannot edit invoice-linked transactions or re-submit while a prior edit request is pending; admin pending requests now surface on the dashboard
- Navigation cleanup: in-shell screen navigation now uses `context.go(...)`; admin quick actions route to the correct in-shell destinations; invoices and inventory bottom-nav long-press actions added
- Financial UX polish: discount field clarified as an absolute discount amount, invoice list status/search fixes shipped, account-statement PDF now renders Debit left / Credit right with LTR amount cells in RTL locales
- Validation + l10n: approval-flow strings localized in EN/AR/UR, validator min/max messages parameterized, password minimum raised to 8 chars across profile and admin/user-management paths
- Firestore coverage: added composite index for `transactions(edit_request_pending, created_at desc)`
- Android release stabilization: disabled Kotlin incremental compilation in `app/android/gradle.properties` to avoid Windows cross-drive cache crashes when Gradle compiles pub-cache plugins from `C:` against the workspace on `D:`

2026-04-09 audit v9 — v3.4.4+35:

- Firestore hotfix: admin user updates bypass write-rate throttle so route assignment edits no longer fail under rapid admin saves
- Route/shop detail providers now guard seller subscriptions client-side to avoid transient permission-denied UI
- Route assignment create/update moved to Firestore transactions; seller reassignment is normalized and concurrency-safe
- Login password-reset username lookup moved out of screen code into auth provider; account-statement export reads moved out of screen code into transaction provider
- Firestore index cleanup: removed 8 unused defensive composite indexes; active query coverage remains complete
- Validation: flutter analyze --no-pub clean, flutter test suite green, screen/widget Firestore hygiene scan cleared

2026-04-10 v3.4.5+36 — Wasm dep-lock eliminated:

- Root cause: `excel 4.0.6` locked `archive ^3.6.1` which prevented `image` from upgrading past 4.3.0; image 4.3.0 had `avoid_double_and_int_checks` violations that caused `flutter build web --release` Wasm dry-run to fail
- Fix: replaced `excel` with a custom minimal xlsx writer (`app/lib/core/utils/excel_export.dart`) using `archive ^4.0.0` directly; identical public API, same styled output
- Result: `image` resolved to 4.8.0 (Wasm clean since 4.6.0); `archive` resolved to 4.0.9; `flutter build web --release` Wasm dry-run now reports "succeeded"
- PowerShell false positive documented: `$LASTEXITCODE` is the authoritative check; pipe artefacts (`NativeCommandError`) do not reflect flutter's real exit code
- Documented as Chain 5 in CLAUDE.md Breakage Chain Reference + code-quality SKILL + inline-audit SKILL
- Version bumped to v3.4.5+36, web deployed, APK built

2026-04-10 process upgrade:

- Closed-loop ambiguity control added: Band-Aid Loop Reversal protocol (rule + instruction + skill + custom agent)
- Post-culprit workflow now requires explicit keep/remove decisioning for temporary mitigations

2026-04-07 audit v8 — v3.4.0+30 (autonomous 20-agent system):

- 20-agent CI/CD + self-healing system launched
- GitHub Actions: ci.yml (6 hygiene gates), build-apk.yml, release.yml, deploy-web.yml
- GitHub prompts: audit.prompt.md (20-agent run), post-impl-checklist.prompt.md
- GitHub instructions: collections, financial-integrity, testing, code-quality
- Skills: multi-agent-orchestration (Agents 16-20 added), inline-audit (breakage chains + grep gates),
  code-quality (new), shoeserp-runtime-hardening (auth pipeline playbook),
  user-management (3-step custom-token flow), github-workflows (new),
  testing-strategy (rules emulator tests, archive 4-test requirement, financial guards)
- Security fix A3: seller transaction rules restricted to ['description','updated_at'] only;
  updateTransactionNote() provider method; role-aware UI (seller sees annotation dialog, delete hidden)
- Session UX fix A4: 7h30m warning dialog before 8h hard cutoff; session_expiring_soon L10n × 3 langs
- AGENTS.md §4: Rules 17+18 added (provider leak guard, collection constants mandate)
- AGENTS.md §8: Hygiene grep gates added to pre-commit checklist
- CLAUDE.md: Breakage Chain Reference, Vibe-Coded Debt Signals, Five Pre-Commit Checks, Auth Pipeline
- Release: v3.4.0+30, split-per-ABI APK + web deployed

2026-04-06 audit v7 — v3.3.0+21:

- Admin is now a full seller: loads vehicle stock via Inventory → Transfer, sees own seller_inventory in invoice creation, creates invoices from own stock
- Invoice item restriction: all roles (admin + seller) must select ≥1 item; empty-item invoices blocked
- Transfer dialog: `sellersProvider` → `allUsersProvider` so admin appears as a recipient for self-transfer
- product_provider.transferToSeller: fixed audit log to write to `inventory_transactions` (not `transactions`); type corrected to `transfer_out` matching InventoryTransactionModel constants — was violating Firestore rules AND not appearing in transfer history
- customer transaction visibility fixed (v3.2.7+19): client-side `deleted != true` filter on all providers
- Build standard: split-per-ABI APK release path (`flutter build apk --release --split-per-abi --dart-define=USE_PLAY_INTEGRITY=true`), phone-delivery artifact set
- user_model: added `canHaveSellerInventory` getter (always true; admin = god tier)

2026-04-06 audit v6 — v3.2.6+18:

- 62-issue audit (15-agent synthesis) fully patched across Phases 1–8
- Financial integrity: createSaleInvoice amountReceived guard, voidInvoice atomic transaction, markAsPaid outstanding fallback fix
- Security: seller admin data leak guards (allInvoicesProvider, adminAllSellerInventoryProvider), voidInvoice admin-only check, isValidRole() in Firestore rules, invoice math validation in rules, transaction type+amount validation
- Dashboard: _lastGoodDashboardStatsProvider cache; graceful per-metric zero-fallback; no AsyncError propagation
- Android: ProGuard rules for 8+ plugins, isMinifyEnabled=true, isShrinkResources=true, signing fallback removed (throws GradleException)
- Signing: new release keystore footwear-erp.jks at D:\Footwear\footwear-erp.jks; storePassword=ShoeERP2024!; key.properties path fixed + BOM removed
- L10n: 3 new keys × 3 languages (err_url_open, err_whatsapp_unavailable, whatsapp_greeting)
- About screen: hardcoded EN strings replaced with tr() calls
- Dead code: search_provider.dart deleted (0 usages)
- Tests: 206 → 272 (added sanitizer_test, error_mapper_test, create_sale_invoice_guard_test, mark_paid_outstanding_test)
- Release: v3.2.6+18, 3 ABI-split APKs built + web deployed to Firebase Hosting

2026-03-30 enterprise v3.0.0 upgrade:

- Full 6-phase enterprise master plan (22 sections) implemented
- Firebase Storage fully removed — zero cost architecture (Firestore + Auth only, NO Cloud Functions)
- Cloud Functions dependency removed — user CRUD uses secondary FirebaseApp approach
- Company logo stored as base64 in Firestore settings doc (≤50KB cap, 256×256 compressed)
- Product image_url field supports external HTTP URLs only (no upload to Storage)
- Role normalization hardened in app + rules + storage.rules (regex matching)
- Dashboard aggregate fallback cache enabled
- Critical write screens map errors through AppErrorMapper
- SnackBar system redesigned: Material 3 container-color card-style (light bg + dark text + accent bar)
- All SnackBars across 19 screens converted to styled helpers (errorSnackBar/successSnackBar/warningSnackBar/infoSnackBar)
- Variant stock shown as cartons/dozens/pairs in product detail
- L10n: 372+ keys × 3 languages — perfect parity
- All 21 provider queries covered by 17 composite indexes + 1 new seller_inventory(active+variant_name)
- Provider write guards: created_by validation, admin-only product/variant creation
- Color consistency: all semantic colors use AppBrand constants
- Seller self-update rules: display_name, updated_at, last_active (session heartbeat)
- Edit user dialog: email read-only, password reset via email (no direct password setting)
- Multi-device tested: Samsung A56 (Android 16/API 36), V2247 (Android 14/API 34)
- Design system: app_tokens, app_animations, app_sanitizer, input_formatters
- 14 widgets (6 upgraded + 8 new), all with accessibility tooltips
- 5 list screens with search/filter/shimmer/pull-to-refresh/animations
- 7 forms standardized with PopScope/dirty-check/sanitizer/haptic
- 5 detail screens enriched with charts/badges/grouping
- Reports: monthly cash flow BarChart, outstanding PieChart
- PDF export: Isolate.run() for all 4 functions, sanitized interpolation (S-08)
- Session guard: AppLifecycleListener, 8h admin hard session limit (S-10)
- Firestore rules: docSizeOk() <50KB, withinWriteRate() 1s cooldown
- Dark mode QA: theme-aware colors throughout
- RTL QA: EdgeInsetsDirectional throughout
- Release: v3.0.0+7, 3 ABI-split APKs built

2026-10-24 consolidated release — v3.9.83+709:

- Full Flutter suite: `01:32 +589: All tests passed!`; changelog regression:
  `00:00 +10: All tests passed!`; `flutter analyze lib --no-pub`:
  `No issues found! (ran in 10.6s)`; `dart analyze test/`:
  `No issues found!`.
- Firestore Rules Emulator: `129 passing (23s)`. Rules/indexes deployed with
  `Deploy complete!`; 23 remote indexes and 2 field overrides absent locally
  were preserved (no `--force`).
- Web build `EXIT: 0`; Hosting deployment completed to
  `shoeserp-clean-20260327.web.app`. Split APKs built: ARMv7 30.4 MB, ARM64
  31.9 MB, x86_64 33.4 MB.
- Google Drive OAuth IDs were not available in the local build environment.
  Encrypted phone backup and restricted restore remain available; Drive
  upload requires OAuth configuration and a subsequent rebuild/redeploy.
- No device install, authenticated business-screen visual acceptance, or
  performance profile was performed. The wider frontend visual-acceptance
  mission remains partial.

2026-10-24 unreleased operational refresh and invoice-void integrity:

- Workspace settings/header forms rehydrate from Firestore snapshots until
  locally edited. Shops, invoices, shop ledgers, and settings expose pull-to-
  refresh. Shop flow totals keep route currencies separate and unabridged;
  invoice Pending includes only outstanding sale invoices. Receipt PDFs
  emphasize received amounts and include payment, balance, receiver, and
  signature details.
- Invoice voids now include every tenant-scoped transaction linked by
  `invoice_id`, including legacy settlement payments not recorded on older
  invoice documents. New settlement writes also append their transaction ID
  atomically to the invoice. Customer statements omit voided rows; a
  credit-balance void retains all actual cash-in payments as customer credit,
  while cash-refund voids hide those payments. Admin transaction history
  retains the audit rows.
- Full Flutter suite: `01:08 +599: All tests passed!`; focused invoice-void
  tests: `00:00 +22: All tests passed!`; `flutter analyze lib --no-pub`:
  `No issues found! (ran in 7.1s)`; `dart analyze test/`: `No issues found!`.
- Firestore Rules and indexes were not changed. No Rules deployment, release
  build, Hosting deployment, APK installation, commit, or push was performed.
- Authenticated web/APK cross-device freshness and visual acceptance remain
  unverified. Workspace-admin role promotion remains restricted to the
  selected platform super-admin path; no role authorization was changed.

2026-10-24 workspace backup scope and role validation — v3.9.84+710:

- Tenant backup reads now resolve `settings/{tenantId}` by its authorized
  document path instead of issuing a tenant-field list query that Firestore
  Rules cannot prove. Archive validation uses the concrete collection keys
  actually serialized for products and inventory, while retaining each role's
  narrower selection policy.
- Selected super-admin workspace backup remains explicit and metadata-only by
  default. Seller backups remain tenant- and assigned-route-scoped; restore
  accepts only the seller's own eligible unlinked cash rows, and rejects
  inventory records belonging to another seller. Workspace-admin role
  promotion remains reserved for the selected platform-super-admin path.
- Backup role widget/unit tests: `00:07 +16: All tests passed!`; full Flutter
  suite: `01:15 +603: All tests passed!`; `flutter analyze lib --no-pub`:
  `No issues found! (ran in 83.9s)`; `dart analyze test/`: `No issues found!`.
  Firestore Rules Emulator: `132 passing (48s)`. Firestore Rules/index
  deployment reported `Deploy complete!`; split APKs built at 30.4 MB,
  32.0 MB, and 33.4 MB. ARM64 APK install on `R5GL22RGT9V` reported
  `Success`; the device reports versionName `3.9.84`, versionCode `3101110`.
  Hosting deployment and Git publication are pending; a push to `main`
  triggers the Hosting workflow and requires explicit authorization.

2026-10-25 bilingual financial PDFs and seller invoice Rules — v3.9.85+711:

- Financial document language is workspace-configurable: English-Arabic is
  the default and English-Urdu is available to workspace administrators.
  New invoice snapshots preserve the selected pair; historical snapshots
  continue to control document reprints.
- Invoice, receipt, account-statement, seller, multi-shop, and flat financial
  report PDFs use paired labels. Ledger summary and table labels render
  English and RTL text on separate directionally explicit lines.
- Seller invoice writes accept optional legacy company-name fields and require
  the provider-generated language-pair snapshot to match the workspace setting.
  Tenant, seller-route, inventory, and atomic-balance safeguards remain.
- Full Flutter suite: `609` passed; Rules Emulator: `133 passing`; `flutter
  analyze lib --no-pub`: `No issues found! (ran in 9.2s)`; `dart analyze
  test/`: `No issues found!`. Release build, production deployment, device
  install, commit, and push remain pending.

2026-10-25 workspace administration and receipt detail — v3.10.1+1112:

- Workspace management presents owner contact and verification details, live
   member counts by role, and the free-tier limit of 10 active
   non-platform-super-admin members. Profile activation/deactivation and the
   tenant seat counter are checked as an atomic transition by Firestore Rules.
- Cash receipt detail and PDFs show a fuller payment, balance, shop, and
   receiver/signature breakdown without changing financial calculations.
- Google Drive OAuth client IDs are not configured for this release; Drive
   backup is disabled, while encrypted phone archives remain available.
- Full Flutter suite: `01:20 +623: All tests passed!`; `flutter analyze lib
   --no-pub`: `No issues found! (ran in 98.8s)`; `dart analyze test/`:
   `No issues found!`; Markdown lint exited 0 with no output.
- Firestore Rules Emulator: `140 passing (31s)`. Web build: `EXIT: 0`;
   Hosting and Firestore Rules/indexes deployments both reported
   `Deploy complete!`. The 23 remote indexes and 2 field overrides not listed
   locally were preserved.
- Split APKs built: ARMv7 30.6 MB, ARM64 32.1 MB, x86_64 33.6 MB.
   ARM64 copied to and installed on `R5GL22RGT9V` (`Success`); installed
   versionName is `3.10.1`, versionCode `3103212`. Feature commit `4d41f93`
   was pushed to `main`.

2026-10-25 workspace role, logo, and receipt corrections — v3.10.2+1113:

- Workspace-admin account management now permits creating canonical admin and
  seller accounts and promoting/demoting eligible same-workspace admin/seller
  users. The permanent owner, tenant-admin peers, platform roles, and
  peer-admin deactivation remain protected. User-profile changes and seat
  counter transitions stay atomic.
- Selected platform super-admins can reconcile a tenant's stored seat total
  against its fully paged active roster with revision checks. Workspace cards
  show role counts from the live roster only when the role has authorized
  access; otherwise the UI displays stored metadata and an actionable support
  context rather than a perpetual spinner. The free-tier limit remains 10
  active non-platform members.
- Workspace logos are resized and losslessly re-encoded locally, preserving
  alpha while reducing dimensions until the encoded value fits Firestore's
  limit. This deterministic image processing does not use offline AI.
- Cash-receipt detail and PDFs use a compact bilingual table and a single-page
  receipt layout. The balance-movement presentation was removed; financial
  writes and shop-balance accounting are unchanged. Financial PDFs reuse the
  shared compact bilingual workspace header.
- Full Flutter suite: `01:26 +623: All tests passed!`; changelog regression:
  `00:00 +10: All tests passed!`; `flutter analyze lib --no-pub`:
  `No issues found! (ran in 103.6s)`; `dart analyze test/`: `No issues found!`.
  Firestore Rules Emulator: `145 passing (31s)`.
- Web build `EXIT: 0`; Firebase Hosting and Firestore Rules/indexes each
  reported `Deploy complete!`. Split APKs: ARMv7 30.7 MB, ARM64 32.2 MB,
  x86_64 33.6 MB. ARM64 was copied to and installed on `R5GL22RGT9V`
  (`Success`, versionName `3.10.2`, versionCode `3103313`).

2026-10-25 legacy workspace roster completeness — v3.10.3+1114:

- Active and inactive workspace user streams now retain profiles lacking the
  optional `display_name` field and sort the complete results client-side.
  Seat reconciliation uses a tenant-scoped active-user query without that
  optional-field ordering, preventing legacy profiles from being omitted from
  the stored seat total.
- Added an emulator regression showing that Firestore `orderBy('display_name')`
  excludes a seeded legacy profile while the complete scoped query includes it.
- Full Flutter suite: `01:21 +623: All tests passed!`; `flutter analyze lib
  --no-pub`: `No issues found! (ran in 15.3s)`; `dart analyze test/`:
  `No issues found!`; Firestore Rules Emulator: `146 passing (37s)`.
- Web build `EXIT: 0`; Hosting deployment reported `Deploy complete!`.
  Firestore Rules/indexes were already deployed with v3.10.2 and no Rules or
  index files changed for this provider-only hotfix.
- Split APKs: ARMv7 30.7 MB, ARM64 32.2 MB, x86_64 33.6 MB. ARM64 installed
  on `R5GL22RGT9V` (`Success`, versionName `3.10.3`, versionCode `3103414`).

2026-10-25 combined release — v3.10.4+1115:

- Super-admin workspace support start/end now use the active context correctly,
  context switching is explicit, and localized feedback distinguishes success
  and failure. Regression coverage includes end-access, context switching,
  selected-workspace feedback, and expired-context errors.
- Bilingual PDF rows now pin physical LTR column order with
  `pw.Directionality`, while English and RTL text directions stay explicit.
  Fresh Arabic and Urdu account-statement PDFs were visually checked in
  Chrome: English appears left, the configured RTL language right, and Urdu
  is readable Naskh-style text.
- Nastaliq PDF rendering remains unimplemented. A separate `payv` proof
  showed shaped sample output, but logo embedding, text extraction, pagination,
  and all-report Web/Android parity are not proven. Production PDFs must not be
  described as Nastaliq.
- Full Flutter suite: `01:16 +628: All tests passed!`; focused access/PDF
  suite: `00:11 +65: All tests passed!`; `flutter analyze lib --no-pub`:
  `No issues found! (ran in 132.4s)`; `dart analyze test/`: `No issues found!`.
- Rules Emulator: `147 passing (29s)`. Web build `EXIT: 0`; Firebase Hosting
  and Firestore Rules/indexes both reported `Deploy complete!`. The 23 remote
  indexes and 2 field overrides absent locally were preserved.
- Split APKs: ARMv7 30.7 MB, ARM64 32.2 MB, x86_64 33.6 MB. `adb devices`
  showed only `List of devices attached`, so phone copy/install was skipped.
- Google Drive OAuth IDs remain unconfigured; Drive backup is disabled in
  these artifacts. Markdown lint and `git diff --check` exited 0.

2026-10-25 supervisor and Android bundle — v3.10.5+1116:

- The tenant-scoped `supervisor` role grants operational access to routes,
  shops, products, inventory, invoices, and reports without user
  administration, notifications, settings, backup, financial corrections,
  invoice voids, seller-route assignment, or shop-route reassignment.
  Legacy workspace admins can load the user list and restore backups in
  merge-only mode. Notification shop subscriptions now use stable sorted shop
  IDs, so read-state updates do not restart them.
- The Play Console AAB collision was caused by ABI APK splits remaining enabled
  during `bundleRelease`; Gradle now disables ABI splits for bundle tasks and
  retains them for APK tasks. Android versionCode generation is bounded and
  monotonic. Flutter adds an ABI-specific offset to split APK version codes.
- Full Flutter suite: `01:59 +633: All tests passed!`; focused role/backup/
  notification/users suite: `00:22 +55: All tests passed!`;
  `flutter analyze lib --no-pub`: `No issues found! (ran in 15.0s)`;
  `dart analyze test/`: `No issues found!`; Firestore Rules Emulator:
  `152 passing (33s)`. Markdown lint and `git diff --check` exited 0.
- Split APKs built: ARMv7 30.7 MB, ARM64 32.2 MB, x86_64 33.6 MB. Signed
  AAB: 54.8 MB. APK v2 signature verified; AAB verification reported
  `jar verified.`. ARM64 metadata reports versionName `3.10.5`,
  versionCode `310053116`. `flutter doctor` still reports unaccepted Android
  SDK licenses, although both release builds succeeded; licenses were not
  accepted automatically. These local v3.10.5 artifacts were superseded by
  the v3.10.6+1117 release below.

2026-10-25 bilingual statement layout and combined release — v3.10.6+1117:

- Account-statement PDFs now use an explicit three-column row under the shared
  workspace brand header: English title/report date/entry details on the left,
  shop name and statement duration centered, and selected Arabic or Urdu
  details on the right. The `pw.Directionality` wrapper pins physical order;
  individual text directions remain explicit. Both statement export screens
  use the same `buildPdfLedger()` path. Financial calculations and ledger
  writes are unchanged.
- Full Flutter suite: `01:14 +633: All tests passed!`; focused PDF suite:
  `00:01 +12: All tests passed!`; `flutter analyze lib --no-pub`:
  `No issues found! (ran in 6.3s)`; `dart analyze test/`:
  `No issues found!`; Firestore Rules Emulator: `152 passing (30s)`.
- Web release build `EXIT: 0`; Hosting and Firestore Rules/indexes each
  reported `Deploy complete!`. Live `/`, `index.html`, `version.json`, and
  `main.dart.js` returned HTTP 200 with `no-store, must-revalidate, no-cache`;
  live `version.json` reports version `3.10.6`, build `1117`. The existing
  23 remote indexes and 2 field overrides absent from the local definition
  were preserved; deployment did not use `--force`.
- Split APKs: ARMv7 30.7 MB, ARM64 32.2 MB, x86_64 33.7 MB; signed AAB:
  54.8 MB. APK v2 signature and AAB JAR signature checks passed. ARM64
  package metadata is versionName `3.10.6`, versionCode `310063117`; install
  on `R5GL22RGT9V` reported `Success`.
- Android SDK license acceptance was not changed; release builds succeeded.
