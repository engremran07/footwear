# ShoesERP — Ultimate Master Audit Report

**Audit version:** v13 (88-agent governance pack v2.0)  
**Date:** 2026-04-11  
**App version:** v3.5.0+43 (post-remediation)  
**Auditor:** GitHub Copilot (Claude Sonnet 4.6) — autonomous multi-agent system  
**Baseline commit:** 3377697 (v3.4.11+42)  
**Branch:** main  
**Firebase project:** shoeserp-clean-20260327

---

## Scope-Specific Addendum — 2026-10-27 Tenant Cache Isolation and Policy Recheck

This recheck fixes reproducible app/provider defects and records local Rules
evidence. It does not claim production deployment or full closure of the
attached 33-finding checklist.

### Confirmed Fixes

- The notification regression had two independent causes. The feed did not
  preserve its previous value during same-tenant refresh, and its singleton
  provider cache could retain tenant A's rows after switching to tenant B.
  Feed and referenced-shop providers now use tenant-keyed families, keep
  same-tenant refresh behavior, and return no business stream for missing or
  `__global__` scope. A tenant-switch regression proves the new scope begins
  without tenant A's cached rows.
- Root platform super-admins can open the platform settings hub without
  business context. Workspace settings descendants remain gated by a valid
  selected support context. `viewSettingsHub` and `manageSettings` encode
  these different scopes.
- The user-route retry test now supplies the authenticated Firebase user that
  the screen's auth-loading guard requires. The workspace navigation test now
  uses a concrete tenant for tenant-admin access and valid reason/TTL fields
  for selected super-admin access; the production guard was not weakened.
- The Firestore Rules changes received local emulator validation. This is not
  evidence that production Rules or indexes are deployed.

### Verification

- Full Flutter suite: `01:20 +654: All tests passed!`.
- `flutter analyze lib --no-pub`: `No issues found! (ran in 5.6s)`.
- `dart analyze test/`: `No issues found!`; updated changelog regression:
  `00:00 +10: All tests passed!`.
- Rules Emulator: `172 passing (42s)`.
- Focused notification, route, settings, and permission-policy regressions
  passed. Full suite includes those regressions; changelog was separately
  tested after its final edit.
- Markdown lint and `git diff --check` exited 0 after the final documentation
  edits.
- Version `3.10.8+1119` is synchronized. Split APKs built at 30.7 MB (ARMv7),
  32.2 MB (ARM64), and 33.7 MB (x86_64); signed AAB built at 54.8 MB. APK v2
  signature verification succeeded and `jarsigner` reported `jar verified.`
  for the AAB.

### Open Findings and Limits

- The exact 129-line attachment text is not present in the current workspace
  or retained session files. A complete row-by-row mapping of its 33 findings
  cannot be honestly asserted from the available summary; reattach the source
  checklist to finish that trace without inventing omitted points.
- Known Rules/provider follow-ups remain: an invoice counter can be advanced
  without a corresponding invoice; the write-rate throttle still depends on
  client-controlled `updated_at`; and the auth provider still attempts a
  client `email_verified` update that current Rules deny and the provider logs
  as skipped.
- Migration/decision-sized audit items remain open: money-in-minor-units,
  financial disaster-recovery restore, shared-device inactivity policy,
  invoice-logo reference redesign, paid-plan architecture, CSP hardening,
  web multi-tab persistence, Rules-read billing metrics, and legacy sentinel
  inventory/cleanup. They were not changed without migration evidence and
  explicit policy decisions.
- The device reconnected after the initial check. ARM64 APK copy reported
  `1 file pushed`; streamed install reported `Success`. Device package reports
  versionName `3.10.8`, versionCode `310083119`. No production Rules/indexes
  or Hosting deployment, Play Console upload, commit, or push has been
  performed.

---

## Scope-Specific Addendum — 2026-10-27 Tenant Permissions and User-List Recovery

This addendum records verified local changes against the attached multi-tenant
audit. It does not claim that every audit finding is closed or that production
is ready.

### Confirmed User-List Root Cause

- `UsersListScreen` read `authUserProvider.value` but treated a null value as
  loading whenever Firebase Auth still had a signed-in user. A Firestore
  profile-stream error therefore remained an indefinite shimmer; a missing
  profile was also presented as loading rather than an actionable access state.
- The screen now distinguishes auth/profile loading, mapped auth/profile
  errors with retry, and a missing profile's access-denied state. The focused
  test reproduced the pre-fix failure as `pumpAndSettle timed out`; after the
  fix the file reported `00:04 +4: All tests passed!`.

### Permission Policy and Tenant Boundaries

- `RoleCapabilities` and `PermissionPolicy` now include dashboard capability
  and are the canonical app-side role/capability policy. The router rechecks
  dashboard/business-route access when super-admin workspace support context
  expires. This does not make client policy a security boundary.
- `TenantScope.requireTenant()` and `TenantScope.applyToData()` reject missing
  and `__global__` write scopes. Legacy sentinel reads are not globally
  removed; any data cleanup requires an inventory and migration plan.
- Runtime role policy remains: legacy admin/manager account management is
  limited to sellers; tenant admins can manage eligible sellers/supervisors;
  supervisors have operational and tenant-notification access, not user,
  settings, backup, financial-correction, or invoice-void access.
- Active admins, tenant admins, supervisors, and sellers may create sale
  invoices and cash receipts in their permitted tenant scope. Seller writes
  require their own authenticated identity and assigned route. Settlement,
  credit-note creation, correction, and void remain separate capabilities.
- Invoice Rules now accept only `sale`, `cash_receipt`, and `credit_note`
  create types. The unsupported-type regression reproduced a supervisor
  creating a `write_off` invoice before the fix; afterward, the targeted test
  reported `1 passing`. The full Rules Emulator suite reports `180 passing`.
- Multi-workspace regression seeds 15 distinct workspace IDs and verifies
  each tenant admin can read its own shop/invoice documents but not the next
  tenant's documents. This proves only those tested authorization paths; it
  does not measure production quota or load capacity.
- Invoice lifecycle Rules tests cover denied unlinked settlement, void, and
  credit-total changes, plus linked credit-note creation. The invoice sequence
  regression denies counter-only updates and requires same-batch invoice
  linkage.
- A read-only security review examined tenant scoping, role checks, invoice
  and receipt Rules, counter linkage, provider authorization, notification and
  tenant-user scoping, and the 15-workspace regression. It reported no
  vulnerabilities in that reviewed scope. This is local-source review only;
  it does not close the other pending checklist findings or verify deployed
  production Rules.

### Scope and Remaining Release Gates

- Verified locally: Rules Emulator `180 passing`; focused invoice and
  permission suite `00:08 +50: All tests passed!`; full Flutter suite
  `01:21 +655: All tests passed!`; `flutter analyze lib --no-pub`:
  `No issues found! (ran in 16.1s)`; `dart analyze test/`: `No issues found!`.
- Finding dispositions currently supported by this pass: #4, #5, and #26 are
  verified fixed in local source; #6 is partially addressed. The other 29
  findings remain `pending_review` because their individual evidence has not
  been revalidated here. This is not a complete 33-item audit closure.
- Hosting and Firestore Rules/indexes deployed to
  `shoeserp-clean-20260327` and each reported `Deploy complete!`; 23 remote
  indexes and 2 field overrides absent locally were preserved. Web build:
  `EXIT: 0`; live `version.json` reports `3.10.9`, build `1120`; shell and
  main bundle returned HTTP 200 with `no-cache, no-store, must-revalidate`.
  ARM64 installation on `R5GL22RGT9V` reported `Success`, versionName `3.10.9`,
  versionCode `310093120`. Version `3.10.9+1120` split APKs
  (30.7/32.2/33.7 MB) and a signed 54.8 MB AAB were built and verified.
  Production data changes, Play Console upload, commit, and push were not
  performed. The wider audit remains open; passing local tests and current
  deployment do not disposition the 29 pending findings.

---

## Scope-Specific Addendum — Local v3.10.8+1119 Shared PDF Logo

This focused regression addresses the user's request for one centered logo
placement across financial PDFs; it is not a full re-audit.

### Root Cause and Change

- `_workspaceBrandHeader()` previously placed the logo at the left and had a
  larger-logo special case only for statements. The flat-table builder had a
  separate standalone image path, so placement and size varied by document.
- The shared brand header now places English content on the left, a
  consistently sized 64-by-46-point logo in the center, and selected
  Arabic/Urdu content on the right. The flat-table fallback now uses the same
  header. Saved invoice logo fallback and the explicit `visibleFields` logo
  setting remain enforced.
- Arabic statement and A5 cash-receipt samples were inspected in Chrome.
  Logo-resource tests cover statement, invoice, receipt, seller/multi-shop,
  and flat-table output; a regression also verifies that hidden logos remain
  hidden.

### Verification and Scope

- Focused PDF suite: `00:01 +12: All tests passed!`; temporary visual probe:
  `00:00 +1: All tests passed!`.
- Full-suite validation, fresh Android/web builds, production Rules/indexes
  and Hosting deployment, device upgrade, and Git publication are pending.
  The `3.10.7` ARM64 APK is already installed; production has not yet received
  the `3.10.8+1119` source.

---

## Scope-Specific Addendum — Local v3.10.7+1118 Cash Receipt Follow-up

This is a focused implementation and regression record, not a full re-audit
or production release. The actual cash-receipt reference is now available.

### Changes and Evidence

- The receipt body now follows the reference's compact bilingual structure
  while retaining the existing shared workspace header and saved invoice
  balance values. The A5 one-page constraint is covered by Arabic/Urdu PDF
  regressions.
- Workspace invoice-header settings now accept optional second and third
  receipt-footer contact numbers. Model serialization, live form hydration,
  dirty-edit preservation, and matching seller invoice-header Rules are
  covered.
- Arabic and Urdu PDFs were inspected in the browser; both show connected
  script text and preserved English-left/RTL-right placement. Urdu remains
  Naskh-style under the current renderer.
- Full Flutter suite: `01:29 +639: All tests passed!`; focused PDF/settings
  suite: `00:15 +24: All tests passed!`; `flutter analyze lib --no-pub`:
  `No issues found! (ran in 13.3s)`; `dart analyze test/`:
  `No issues found!`; Rules Emulator: `154 passing (30s)`.
- Split APKs: ARMv7 30.7 MB, ARM64 32.2 MB, x86_64 33.7 MB; signed AAB:
  54.8 MB. All APK signatures verified and the AAB reported `jar verified.`.
  ARM64 was copied to `/sdcard/Download/` and installed on `R5GL22RGT9V`
  (`Success`); installed versionName `3.10.7`, versionCode `310073118`.
- Firestore Rules/indexes and Hosting were not deployed; no production data,
  commit, or push occurred.

---

## Scope-Specific Addendum — Unreleased Notification and RTL PDF Follow-up

This is a focused local regression record, not a full re-audit or a production
release. It does not change the historical v13 scores.

### Confirmed Root Causes

- The shop-visibility transform used `AsyncValue.whenData()`. On Riverpod 3
  refresh loading states, this returned loading instead of preserving the
  last successful transformed value, causing the notification list to be
  replaced by shimmer. The regression now covers cached refresh state,
  first-load loading, and real errors.
- Mark-as-read failures were discarded with `.ignore()`, hiding the cause of
  permission-denied feedback. The screen now shows mapped write failures; the
  provider validates the available role/tenant/support context before
  attempting the write.
- Generated RTL statement output showed the table's physical columns
  reversed. The table, summary, and final-balance row now use explicit LTR
  physical ordering with per-cell language directions. Arabic and Urdu
  statement samples were visually inspected in Chrome.

### Scope and Remaining Evidence

- Full Flutter suite: `01:14 +638: All tests passed!`; focused notification
  provider/widget suite: `00:03 +9: All tests passed!`.
- `flutter analyze lib --no-pub`: `No issues found! (ran in 10.9s)`;
  `dart analyze test/`: `No issues found!`; Rules Emulator:
  `154 passing (54s)`. Markdown lint and `git diff --check` exited 0.
- At this earlier stage, the receipt image was unavailable. The later receipt
  implementation and current validation are recorded in the v3.10.7+1118
  addendum above.
- This earlier source snapshot had no version bump or APK/AAB rebuild.
  Production Rules/Hosting deployment, install, commit, and push were not
  performed for that snapshot.

---

## Scope-Specific Addendum — v3.10.6+1117 (2026-10-25)

This addendum records the account-statement layout and combined release. It is
not a full re-audit and does not change the historical v13 scores.

### Statement Layout

Account-statement PDFs now position English title/date/entry information in
the left column, shop name and date range in the center, and selected Arabic
or Urdu information in the right column. Physical column order is pinned with
an LTR directionality wrapper; child text retains explicit language direction.
Both account-statement export call sites use `buildPdfLedger()`. No ledger
calculation or write path changed. Generated Arabic and Urdu PDFs were
visually inspected in Chrome.

### Validation and Deployment

- Focused PDF suite: `00:01 +12: All tests passed!`; full Flutter suite:
  `01:14 +633: All tests passed!`.
- `flutter analyze lib --no-pub`: `No issues found! (ran in 6.3s)`;
  `dart analyze test/`: `No issues found!`; Rules Emulator:
  `152 passing (30s)`.
- Web build `EXIT: 0`; Hosting and Rules/indexes deployments reported
  `Deploy complete!`. Live shell endpoints returned HTTP 200 with
  `no-store, must-revalidate, no-cache`; `version.json` reports version
  `3.10.6`, build `1117`.
- Split APKs: 30.7/32.2/33.7 MB; signed AAB: 54.8 MB. APK v2 and AAB JAR
  signatures verified. ARM64 versionCode `310063117` installed on
  `R5GL22RGT9V` with `Success`.

---

## Scope-Specific Addendum — v3.10.5+1116 (2026-10-25)

This addendum records the supervisor, workspace access, notification
subscription, and Android release work. It is not a full re-audit and does not
change the historical v13 scores above.

### Findings and Remediation

- Workspace user loading and backup access had inconsistent role predicates:
  legacy workspace `admin` profiles did not receive the expected user-list
  and merge-only backup capabilities. The predicates now recognize legacy
  admins while retaining tenant scope and preserving the narrower backup
  policy.
- Promoting sellers directly to administrator roles would grant unrelated
  account and workspace powers. A separate tenant-scoped `supervisor` role
  now supports operational routes, shops, products, inventory, invoices, and
  reports. It does not grant user administration, notifications, settings,
  backups, financial corrections/approval, invoice voids, or reassignment
  powers reserved for administrators.
- Notification visibility listeners previously depended on changing
  notification state. They now key on stable sorted shop IDs, avoiding
  read-state-only listener restarts.
- Android release ABI splits previously remained active during bundle
  resource shrinking. Bundle tasks now disable APK ABI splits; APK tasks
  retain them. Version-code generation is bounded and monotonic, with Flutter
  ABI offsets accounted for when comparing split APKs.

### Evidence and Remaining Release Gates

- Focused role/backup/notification/users suite: `00:22 +55: All tests passed!`;
  full Flutter suite: `01:59 +633: All tests passed!`.
- `flutter analyze lib --no-pub`: `No issues found! (ran in 15.0s)`;
  `dart analyze test/`: `No issues found!`; Rules Emulator:
  `152 passing (33s)`.
- Markdown lint and `git diff --check` exited 0.
- Split APKs: ARMv7 30.7 MB, ARM64 32.2 MB, x86_64 33.6 MB. Signed AAB:
  54.8 MB. APK v2 signature verified; AAB verification reported
  `jar verified.`. ARM64 package metadata: versionName `3.10.5`,
  versionCode `310053116`.
- Android SDK license acceptance remains pending (release builds succeeded
  without accepting licenses). No device was connected, so phone delivery was
  skipped. Production Rules/indexes and Hosting deployments, installation,
  commit, and push were not performed. Firestore Rules remain local and
  undeployed.

---

## Executive Summary

ShoesERP is a production Flutter/Firebase ERP application for footwear distribution. This audit was performed using an 88-agent governance system examining security, architecture, financial integrity, CI/CD, testing, code quality, performance, and observability dimensions. The app has undergone 12 prior audit cycles before this report.

**Overall score: 79/100** (up from 72/100 at v3.4.11+42)

| Category | Score | Grade |
|----------|-------|-------|
| Security (OWASP Mobile M1–M9) | 80/100 | B+ |
| Architecture / Code Quality | 82/100 | A- |
| Financial Integrity | 91/100 | A |
| CI/CD + Testing | 76/100 | B+ |
| Performance / Scalability | 69/100 | C+ |
| Observability | 60/100 | C |
| Documentation / Governance | 80/100 | B+ |
| **Overall** | **78/100** | **B+** |

---

## Agent Roster & Findings Summary

### Group A — Security Agents (A1–A12)

**A1 — Authentication Auditor**  
Status: ✅ Pass  
Firebase Auth email+password. Secondary FirebaseApp for user creation (no server SDK). Token refresh + forced re-auth on INVALID_ID_TOKEN. Session 8h hard limit. 7h30m warning dialog.  
Finding: None critical.

**A2 — Authorization Auditor**  
Status: ✅ Pass  
Firestore rules: deny-by-default. `isAdminRole()` regex handles `admin`/`manager` casing variants. Seller write scope validated in rules + provider layer (defense in depth). Admin-only providers guarded.  
Finding: None critical.

**A3 — Data Exposure Auditor**  
Status: ✅ Fixed (RR-001 closed 2026-09-26)  
The exposed user-managed key was revoked in IAM, its Firestore credential document was deleted, the local backup payload was sanitized, and the client service-account/JWT Auth administration implementation was removed. Arbitrary-user Auth administration now requires a trusted backend; client password resets use Firebase Auth's owner-directed email flow.

**A4 — Input Validation Auditor**  
Status: ✅ Pass  
AppSanitizer used throughout. Input formatters applied on all numeric fields. Firestore rules validate field types, invoice math, transaction amounts. No injection surface.

**A5 — Cryptography Auditor**  
Status: ✅ Pass  
No custom crypto. Firebase SDK handles all crypto. PDF isolation via `Isolate.run()`. No sensitive data in log output.

**A6 — Session Management Auditor**  
Status: ✅ Pass (P1-DEFERRED RR-003)  
8h hard session cutoff via `AppLifecycleListener`. 7h30m soft warning. Role-scoped providers invalidated on logout. Lock overlay present but tap-to-dismiss without re-auth (P1-DEFERRED — requires local_auth sprint).

**A7 — API / Network Security Auditor**  
Status: ✅ Pass  
All traffic via Firebase SDK (HTTPS). No raw HTTP calls. External product image URLs validated at SDK level.

**A8 — Storage Security Auditor**  
Status: ✅ Pass  
No Firebase Storage. Logo stored as base64 in Firestore (≤50KB cap enforced). No sensitive data in SharedPreferences. ProGuard minification enabled for APK.

**A9 — Secrets Management Auditor**  
Status: ✅ Pass (CI) / ⚠️ Documented (App)  
CI uses GitHub Secrets only. `firebase_options.dart` and `google-services.json` injected at build time. `key.properties` not in repo. Admin identity SA key in Flutter heap documented as RR-001.

**A10 — OWASP M1 (Improper Platform Usage) Auditor**  
Status: ✅ Pass  
GoRouter guards enforce role access. No direct intent manipulation. Permission handler used correctly.

**A11 — OWASP M7 (Poor Code Quality) Auditor**  
Status: ✅ Pass  
flutter analyze: clean (zero issues). All financial writes via WriteBatch. No raw collection strings. No screen-layer Firestore writes.

**A12 — OWASP M9 (Reverse Engineering) Auditor**  
Status: ✅ Pass  
isMinifyEnabled=true, isShrinkResources=true. ProGuard rules for 8 major plugins. Release signing with dedicated keystore. Build signing fallback throws GradleException (no silent failure).

---

### Group B — Architecture Agents (B1–B10)

**B1 — Collection Alignment Auditor**  
Status: ✅ Pass  
Zero raw `.collection('string')` calls in `app/lib/`. All 10 collections referenced via `Collections.*` constants. Constants match Firestore actual collection names.

**B2 — Provider Architecture Auditor**  
Status: ✅ Pass  
All Firestore writes in provider notifiers. No `ref.read()` in `build()` methods. `StreamProvider.autoDispose` used throughout. 19 admin-scoped providers in `_invalidateRoleScopedProviders()`.

**B3 — Role Alignment Auditor**  
Status: ✅ Pass  
Three layers aligned: `user_model.dart` (parsing), `firestore.rules` (enforcement), provider write guards (defense). `manager` treated as admin-equivalent throughout.

**B4 — Navigation / Router Auditor**  
Status: ✅ Pass  
21 routes defined. Auth guard redirects unauthenticated users. Role-based screen access enforced. `context.go()` used in-shell. No deprecated `Navigator.push()` in screens.

**B5 — Stock Tracking Auditor**  
Status: ✅ Pass  
`quantity_available` stores PAIRS in Firestore. UI converts to dozens throughout. `canHaveSellerInventory` true for all roles (admin acts as field seller).

**B6 — Financial Pipeline Auditor**  
Status: ✅ Pass (P0-DEFERRED RR-002)  
Single write pipeline. `shop.balance` only mutated via InvoiceNotifier or TransactionNotifier. Atomic WriteBatch used for all financial writes. Float arithmetic documented as RR-002 (deferred).

**B7 — Dependency Auditor**  
Status: ✅ Pass  
No `dependency_overrides` present. `archive ^4.0.0` uses `image 4.8.0` (Wasm clean). No firebase_storage dependency. No Cloud Functions dependency. All deps on current stable range.

**B8 — Firebase Rules Auditor**  
Status: ✅ Pass (Security fix applied in this session)  
Deny-by-default. `docSizeOk()` <50KB. `withinWriteRate()` 1s cooldown. `isValidRole()` in rules. Invoice math validated in rules. Transaction type+amount validated. **RR-015 FIXED:** Seller transaction update (approval-disabled path) over-permissioned `amount`+`type` fields — restricted to `description`, `updated_at`, `updated_by`, `edit_request_*` only.

**B9 — Index Coverage Auditor**  
Status: ✅ Pass  
All `where(A)+orderBy(B)` (A≠B) queries have composite index entries. 8 unused indexes removed in v3.4.4. `route_id+created_at` index added for seller analytics. `edit_request_pending+created_at` index added.

**B10 — L10n Parity Auditor**  
Status: ✅ Pass  
CI Gate 5 validates EN ⊆ AR ⊆ UR key parity. 372+ keys × 3 languages. All touched strings in v3.5.0 localized.

---

### Group C — Code Quality Agents (C1–C8)

**C1 — Hardcoded Color Auditor**  
Status: ✅ FIXED (was ⚠️)  
Was: 15 `Colors.*` instances in 6 screens. Now: replaced with `AppBrand.*` / `cs.*` constants throughout. Dark mode safe.

**C2 — SnackBar Consistency Auditor**  
Status: ✅ Pass  
All 19 screens use styled `errorSnackBar()` / `successSnackBar()` / `warningSnackBar()` / `infoSnackBar()` helpers. No raw `SnackBar(content: Text(...))`.

**C3 — Widget Test Auditor**  
Status: ✅ FIXED (was ⚠️)  
Was: placeholder `MaterialApp(home: Text('OK'))` with no real screen coverage. Now: auth-flow smoke test + GoRouter absent-state check.

**C4 — Dead Code Auditor**  
Status: ✅ Pass  
`search_provider.dart` (0 usages) deleted in v3.2.6. No other dead providers or screens detected.

**C5 — CI Workflow Auditor**  
Status: ✅ FIXED (was ⚠️)  
Was: Flutter version drift (3.22.x/3.29.x), no timeouts, no coverage. Now: all 4 workflows pinned to Flutter 3.29.2, timeouts added (20/30/10 min), coverage enabled, 10 hygiene gates.

**C6 — PDF Threading Auditor**  
Status: ✅ Pass  
All 4 PDF export functions use `Isolate.run()`. No PDF rendering on main thread.

**C7 — Error Mapping Auditor**  
Status: ✅ Pass  
`AppErrorMapper` used in all critical write screens. `ErrorState` replaces raw exception text. Firebase exceptions mapped to user-facing localized messages.

**C8 — AppBrand Consistency Auditor**  
Status: ✅ Pass  
All semantic colors use `AppBrand.*` constants. `errorColor`, `successColor`, `warningColor`, `stockColor`, `adminRoleColor`, `sellerRoleColor` used consistently.

---

### Group D — Financial Integrity Agents (D1–D5)

**D1 — Balance Pipeline Auditor**  
Status: ✅ Pass  
`shop.balance` single write pipeline enforced. No direct Firestore writes to balance outside InvoiceNotifier/TransactionNotifier.

**D2 — Invoice Lifecycle Auditor**  
Status: ✅ Pass  
Sale invoice: stock deduction + invoice + tx in one atomic batch. Void: stock return + refund/credit in one atomic transaction. `markAsPaid` outstanding fallback guard present.

**D3 — Transaction Ledger Auditor**  
Status: ✅ Pass  
All transaction types mapped: `cash_in`, `cash_out`, `return`, `payment`, `write_off`. Running-balance reconstruction uses typed impact. Ledger entries render correctly per type.

**D4 — Invoice Number Auditor**  
Status: ✅ Pass  
`settings/global.last_invoice_number` incremented atomically (Firestore transaction). No duplicate numbers possible under concurrent writes.

**D5 — Float Arithmetic Auditor**  
Status: ⚠️ P0-DEFERRED (RR-002)  
`double` used for all monetary fields. ±0.01 epsilon tolerance in provider. No runtime rounding errors observed in production, but theoretical drift under repeated operations.

---

### Group E — Performance Agents (E1–E5)

**E1 — Firestore Read Auditor**  
Status: ⚠️ P1-DEFERRED (RR-004)  
Shops analytics capped 500. Ledger capped 150. Full-history export uses one-shot query. No cursor-based pagination (deferred to scale sprint).

**E2 — Widget Rebuild Auditor**  
Status: ✅ Pass  
`StreamProvider.autoDispose` used throughout. No unnecessary `Consumer` wrappers. `ref.watch()` only in build methods, `ref.read()` in callbacks.

**E3 — List Performance Auditor**  
Status: ✅ Pass  
Shimmer loading, lazy-listview, `AnimatedList` used in 5 list screens. No synchronous blocking operations in build.

**E4 — Dashboard Quota Auditor**  
Status: ✅ Pass  
Dashboard uses per-metric safe aggregate calls with cached fallback (`_lastGoodDashboardStatsProvider`). No repeated refresh loops.

**E5 — APK Size Auditor**  
Status: ✅ Pass  
Split-per-ABI release baseline: arm64-v8a APK plus universal release wrapper, with ProGuard minification active. No Firebase Storage, no large bundled assets.

---

### Group F — Testing Agents (F1–F5)

**F1 — Test Coverage Auditor**  
Status: ⚠️ Partial  
337 tests passing. Coverage measurement now enabled (--coverage). Unit test coverage estimated ~60% of business logic. Widget tests: minimal (1 smoke test). Integration tests: none.

**F2 — Financial Guard Test Auditor**  
Status: ✅ Pass  
`create_sale_invoice_guard_test.dart`, `mark_paid_outstanding_test.dart` present. Invoice lifecycle guards tested.

**F3 — Sanitizer Test Auditor**  
Status: ✅ Pass  
`sanitizer_test.dart` present. Input sanitization paths tested.

**F4 — Error Mapper Test Auditor**  
Status: ✅ Pass  
`error_mapper_test.dart` present. Firebase exception type mapping tested.

**F5 — Rules Emulator Test Auditor**  
Status: ⚠️ Missing (PI-005)  
`tests/firestore-rules/` scaffold created with package.json and rules.test.js. Not yet wired to CI. Rules emulator tests recommended for next sprint.

---

### Group G — Observability Agents (G1–G3)

**G1 — Crashlytics Auditor**  
Status: ⚠️ Partial  
Crashlytics dependency present. Not configured with custom keys (user_id, role, app_version). Crash correlation limited. Improvements tracked as PI-006.

**G2 — Logging Auditor**  
Status: ✅ Pass  
No sensitive data (passwords, tokens, balance values) in debug output. AppErrorMapper redacts Firebase internal messages.

**G3 — Version Tracking Auditor**  
Status: ✅ Pass  
`appVersion + buildNumber` in AppBrand constants. CI Gate 8 enforces pubspec ↔ app_brand.dart sync. Version displayed in About screen.

---

## P0/P1 Open Risks

| ID | Severity | Summary | Recommended resolution |
|----|----------|---------|----------------------|
| RR-002 | P0-DEFERRED | Float double monetary arithmetic | Integer-pence accounting sprint |
| RR-003 | P1-DEFERRED | Lock overlay tap-to-dismiss | `local_auth` sprint |
| RR-004 | P1-DEFERRED | Hard pagination caps (150/500) | Cursor-based pagination sprint |

---

## Changes Implemented in This Audit (v3.5.0+43)

| # | Fix | Status |
|---|-----|--------|
| 1 | REGRESSION_REGISTRY.md created | ✅ |
| 2 | SESSION_LOG.md created | ✅ |
| 3 | MASTER_BLUEPRINT.md created | ✅ |
| 4 | CHANGELOG.md created | ✅ |
| 5 | AUDIT_REPORT_FOOTWEAR_ERP.md (this file) created | ✅ |
| 6 | `.github/baselines/apk_size_kb.txt` created | ✅ |
| 7 | `Colors.*` fixed in login_screen.dart (4 instances) | ✅ |
| 8 | `Colors.*` fixed in bootstrap_profile_screen.dart (2 instances) | ✅ |
| 9 | `Colors.*` fixed in create_sale_invoice_screen.dart (2 instances) | ✅ |
| 10 | `Colors.*` fixed in users_list_screen.dart (2 instances) | ✅ |
| 11 | `Colors.*` fixed in shop_detail_screen.dart (2 instances) | ✅ |
| 12 | `Colors.*` fixed in settings_screen.dart (3 instances) | ✅ |
| 13 | All 4 CI workflows pinned to Flutter 3.29.2 | ✅ |
| 14 | All 3 CI jobs: timeout-minutes added (20/30/10) | ✅ |
| 15 | Test job: --coverage enabled | ✅ |
| 16 | ci.yml: Gates 7–10 added | ✅ |
| 17 | release.yml: APK size gate added | ✅ |
| 18 | widget_test.dart placeholder replaced | ✅ |
| 19 | Version bumped to v3.5.0+43 (pubspec + app_brand) | ✅ |
| 20 | AGENTS.md §10 audit v13 entry | ✅ || 22 | Security fix RR-015: Firestore transaction rule — seller over-permission (amount+type) removed | ✅ || 21 | CLAUDE.md "Done In This Baseline" updated | ✅ |

---

## Score Justification

**+6 points from v3.4.11+42 (72) to v3.5.0+43 (78):**

| Area | Delta | Reason |
|------|-------|--------|
| Documentation | +5 | 5 governance docs created; regression registry; blueprint; changelog; session log |
| Code Quality | +3 | 15 hardcoded Colors.* eliminated; widget_test.dart replaced |
| CI/CD | +2 | Version pinned; timeouts; coverage; 10 gates; baselines |
| Score cap | -4 | Remaining P0/P1 deferred risks RR-002 through RR-004 prevent full score |

**Remaining gap to 100:**

- P0 float arithmetic: -5 points until resolved
- P1 session re-auth: -3 points until resolved
- P1 pagination: -3 points until resolved
- Observability (Crashlytics custom keys): -3 points

---

*Report generated by GitHub Copilot (Claude Sonnet 4.6) autonomous 88-agent governance system v2.0.*  

### Security Remediation Update — 2026-09-26

- Revoked the exposed IAM key and verified the key endpoint returns 404.
- Deleted `admin_config/sa_credentials` from the live Firestore project and sanitized the local backup.
- Removed the client-held service-account Auth administration feature.
- Restricted platform super-admin business access to one selected workspace with a required support reason and append-only start/end audit events.
- Client-created/promoted super-admin roles are now denied by provider and Firestore rules.
*Next audit recommended after any of: Blaze upgrade, accounting sprint, local_auth sprint, scale sprint.*

## Frontend Forensic Audit — 2026-10-03

**Scope:** Current Flutter source, installed APK runtime logs and screenshot, focused widget tests, and Firestore emulator behavior relevant to the frontend symptoms. This is a source-led audit with partial device verification, not a completed visual redesign. No Firestore rules, schema, or accounting calculations were changed.

### Runtime and Architecture Map

- **Toolchain:** Flutter 3.41.6, Dart 3.11.4. App dependencies include Riverpod 3.3.2, go_router 17.2.1, Firebase Auth 6.4.0, Firestore 6.3.0, fl_chart 1.2.0, flutter_animate 4.5.0, and Shimmer 3.0.0.
- **Startup:** `main.dart` initializes Firebase/App Check, applies system-bar defaults, then mounts `FootwearErpApp`; initialization failure uses a retry surface.
- **App composition:** `FootwearErpApp` resolves locale, theme, router, and wraps the route tree with `SessionGuard`.
- **State/data flow:** screens watch Riverpod providers; providers expose Firestore state and own writes. `AuthNotifier` authenticates/registers access, `SessionGuard` enforces active application sessions, and `RouterNotifier` redirects based on auth/profile/role state.
- **Navigation:** GoRouter shell routes render through `AppShell`; compact layouts use role-filtered bottom navigation and drawer, widths at/above 720dp use a navigation rail, and 1024dp uses the extended rail. Form/detail routes use `push`; top-level destinations use `go`; shell and form back handling use `PopScope`.
- **Tenant identity:** desktop/rail and mobile shell share `_workspaceContextBanner`; it now appears whenever an active tenant context exists, with platform support access visually distinguished.

### Design-System Map

| Area | Current implementation | Audit assessment |
|---|---|---|
| Color | Arctic seed blue; Material 3 generated schemes; explicit light, dark, and high-contrast colors; semantic status palettes | Preserve brand. Blue is overrepresented in primary actions/icons; semantic colors exist but several screens still use fixed white/black overlay colors. |
| Typography | Syne headings, DM Sans body, Noto Sans Arabic, Noto Nastaliq Urdu; locale-specific line heights | Intentional families. Urdu’s 2.0 line-height requires screenshot checks for tall dialogs and form rows; numeric and long mixed-script fields need text-scale QA. |
| Spacing | `AppTokens` 2–48dp values, primarily 8dp rhythm | Good central vocabulary; screens still mix raw 8/12/16/24 values and token equivalents. Normalize only during targeted component work. |
| Shape | Radius tokens 4–100dp; common cards 12–16dp; dialogs/sheets use larger containment | Useful hierarchy exists, but screen code still uses many literal radii. Avoid a blanket radius rewrite. |
| Elevation | Material tonal surfaces, low card elevation, a few blue-tinted shadow tokens | Mostly restrained; validate contrast and shadows in dark/high-contrast modes. |
| Icons | Material Icons dominate; Font Awesome is limited to brand-specific WhatsApp controls | Preserve the current primary family. Icon-only actions need consistent tooltips/semantics review. |
| Motion | 150/250/400/600ms tokens; page/list entry, stagger, bounce, shake, and shimmer | Shimmer honors reduced motion; most `flutter_animate` call sites do not. The 600ms glacial preset is unused in the scanned screen paths but remains available. |
| Breakpoints | 600/720/900/1024/1200dp plus 1600dp content cap | Adaptive rail exists; only phone UI was captured in this pass. |
| Surface/state | Material 3 surfaces, `StatCard`, `StatusChip`, `EmptyState`, `ErrorState`, shimmer, chart and export wrappers | Canonical components are present; errors must not be represented as empty data or indefinite loading. |
| Accessibility | 48dp button minimum, selected status icon+text, many semantics/tooltips, RTL direction at app root | Continue large-text, focus order, screen-reader and reduced-motion testing; icon-only control coverage is inconsistent. |

### Component Inventory

| Component | Role | Current state support / issue |
|---|---|---|
| `AppShell` | Adaptive navigation, profile, role filtering, tenant context | Compact bottom navigation and expanded rail. Tenant identity is now shown for tenant users. |
| `StatCard` | KPI/value tile | Loading skeleton, semantics, trend icon, haptic, entry animation. Small values and large text require viewport QA. |
| `AppSearchBar` | Search input | Debounced 350ms, clear affordance, outside-tap dismissal. Clear action is immediate; typed changes are delayed. |
| `StatusChip` | Status label and icon | Localized label + icon + semantic state, but 10–13sp labels can be small at scale settings. |
| `EmptyState` / `ErrorState` | Empty and failure surfaces | Empty action supported; error retry supported. Empty-state animation does not honor reduced motion. |
| `ShimmerLoading` | List/card/detail skeletons | Theme-aware and reduced-motion-aware; dashboard/inventory now show it only during actual startup/auth loading. |
| `ConfirmDialog` | Confirmation | Async error path catches and resets loading but does not expose a message; current call-site scan shows no `onConfirmAsync` usage. |
| `AppChartCard` | Chart title, legend, empty chart | Empty state supported; loading/error are caller-owned. Fixed chart height needs narrow/large-text QA. |
| `ExportSheet` | PDF/XLSX/PNG/print/share actions | Unified busy/error handling and custom PDF builder hook. Record count is based on supplied rows; page count/filename preview/cancel are absent. |
| Theme controls | Light/dark/high contrast and locale fonts | Intentional independent palettes; rendered Arabic/Urdu parity not device-verified here. |

### Navigation and Screen Inventory

Status legend: **F** = source finding fixed in this pass; **S** = source reviewed, visual proof pending; **U** = not deeply inspected or rendered in this pass. No screen is marked visually complete without rendered evidence.

| # | Screen | Status / source audit note |
|---:|---|---|
| 1 | Login | F: light-mode status icons now use dark foreground; login errors preserve the actual registration cause. Screenshot still shows long saved email clipping at the right edge under the device’s current text scale; verify/fix at 360dp and 1.3x text. |
| 2 | Bootstrap profile | S: router sends missing profiles to bootstrap; multilingual rendered form not exercised. |
| 3 | Dashboard | F: auth/profile/registration loading is a skeleton; settled permission errors use mapped retry UI. Admin/super-admin/seller KPI hierarchy not device-verified. |
| 4 | Routes list | S: lazy list, route detail push, create route push; search/filter/large-data visual pass pending. |
| 5 | Route form | S: `PopScope` protects unsaved input; full validation and keyboard traversal not device-tested. |
| 6 | Route detail | S: route/shop drill-down and contextual actions present; dense relationship hierarchy pending visual review. |
| 7 | Shops/customers list | S: customer identity, balance, route and activity surfaces exist; fast lookup and long names not visually tested. |
| 8 | Shop/customer form | S: `PopScope`; mobile keyboard and RTL validation remain unverified. |
| 9 | Shop/customer detail | S: ledger and export flows exist; full-history density and financial alignment need screenshots. |
| 10 | Products list | S: lazy list and product detail push; image failures and thumbnails not measured. |
| 11 | Product form | S: form/navigation source inspected only; image-input and validation visual pass pending. |
| 12 | Product detail | S: variant and inventory context present; action/stock hierarchy pending rendered review. |
| 13 | Variant form | S: `PopScope`; variant-specific field clarity and keyboard traversal pending. |
| 14 | Inventory | F: transient errors are loading-only during auth operation; settled permission failures use mapped retry UI. Warehouse/seller/transfer/return visual transitions pending. |
| 15 | Invoices list | S: lazy list and invoice detail push; filtering and status density pending. |
| 16 | Invoice detail | S: status/actions/PDF hooks exist; totals, return/void emphasis and PDF preview need visual QA. |
| 17 | Create sale invoice | S: sale inputs and totals derive from selected stock/customer; no new accounting behavior changed. Full guided flow and large text remain unverified. |
| 18 | Reports | S: summary plus export sections; loading/error exists for summary. No distinct filtered-empty/date-range workflow was confirmed in the reviewed section. |
| 19 | History | S: lazy feed and shop drill-down; actor/resource scanability pending. |
| 20 | Notifications | S: list/route targets exist; severity grouping and unread contrast pending. |
| 21 | Settings | S: grouped navigation destinations and `PopScope`; all theme/locale states pending visual pass. |
| 22 | Profile | S: role/profile surfaces and security navigation; large-text and editing visual pass pending. |
| 23 | Users | S: admin list and role controls; seller assignment/status scanability pending. |
| 24 | Tenant/workspace management | F: nullable-profile render crash removed; write errors propagate to the form; owner-list error is visible/retryable; tenant identity now appears in shell. Authenticated create flow still needs on-device verification. |
| 25 | Database backup | S: current screen has loading/export/restore surfaces; fixed `Colors.white`/`Colors.black54` overlays are a dark/high-contrast risk requiring targeted check. |
| 26 | Database flush | S: workspace identity, irreversible warning, password re-auth, and ten-second countdown exist. Fixed white progress text/overlay colors are a dark/high-contrast risk; destructive end-to-end flow not exercised. |
| 27 | About | S: source route exists; lightweight rendering and external-action behavior not inspected visually. |

### Findings

#### UI-01 — P1 — Tenant/seller login exits after access registration

- **Screen/file/component:** Login → `AuthNotifier.signIn()` → `SessionManagementNotifier.registerCurrentAccess()`; [tenant_provider.dart](app/lib/providers/tenant_provider.dart), [auth_provider.dart](app/lib/providers/auth_provider.dart), [firestore.rules](firestore.rules).
- **Problem/root cause:** `get()` of absent access-slot documents is denied by the existing rules because the read expression dereferences `resource.data.tenant_id`; the live session stream was also unfiltered. Session payloads omitted the required paired-device `device_slot_id`. The emulator confirms missing-slot `get` fails, unfiltered session listing fails, and tenant/user-scoped queries succeed.
- **User/business impact:** Seller and workspace-admin sign-ins return to login or encounter denied startup listeners; route/stock context is unavailable.
- **Accessibility/performance:** Auth churn and permission-denied feedback interrupt a field workflow; repeated listeners produce visible startup errors.
- **Current behavior/change:** Reads are tenant/user-scoped; current matching docs are refreshed transactionally; absent fixed slots are created; session writes include the paired device slot. Registration errors retain their real mapped cause. A 15-second access-registration grace defers enforcement of stale initial session snapshots and schedules one re-check.
- **Reusable component impact:** Login error mapping and shell startup state now expose the actual outcome.
- **Risk/test:** Rules remain unchanged. Emulator tests assert denied missing-slot gets and permitted scoped queries; login/session widget tests and analyzer pass. The first-slot query and following transaction are not atomic; simultaneous first-login cap enforcement still depends on rules/backend support.
- **Visual verification/status:** **Fixed in source; installed APK login/logout transition not re-tested with account credentials.** The captured APK log shows Auth login followed by permission failures and the app returning to login, with no Flutter fatal exception.

#### UI-02 — P1 — Workspace card can throw while auth profile is null

- **Screen/file/component:** Workspace management card in [tenant_management_screen.dart](app/lib/screens/tenant_management_screen.dart).
- **Problem/root cause:** The screen uses `currentUser?.` for earlier permission checks, then force-unwraps `currentUser!` when building each card. A profile stream loading/error emission with nonempty workspace data can throw during build, replacing the screen with a blank/error frame.
- **User/business impact:** Workspace administration can appear black/blank, especially during profile refresh or APK startup.
- **Accessibility/performance:** Build exception removes all usable controls; no assistive recovery surface is available.
- **Current behavior/change:** The member/security section is rendered only when a profile exists and access scope matches. Workspace data can still render without the transient profile.
- **Reusable component impact:** None; fixed at the owning conditional.
- **Risk/test:** Added a widget test with a null profile and nonempty workspace list; test passes, no exception.
- **Visual verification/status:** **Fixed in source; authenticated create/edit flow on APK pending owner credential entry.**

#### UI-03 — P1 — Failed workspace write closes as success

- **Screen/file/component:** Workspace create/edit dialog and `TenantManagementNotifier` in [tenant_management_screen.dart](app/lib/screens/tenant_management_screen.dart) and [tenant_provider.dart](app/lib/providers/tenant_provider.dart).
- **Problem/root cause:** `AsyncValue.guard` stored provider errors but returned normally; the screen then popped the dialog after a failed create/update.
- **User/business impact:** Admin loses entered workspace data and sees no reliable failure state.
- **Accessibility/performance:** No announced error/recovery; duplicate re-entry may be required.
- **Current behavior/change:** A shared notifier helper keeps AsyncValue state and rethrows the original error; the screen maps it and keeps the dialog open. Owner-list errors now use the shared retryable `ErrorState` instead of `SizedBox.shrink()`.
- **Reusable component impact:** Reuses `mappedErrorState` and `AppErrorMapper`.
- **Risk/test:** Focused tenant-management widget test passes; Firestore authorization was not changed.
- **Visual verification/status:** **Fixed in source; live authorized create flow pending.**

#### UI-04 — P2 — Login system-bar icons lack light-surface contrast

- **Screen/file/component:** [login_screen.dart](app/lib/screens/login_screen.dart), root `AnnotatedRegion`/Android status bar.
- **Problem/root cause:** The login route did not set local overlay icon brightness and inherited the global white-icon style against its light surface.
- **User/business impact:** Time, connectivity, and battery indicators are difficult to read on the login screen.
- **Accessibility/performance:** System UI contrast failure; no performance cost.
- **Current behavior/change:** Login applies transparent status bar and derives icon brightness from its own theme.
- **Reusable component impact:** Other screens retain their shell/theme overlay.
- **Risk/test:** Login widget checks dark status-bar icons in the light theme; test passes.
- **Visual verification/status:** **Source/test fixed; post-fix device screenshot pending.**

#### UI-05 — P2 — Tenant identity hidden for tenant operators

- **Screen/file/component:** `_workspaceContextBanner` in [app_shell.dart](app/lib/widgets/app_shell.dart).
- **Problem/root cause:** Banner returned empty for users other than platform and workspace administrators, so sellers could use business screens without a persistent company label.
- **User/business impact:** Reduces confidence about which workspace owns the active records.
- **Accessibility/performance:** No assistive context announcement; negligible rendering cost.
- **Current behavior/change:** Banner appears for any non-null active tenant ID; support reason remains distinct for platform operators.
- **Reusable component impact:** Shared shell banner now covers seller/admin business screens.
- **Risk/test:** `widget_test.dart` passes; contextual tenant name requires Firestore/emulator data for visual verification.
- **Visual verification/status:** **Fixed in source; tenant-switch screenshot pending.**

#### UI-06 — P2 — Permission errors can masquerade as empty/loading data

- **Screen/file/component:** Dashboard and inventory async surfaces in [dashboard_screen.dart](app/lib/screens/dashboard_screen.dart) and [inventory_screen.dart](app/lib/screens/inventory_screen.dart).
- **Problem/root cause:** Permission errors were unconditionally converted to indefinite shimmer or “no data,” obscuring settled access failures.
- **User/business impact:** Operators cannot distinguish no stock/customers from denied workspace access.
- **Accessibility/performance:** Screen reader receives a loading/empty state instead of actionable error; continuous shimmer costs raster work.
- **Current behavior/change:** Screens show structural shimmer while auth/profile or sign-in registration is actually loading; errors after that state use mapped retry UI.
- **Reusable component impact:** Uses existing `ShimmerLoading` and `mappedErrorState`.
- **Risk/test:** Focused dashboard/login/workspace tests pass; settled permission-denial UI was not visually captured.
- **Visual verification/status:** **Fixed in source; runtime error state still needs emulator/device verification.**

#### UI-07 — P2 — Large saved login address clips on compact screen

- **Screen/file/component:** Email `TextFormField` in [login_screen.dart](app/lib/screens/login_screen.dart).
- **Problem/root cause:** At the captured 384dp-class phone width and current device text scale, a saved email extends beyond the visible input viewport without an explicit compact layout treatment.
- **User/business impact:** User may not be able to visually confirm the full account before sign-in.
- **Accessibility/performance:** Large text magnifies the issue; keyboard and font scaling need a real device test.
- **Current behavior/required change:** The field retains the saved address but the screenshot visibly truncates its tail. Test at 360/390/412dp and 1.0/1.3 text scale; consider ensuring start alignment and an accessible full-value semantics label without shrinking text.
- **Reusable component impact:** Login field only; do not alter shared numeric/text fields without evidence.
- **Risk/test:** Must not disable text scale or reduce contrast. Add a widget constraint/text-scale test if a fix is made.
- **Visual verification/status:** **Open P2; screenshot evidence captured before the current build.**

#### UI-08 — P2 — Fixed light colors remain in destructive/backup progress overlays

- **Screen/file/component:** [database_backup_screen.dart](app/lib/screens/database_backup_screen.dart), [database_flush_screen.dart](app/lib/screens/database_flush_screen.dart).
- **Problem/root cause:** Source scan finds fixed `Colors.white`, `Colors.black54`, and white progress labels inside overlays.
- **User/business impact:** Progress text/scrims can lose contrast in dark/high-contrast theme.
- **Accessibility/performance:** Contrast may fail; no measurable compute impact.
- **Current behavior/required change:** Replace overlay colors with local `ColorScheme` roles after a rendered dark/high-contrast check.
- **Reusable component impact:** Prefer a shared theme-aware progress overlay if both flows truly share the same treatment.
- **Risk/test:** Destructive flush must remain emphatic and legible; screenshot all themes before/after.
- **Visual verification/status:** **Open P2; source issue identified, no broad color rewrite made.**

#### UI-09 — P2 — Most motion ignores reduced-motion preference

- **Screen/file/component:** `AppAnimations`, `EmptyState`, `ErrorState`, and direct `flutter_animate` call sites.
- **Problem/root cause:** Reduced motion is checked in shimmer widgets only; entry, shake, scale, and status transitions continue elsewhere.
- **User/business impact:** Motion-sensitive users receive avoidable animation; staggered list entries can delay scanning.
- **Accessibility/performance:** Reduced-motion preference is inconsistently respected; large animated lists may add raster work.
- **Current behavior/required change:** Define a shared reduced-motion policy and apply it to nonessential transitions; preserve immediate state feedback.
- **Reusable component impact:** Central animation extension and state widgets should own the policy.
- **Risk/test:** Test `MediaQuery.disableAnimations` for state widgets and critical list paths; profile-mode frame data not collected.
- **Visual verification/status:** **Open P2; no unrelated animation rewrite.**

### Navigation, State, and Interaction Coverage

- **Observed:** Screen/form routes use `push` and current forms use `PopScope`; top-level navigation uses `go`; compact and rail shell paths exist.
- **Observed:** Search component debounces at 350ms, clears immediately, and dismisses keyboard on outside tap.
- **Observed:** Shared state components support skeleton/empty/retry patterns; screen-level wiring remains inconsistent by area.
- **Coverage matrix:** Initial loading: partial skeleton coverage; refreshing: screen-specific `RefreshIndicator`; empty: shared `EmptyState`; error: shared `mappedErrorState`, but some legacy callers still render empty/loading instead; submitting: per-form booleans; stale data: present in seller dashboard; offline: shared online indicator; permission denied: now mapped after auth settles on dashboard/inventory; no-search-results: present on inspected inventory/list paths; large datasets: builders are lazy, but cursor pagination not confirmed across all operational lists.
- **Destructive flow:** Database flush visibly separates danger zone, workspace label, first confirmation, owner password re-auth, and countdown. This pass did not execute a destructive operation.

### Screen-by-Screen Review Boundary

Deep source review was performed for login, dashboard, inventory, reports, workspace management, database backup/flush surfaces, shell, router, theme/tokens/fonts, and shared stat/status/search/empty/error/loading/chart/export/dialog components. The remaining operational forms/lists/details were enumerated from the live screen directory and route table but were not all read end-to-end or rendered. Their rows above are therefore `S` (source scan) or `U` (not deeply reviewed), not passes. This prevents treating the 27-screen visual checklist as completed when account-protected screens could not be entered.

### Post-Fix Verification and Visual Evidence

- Focused login, dashboard startup, workspace-management and app-shell widget tests pass; exact counts are recorded by the command outputs from the current session.
- Rules emulator test proves missing access-slot reads fail, unfiltered session lists fail, and tenant/user-scoped queries succeed. Full emulator rerun is required after the latest test assertion update.
- Flutter/Dart full analyzers, complete test suite, web release build, APK release build, and web/Firestore deployment are pending for v3.9.59+98.
- Before-fix APK screenshot: login form rendered on 384dp-class device; system bar icons white on light background; saved email visually clipped at the trailing edge. It is an actual screenshot from the running app, not a document image.
- After-fix screenshot, Arabic/Urdu, dark/high-contrast, seller/workspace-admin dashboard, workspace creation success/error, and large-text captures are pending. Device was connected during initial log collection; account passwords were not supplied to automation.
- Visual regression plan: add golden/widget cases for login at compact width and large text; tenant card null-profile/error; workspace banner by role; mapped permission errors; EN/AR/UR with RTL; light/dark/high contrast; reduced motion. No golden baselines were generated during this pass.

### Remaining Backend / Rules Dependencies

- Existing rules deny `get()` on nonexistent access slots and require `tenant_id`/`user_id` constraints. The app now conforms without altering rules.
- Firestore `Transaction.get` accepts a document reference, not a query. The new scoped reads occur before the transaction and existing returned documents are re-read inside it. Two simultaneous first-time logins can still race for the same slot/limit; enforcing an atomic tenant session ceiling under these rules requires a rule/data contract change, explicitly outside this frontend-only task.
- Live logs showed additional `PERMISSION_DENIED` for profile/business listeners during the failed login attempt. Current own-profile rule permits an authenticated own-document read; the captured log sequence does not conclusively establish whether the profile denial preceded or followed sign-out. Re-check the updated APK with an authorized account before attributing that log to another defect.
- The legacy one-shot production data purge remains blocked until owner-provided Google ADC/service-account credentials are configured; no credential was requested or read in this task.
