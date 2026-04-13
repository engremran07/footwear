# ShoesERP AGENTS Runtime Contract

Last updated: 2026-04-13

## 1) Runtime Truth (Authoritative)

This repository is a route/seller distribution ERP.

- Roles: admin, seller
- Legacy role value manager must be treated as admin-equivalent in app and rules
- Canonical collections:
  - users
  - products
  - product_variants
  - seller_inventory
  - inventory_transactions
  - routes
  - shops [Firestore collection: 'customers' — legacy name, use Collections.shops]
  - transactions
  - invoices
  - settings

Source of collection truth: app/lib/core/constants/collections.dart

## 2) Required Route Map

Defined in app/lib/core/router/app_router.dart:

- /login
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
- /invoices/:id
- /reports
- /profile
- /settings

## 3) Permission Matrix

Admin-equivalent (admin/manager):

- Full write access to all business collections

Seller:

- Read active business documents
- Create/update shops only inside assigned route constraints
- Create transactions for assigned route
- Update own profile (name, theme, locale, password)
- No writes to routes/products/product_variants/settings

## 4) Non-Negotiable Engineering Rules

1. Role alignment is mandatory in all three layers: app/lib/models/user_model.dart, firestore.rules, and provider write guards on security-critical fields.

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

1. No Firebase Storage usage — the app runs on Firestore + Auth + Functions
  only (zero-cost tier). Company logos are stored as base64 in Firestore.
  Product images use external HTTP URLs. Do not introduce firebase_storage.

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
  updating the corresponding `shop.balance` WILL produce stale UI. If you flush
  data during dev, always also reset every shop's `balance` field to `0.0` and
  reset `settings/global.last_invoice_number` to `0`. Use `dev_reset.js` in
  the repo root for this.

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
   - `flutter test -r expanded` → must quote pass count line
   - APK build → must quote file size from output
   - Web build → must state `EXIT: 0`
  Claims of "tests pass" or "no issues" without quoting the actual tool
  output are invalid and block signoff. This rule is non-bypassable.

1. **Version sync is atomic.** `app/pubspec.yaml` version field and
  `app/lib/core/constants/app_brand.dart` `appVersion`/`buildNumber` MUST
  be updated in the same edit operation. Version drift between these two
  files is a P0 regression. Verify with:
  `grep -E "^version:|appVersion|buildNumber" app/pubspec.yaml app/lib/core/constants/app_brand.dart`

## 5) Known Failure Signatures

1. permission-denied on route create/inventory add

- Common causes:
  - role value drift (Admin/manager casing, trailing spaces, legacy values)
  - user doc inactive
  - rules not deployed

1. resource-exhausted on dashboard

- Common causes:
  - aggregate query quota pressure
  - repeated refresh hitting count/sum endpoints

1. lists empty without obvious UI error

- Common cause:
  - missing composite index

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
flutter pub get
flutter analyze lib --no-pub
# Fat APK (canonical — always fat, never ABI-split)
flutter build apk --release
# Web
flutter build web --release
firebase deploy --only hosting
```

## 8) Autonomous Agent Checklist

**NON-BYPASSABLE. Every step is mandatory on every signoff. No exceptions.**

### Before writing code

- Read AGENTS.md and CLAUDE.md
- Validate role/rules/collection alignment

### The 14-Step Mandatory Signoff Sequence

Every session ending with code changes MUST complete ALL 14 steps in order
and quote the required evidence for each. A session is NOT complete until
every step has been executed and its evidence recorded in the response.

#### Step 1 — Flutter analyze (zero issues)

```powershell
cd app; flutter analyze lib --no-pub
```

Evidence required: quote exact final line `No issues found! (ran in Xs)`

#### Step 2 — Dart analyze test (zero issues)

```powershell
dart analyze test/
```

Evidence required: `No issues found!`

#### Step 3 — All tests green

```powershell
flutter test -r expanded
```

Evidence required: quote `All N tests passed!` with N count

#### Step 4 — Hygiene grep gates (all must return zero results)

```powershell
# 4a — No raw collection strings
grep -rn "\.collection\('" app/lib/ | grep -v "Collections\."
# 4b — allTransactionsProvider in invalidation list
grep -q "allTransactionsProvider" app/lib/providers/auth_provider.dart
# 4c — No Firestore writes in screens/widgets
grep -rn "FirebaseFirestore\|\.collection(" app/lib/screens/ app/lib/widgets/
# 4d — No StateProvider (banned Riverpod 3)
grep -rn "StateProvider\b" app/lib/ --include="*.dart"
# 4e — Version sync: pubspec == app_brand
grep -E "^version:|appVersion|buildNumber" app/pubspec.yaml app/lib/core/constants/app_brand.dart
# 4f — No temp artifacts in git status
git status --short | grep -E "auth-users\.json|\.txt$|\.log$|\.flag$|check_locale\."
```

#### Step 5 — Zero markdown lint issues

```powershell
markdownlint "**/*.md" --ignore node_modules --ignore app/build
```

Evidence required: zero output (exit 0)

#### Step 6 — Firestore rules + indexes deploy

```bash
firebase deploy --only firestore:rules,firestore:indexes
```

Evidence required: quote "Deploy complete!" from output.
This is ALWAYS required, not only when rules changed — it confirms the
deployed state matches the local file state. Skip only if confirmed already
deployed in same session and no `.rules` or `indexes.json` files changed.

#### Step 7 — Web release build

```powershell
$ErrorActionPreference='Continue'
cd app; flutter build web --release
Write-Host "EXIT: $LASTEXITCODE"
```

Evidence required: `EXIT: 0` (check `$LASTEXITCODE` directly; PowerShell
pipe artefacts do not reflect flutter's real exit code)

#### Step 8 — Firebase Hosting deploy

```bash
firebase deploy --only hosting
```

Evidence required: quote "Deploy complete!" from output.

#### Step 9 — APK release build

```powershell
flutter build apk --release
```

Evidence required: quote `Built build\app\outputs\flutter-apk\app-release.apk (XXmb)`

#### Step 10 — GitHub commit audit

```powershell
git log --oneline -5      # review last 5 commits
git status --short        # confirm only expected files are staged/modified
git diff --stat HEAD      # confirm scope of changes matches intent
```

Evidence required: quote `git log --oneline -5` output and confirm
no unexpected files appear in `git status --short`.

#### Step 11 — Commit with descriptive message

```powershell
git add -A
git commit -m "<type>: <summary> — v<version>"
```

Evidence required: quote commit hash from output.
Commit message must follow: `type: summary` where type ∈
{feat, fix, chore, style, refactor, test, docs, ci, release}.

#### Step 12 — Push to remote

```powershell
git push
```

Evidence required: quote push output including branch name and commit hash.

#### Step 13 — APK install to device (if device connected)

```powershell
adb devices   # confirm device is listed
adb -s <device-id> install -r "D:\Footwear\app\build\app\outputs\flutter-apk\app-release.apk"
```

Evidence required: `Success` from adb output.

#### Step 14 — Final verification

- Verify admin and seller startup for `/` and `/inventory` after
  auth/router/provider/rules edits; no transient permission-denied UI acceptable
- Update AGENTS.md §10 audit status if runtime assumptions changed
- If bug resolution involved multiple candidate fixes, run band-aid-loop-reversal
  skill before committing

### Bypass Consequences

Any signoff that skips or omits evidence for any step is an **incomplete
session**. The next agent session MUST check `git log` to confirm which steps
were completed, then run all missing steps before starting new work.

## 9) Runtime Document Hierarchy

Conflict resolution order for instructions:

1. AGENTS.md (runtime contract)
2. CLAUDE.md (coding rules)
3. .claude/CLAUDE.md (local mirror/override helper)
4. Skill files under .claude/skills/

## 10) Current Audit Status

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
- Release: v3.4.0+30, fat APK + web deployed

2026-04-06 audit v7 — v3.3.0+21:

- Admin is now a full seller: loads vehicle stock via Inventory → Transfer, sees own seller_inventory in invoice creation, creates invoices from own stock
- Invoice item restriction: all roles (admin + seller) must select ≥1 item; empty-item invoices blocked
- Transfer dialog: `sellersProvider` → `allUsersProvider` so admin appears as a recipient for self-transfer
- product_provider.transferToSeller: fixed audit log to write to `inventory_transactions` (not `transactions`); type corrected to `transfer_out` matching InventoryTransactionModel constants — was violating Firestore rules AND not appearing in transfer history
- customer transaction visibility fixed (v3.2.7+19): client-side `deleted != true` filter on all providers
- Build standard: fat APK only (`flutter build apk --release`), never ABI-split builds
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
