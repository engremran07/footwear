# ShoesERP — Ultimate Master Audit Report

**Audit version:** v13 (88-agent governance pack v2.0)  
**Date:** 2026-04-11  
**App version:** v3.5.0+43 (post-remediation)  
**Auditor:** GitHub Copilot (Claude Sonnet 4.6) — autonomous multi-agent system  
**Baseline commit:** 3377697 (v3.4.11+42)  
**Branch:** main  
**Firebase project:** shoeserp-clean-20260327

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
