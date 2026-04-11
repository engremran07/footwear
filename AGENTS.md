# ShoesERP AGENTS Runtime Contract

Last updated: 2026-03-29

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

Before writing code:

- Read AGENTS.md and CLAUDE.md
- Validate role/rules/collection alignment

Before finishing:

- Run flutter analyze lib --no-pub
- Run flutter test -r expanded
- Run `$ErrorActionPreference='Continue'; flutter build web --release; Write-Host "EXIT: $LASTEXITCODE"` — confirm LASTEXITCODE=0 AND no `lint violation` lines in output (PowerShell pipe `2>&1` misrepresents exit code; check `$LASTEXITCODE` directly)
- Run hygiene grep gates (see CI §4 in .github/workflows/ci.yml):
  1. No raw collection strings: `grep -rn "\.collection('" app/lib/ | grep -v "Collections\."` → zero
  2. allTransactionsProvider in invalidation list: `grep -q "allTransactionsProvider" app/lib/providers/auth_provider.dart`
  3. No legacy ABI-split APK build commands remain in release docs or scripts
  4. No Firestore writes in screens/widgets: `grep -rn "FirebaseFirestore\|\.collection(" app/lib/screens/ app/lib/widgets/` → zero
- Manually or logically verify admin and seller access for `/` and `/inventory`
  after auth/router/provider/rules edits; no transient permission-denied UI is acceptable
- When release/deploy work is requested, verify `app/pubspec.yaml` and
  `app/lib/core/constants/app_brand.dart` carry the same release version, then
  rebuild/deploy/install from that version before commit/push
- Update deep-dive and READMEs if runtime assumptions changed
- If rules changed, deploy firestore:rules and firestore:indexes
- If bug resolution involved multiple candidate fixes, run
  `.github/instructions/band-aid-loop-reversal.instructions.md` and
  `.claude/skills/band-aid-loop-reversal/SKILL.md` before commit

## 9) Runtime Document Hierarchy

Conflict resolution order for instructions:

1. AGENTS.md (runtime contract)
2. CLAUDE.md (coding rules)
3. .claude/CLAUDE.md (local mirror/override helper)
4. Skill files under .claude/skills/

## 10) Current Audit Status

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
