# ShoesERP AI Coding Rules (CLAUDE.md)

Last updated: 2026-10-25

## Runtime Override (Always First)

The live codebase is a route/seller distribution ERP.

- Roles: admin, seller (manager must be admin-equivalent)
- Super-admin is platform-only by default. Tenant business data requires explicit `active_workspace_id` plus a reasoned support context; selection start/end is written to append-only `platform_access_logs`.
- Firebase Auth is the app's only sign-in mechanism. The app has no custom device registration, pairing approval, session slots, or session renewal; Firestore Rules enforce active profile, role, tenant, and selected-workspace scope.
- Business-data access additionally requires an active tenant document. An active user profile does not override an inactive workspace; the explicitly selected super-admin restoration path is the limited exception.
- Collections: users, products, product_variants, seller_inventory, inventory_transactions,
  routes, shops [Firestore name: 'customers' — legacy, use Collections.shops],
  transactions, invoices, settings
- Stock unit: DOZENS primary (1 dozen = 12 pairs). quantity_available stores
  pairs; UI inputs/displays in dozens. Extra pairs (0–11) are optional per entry.
- Routing source: app/lib/core/router/app_router.dart

If any legacy section conflicts with runtime truth, runtime truth wins.

## Must-Check Before Edits

1. app/lib/models/user_model.dart
2. firestore.rules
3. app/lib/core/constants/collections.dart
4. firestore.indexes.json

## Hard Rules

1. Do not write Firestore directly from screens/widgets.
2. All writes go through provider notifiers.
3. Use Timestamp.now() for Firestore timestamps.
4. Catch and map Firebase exceptions via AppErrorMapper.
5. Dashboard must never fail all stats when one aggregate fails.
6. Dashboard and inventory must not surface transient permission-denied or unauthenticated states during startup; keep role-scoped UI in loading, empty, or cached fallback until auth/profile streams settle.
7. Any where+orderBy query requires index entry when fields differ.
8. Keep role handling canonical and normalized (trim/lowercase in app writes).
   Tenant-aware roles (tenant_admin, super_admin) must be treated as privileged roles and must carry a tenant_id in new documents and in the user profile.
  Workspace settings are tenant-scoped. Workspace administrators may manage business settings within their workspace; device-pairing and custom session-cap policies are not part of the runtime.
9. Keep admin-only write enforcement in submit methods (screen-level defense in depth).
10. Validate required identity fields (for example created_by/route_id/shop_id) before provider writes.
11. No Firebase Storage — company logos stored as base64 in Firestore, product images use external HTTP URLs. Do not add firebase_storage dependency.
12. When shipping both web and APK, keep `app/pubspec.yaml` and `app/lib/core/constants/app_brand.dart` on the same release version/build and rebuild both surfaces from that version before calling them synced.
13. Do not cache Flutter web shell files immutably in Firebase Hosting; stale `main.dart.js` and bootstrap files are a release regression.
14. Shops ARE the customers. One entity: shops (Firestore collection: 'customers' — legacy).
    Never create a separate Customer model, collection, or route. No /customers routes exist.
    All invoices and transactions reference shop.id as both shop_id AND customer_id
    (dual-write for backward compatibility with pre-unification documents).
15. Stock tracking and selling unit is DOZENS (1 dozen = 12 pairs). quantity_available
    in Firestore stores PAIRS for legacy compat. UI always shows and accepts dozens as
    primary, with optional extra pairs (0–11). Android release artifact path is
    split-per-ABI: flutter build apk --release --split-per-abi --dart-define=USE_PLAY_INTEGRITY=true --dart-define=use_arabic=true.
16. Admin has no assigned_route_id — admin is the warehouse AND a field seller.
    Admin can own seller_inventory docs (seller_id = adminUid). isAdmin() in Firestore
    rules covers all admin operations including self-stock-allocation.
17. If a bug was addressed by multiple candidate fixes, and QA/user confirms the
    real culprit, you MUST run the Band-Aid Loop Reversal protocol: keep root-cause
    and mandatory guards, rollback non-culprit mitigations, and record final reasoning.
18. All export/report name resolution MUST use `NameResolver` (`name_resolver.dart`).
    Never build ad-hoc uid→name maps. Never fall back to a raw UID string.
    Use `trRead()` with locale for all export string literals — no hardcoded English.
    Every Flutter test, run, and build that can generate PDFs must pass
    `--dart-define=use_arabic=true`; without it, the PDF package reorders RTL
    text but does not shape Arabic-script letters. The shared font loader
    fails closed with a localized configuration error if the flag is missing.
    PDFs embed Noto Sans Arabic for Arabic and Urdu; the renderer does not
    provide full Nastaliq OpenType shaping, so Noto Nastaliq Urdu is UI-only.
    Bilingual PDF rows must use an explicit LTR `pw.Directionality` wrapper
    for English-left/RTL-right placement; `pw.Row` has no direction parameter
    in the pinned `pdf` 3.12.0 API. Verify actual Arabic and Urdu renders.
    PNG, print, and PDF share the generated PDF bytes. XLSX preserves Unicode
    and RTL sheet direction but does not embed a font.
19. Every `ExportSheet.show()` call MUST provide `pdfBytesBuilder` when the data is a
    ledger, account statement, or seller report. The generic `buildPdfTable()` fallback
    is only acceptable for simple flat tables (inventory list, shops list). If the export
    contains running balances, debit/credit columns, or an Entry By column, the caller
    MUST supply a custom `pdfBytesBuilder` that calls the appropriate builder
    (`buildPdfLedger`, `buildPdfSellerReport`, `buildPdfMultiShopLedger`).
20. `changelog_data.dart` MUST be updated on every version bump. When `app/pubspec.yaml`
    version is bumped, a corresponding entry MUST be added to
    `app/lib/core/data/changelog_data.dart` with trilingual (EN/AR/UR) descriptions.
    The `whats_new_sheet.dart` auto-displays the latest changelog on first launch after
    update. Skipping this means users see stale "What's New" content.
21. Task continuity is mandatory. When a user adds new work mid-session, the agent MUST
    merge new tasks into the existing todo list — never discard, replace, or forget
    previous tasks. Review conversation history and session memory before creating a new
    todo list. Incomplete tasks from prior prompts carry forward automatically. If a prior
    task is no longer relevant, mark it explicitly as "dropped — reason: ..." rather than
    silently removing it.

22. Google Drive backup is least-privilege and scope-bound. Web builds must receive
  `GOOGLE_DRIVE_CLIENT_ID`; Android builds must receive the matching web
  `GOOGLE_DRIVE_SERVER_CLIENT_ID`. Sellers may restore only their own records
  for currently assigned routes. Super admins must select a concrete tenant
  before backup or restore. Never silently fall back to a global snapshot.
  Sellers may save encrypted route archives to phone storage, restore only
  their own unlinked cash rows with atomic shop-balance reconciliation, and
  explicitly upload an existing archive to Drive when online. This is a
  user-triggered retry, not background synchronization.
23. Never store or ship service-account credentials. Arbitrary-user Auth administration belongs in a trusted backend; the client may not create/promote super-admins or mutate another user's Auth credentials.
24. Platform super-admins may read workspace metadata globally, but every business-data operation must be scoped to the selected workspace and an auditable support reason. No selection means no business records.
25. Super-admin business-context selection and exit events are append-only in `platform_access_logs`. Never create/promote platform super-admin accounts or mutate another user's Auth credentials from client code. Never store service-account credentials in Firestore, backups, APKs, or web builds.
26. Super-admin business context expires after 8 hours in Firestore rules. Workspace admins may update only workspace-scoped business settings; workspace lifecycle and other platform configuration remain platform-controlled. Do not restore app-managed device registration, pairing, or session-slot enforcement.
27. Require a concrete tenant for every new business write via `TenantScope.requireTenant`; never replace missing tenant identity with `__global__`. Unassigned users must not be silently self-healed into a shared tenant.
28. Local admins manage seller profiles only. Workspace-admin role changes require an active platform super-admin workspace context.
29. Seller stock decrements must match a same-batch sale invoice's exact `seller_inventory_deductions` entry. Every warehouse stock mutation requires an atomic tenant-scoped inventory audit row.
30. Admin financial corrections append the prior amount/type/date, actor, and a reason of at least 10 characters to `edit_history`; invoice-linked transaction amounts/types/dates are immutable outside void/credit-note flows. Standalone cash-in/cash-out transactions may only be soft-deleted by a tenant admin-equivalent with an exact atomic shop-balance reversal and correction transaction link. Clear cached last-transaction fields only if they point at the deleted row. Sellers, invoice-linked entries, and hard deletes are denied.
31. Shop creation starts with a zero balance and no fabricated last-transaction fields. Standalone transactions must be linked to a same-batch shop/balance update. Invoice batches may contain multiple ledger rows and use validated invoice references plus aggregate balance changes; do not impose a one-row/one-delta rule.
32. Export queries must cursor-page to exhaustion. Tenant-admin backup restore is upsert-only and never prunes; selected super-admin restore upserts before pruning obsolete records in the active tenant. Reject legacy plaintext backup archives.
33. Keep users signed in through transient token-refresh/network failures. Firebase initialization failure must render a retry state and must not mount the normal app shell.
34. Copilot chat history and request IDs do not merge across GitHub identities through repository changes. Preserve durable decisions, pending tasks, audit IDs, and verification evidence in `SESSION_LOG.md` and the current audit report. On an account/profile switch, read those plus `git status`/`git diff`; never store credentials or full chat transcripts in the repository or claim separate accounts were synchronized.
35. Workspace-root hard deletion is denied; use the selected-workspace archive/restore lifecycle. Database flush/reset actions and legacy plaintext whole-project export, whole-collection restore, and direct-balance reset scripts must remain fail-closed until a transactional, audited maintenance path preserves tenant, ledger, and inventory invariants.
36. Missing-document Rules reads must be narrowly scoped to an active profile and concrete active tenant; super-admins additionally require selected-workspace support context. Only admin-equivalent users may probe missing seller inventory, and only super-admins may probe settings for a tenant that does not yet exist. Cover client reads and their complete transaction writes in emulator regressions; do not use a blanket `resource == null` allowance.
37. Financial PDFs use the shared workspace header with English content left
    and the selected Arabic/Urdu content right, independent of app locale.
    Current workspace logo bytes take priority; invoice snapshots provide a
    logo fallback when current bytes are unavailable, subject to the saved
    `visibleFields` setting. Cash receipts are A5 and single-page. Preserve
    the `use_arabic=true` shaping gate; verify font/image resources, page size,
    page count, and rendered layout separately.

## Frontend UI Governance

Use `.github/instructions/frontend-design-system.instructions.md` as the
authoritative Flutter UI contract and
`.claude/skills/flutter-frontend-modernization/SKILL.md` to coordinate broad
screen work. Extend the existing `AppTokens`, `AppTheme`, `AppFonts`,
`AppAnimations`, and shared widgets; do not create a parallel design system.
Inspect the actual router and shell before changing navigation. Preserve
authentication, tenant scope, provider write boundaries, financial and stock
semantics, and role guards. Do not assume a user-visible change authorizes a
version bump, build, deployment, commit, or push.
Shared interactive controls use `AppTokens.minTouchTarget` where applicable.
Optional shared-component transitions honor `MediaQuery.disableAnimations`
through `AppMotion`; custom GoRouter fade/slide transitions must return their
child without optional effects when reduced motion is enabled. Visible-value
semantics use the active locale. Widget tests must cover these contracts,
relevant theme contrast, and RTL direction where the component supports it.

## Financial Pathways (never mix these)

```text
Pathway 1: STOCK SALE
  → CreateSaleInvoiceScreen → InvoiceNotifier.createSaleInvoice()
  → Invoice + cash_out tx + optional cash_in tx + seller_inventory deduction
     (all in one atomic batch)
  → USE WHEN: new goods are delivered and seller inventory must decrease

Pathway 2: NON-STOCK SALE
  → CreateSaleInvoiceScreen → InvoiceNotifier.createSaleInvoice(fulfillmentMode: non_stock)
  → Invoice + cash_out tx + optional cash_in tx + shop balance update
  → No inventory deduction; catalog variants and quantities remain on the invoice
  → Allowed only when the workspace setting enables non-stock invoices

Pathway 3: CASH RECEIPT INVOICE (old debt, no new goods)
  → CreateSaleInvoiceScreen → InvoiceNotifier.createCashReceipt()
  → Receipt invoice + cash_in tx + receipt sequence + shop.balance reduction
     (all in one tenant-scoped Firestore transaction)
  → No stock movement; receipt number and workspace header are snapshotted

Pathway 4: LEDGER-ONLY CASH COLLECTION (no receipt document)
  → ShopDetailScreen → TransactionNotifier.create(type: 'cash_in')
  → Cash_in ledger entry ONLY. No invoice. No stock movement.
  → USE WHEN: recording a payment without issuing a receipt invoice

VOID / RETURN:
  → InvoiceNotifier.voidInvoice() — admin only
  → Returns stock only for stock-backed invoices
  → Two refund modes: cashRefund (cheque/cash paid back) or creditBalance (deduct from balance)
  → Issues ONE reversal transaction (return tx). Cash refund adds a second cash_out tx.

NEVER create a sale invoice for cash-only collection.
NEVER create a standalone transaction for a new goods sale (always through invoice).
```

## shop.balance Single Pipeline (non-negotiable)

`shop.balance` is the **sole source of truth** for every monetary display in the app:

| Screen / Widget | Source |
| --- | --- |
| Shop detail — Total In / Total Out boxes | Live sum of `shopTransactionsProvider` stream |
| Shop detail — balance badge color | `shop.balance` field |
| Route detail — outstanding total | `shops.fold(shop.balance)` |
| Dashboard AR widget | `outstandingShopsProvider` → `shop.balance` |

**Write pipeline (atomic — no exceptions):**

```text
User action → Screen → Provider notifier (InvoiceNotifier / TransactionNotifier)
  → Firestore batch: write transaction doc + update shop.balance in same commit
```

**NEVER bypass this pipeline.** Direct Firestore writes that touch `transactions`
or `invoices` WITHOUT also updating `shop.balance` will produce stale UI across
all screens instantly.

**Database reset and workspace lifecycle:** Bulk client flush/reset actions and
the legacy plaintext backup/restore and direct-balance reset scripts are
disabled. Multi-batch client cleanup can partially delete linked records or
violate the atomic shop-balance ledger contract. Use encrypted, workspace-
scoped app backups for supported restore workflows. Workspace lifecycle is
archive/restore only; Firestore Rules deny tenant-root hard deletion. A
selected platform super-admin may select an existing inactive workspace with
an audited reason to restore it. Lifecycle updates change only tenant status
fields; member profiles remain unchanged and business Rules stay closed until
the tenant is active.

## Failure Playbooks

### permission-denied

- Check user doc active=true
- Check role value in users doc
- Check role parsing in app model
- Check Firestore rules role checks
- Redeploy rules if changed

### resource-exhausted

- Use per-metric safe aggregate calls
- Use cached last-good dashboard stats as fallback
- Reduce aggressive refresh loops

### list data missing

- Check query shape
- Add missing composite index
- Deploy indexes

## Documentation Sync Rule

If architecture behavior is changed, update in same patch:

- AGENTS.md
- CLAUDE.md
- README.md
- app/README.md
- SYSTEM_DEEP_DIVE_2026-03-27.md

## Breakage Chain Reference

### Chain 1: Collection Rename

`collections.dart` constant renamed → providers silently break → rules reference stale name → indexes stale  
**Fix order:** constants.dart → providers → rules → indexes → `firebase deploy --only firestore:rules,firestore:indexes`

### Chain 2: Auth Provider Leak

New admin-data provider added → not in `_invalidateRoleScopedProviders()` → seller inherits admin data after logout  
**Fix:** After every new provider, grep-confirm it's in `auth_provider.dart::_invalidateRoleScopedProviders`.

### Chain 3: Rules + App Role Mismatch

Rules check 'admin' exactly; app writes 'Admin' (casing) → all admin writes fail  
**Fix:** `isAdminRole()` regex in rules + `role.trim().toLowerCase()` before every Firestore write.

### Chain 4: Composite Index Gap

`where(A) + orderBy(B)` added → no index → list renders empty, no error in UI  
**Fix:** Add entry to `firestore.indexes.json` → `firebase deploy --only firestore:indexes`.

### Chain 5: Transitive Dep Wasm Lock

Add a pub package that locks a shared transitive dep (e.g. `archive`) to an old major version → Wasm dry-run violations appear in `flutter build web` from a DIFFERENT package that needs the newer version.  
**Symptoms:** `avoid_double_and_int_checks lint violation` in `flutter build web --release` from a third-party package file you did NOT write.  
**Diagnosis triage:**

1. `flutter pub deps --style=list | grep -A5 '<failing package>'` → find who introduced the dep
2. `flutter pub outdated` → find latest compatible version
3. Check pub.dev changelog for the failing package — search for "Wasm" and "archive"
4. Identify the blocking parent package and what `archive` range it requires
**Fix:** Replace or upgrade the blocking package, OR write a direct replacement if no compatible version exists. Do NOT use `dependency_overrides` to force incompatible archive versions — it compiles but breaks at runtime.  
**This project (history):** `excel 4.0.6` locked `archive ^3.x` which blocked `image` from upgrading past 4.3.0 (which had the violations). Fixed by replacing `excel` with a custom xlsx writer using `archive ^4.0.0` directly.

### Chain 6: StateProvider Lifecycle

`StateProvider` used → Riverpod 3 removed it from main export → compilation failure on upgrade  
**Fix:** Replace every `StateProvider<T>` with `NotifierProvider<T extends Notifier<S>, S>` plus an explicit `Notifier` subclass with `build()` and a setter method. Write sites: `.notifier).state =` → `.notifier).set(value)`.  
**This project (history):** `appLocaleProvider` and `lastGoodDashboardStatsProvider` converted in v3.6.0+47. `grep -rn "StateProvider\b" app/lib/` → zero.

## Band-Aid Loop Reversal Protocol

Trigger this protocol when all are true:

1. Two or more fixes were applied to the same symptom.
2. It is unclear which change truly solved the issue.
3. QA/user confirms the symptom stopped after a specific change.

Required actions:

1. Build a fix ledger: change, hypothesis, observed effect, keep/remove decision.
2. Classify each fix: `root-cause`, `mandatory-guard`, `temporary-mitigation`.
3. Rollback temporary mitigations incrementally and re-test after each rollback.
4. Keep only root-cause + mandatory safeguards.
5. Publish closure evidence showing exactly which change fixed the bug.

Never keep ambiguity-driven workaround code without explicit justification.

## Vibe-Coded Debt Signals

| Pattern seen | What it signals | Correct pattern |
| --- | --- | --- |
| `db.collection('transactions')` | Raw collection string | `db.collection(Collections.transactions)` |
| `if (user.isSeller && ...)` on stock source | Admin silently excluded | `sellerInventoryProvider(user.id)` for all |
| `.where('deleted', isEqualTo: false)` | Pre-DI-01 docs excluded | Client-side `d.data()['deleted'] != true` |
| `ref.read(provider)` in `build()` | Stale data guarantee | `ref.watch(provider)` |
| ABI-split APK build command | Wrong split APK | `flutter build apk --release --split-per-abi --dart-define=USE_PLAY_INTEGRITY=true --dart-define=use_arabic=true` |
| Hardcoded `Colors.red`, `Colors.white` | Dark mode breakage | `AppBrand.errorFg`, `AppBrand.errorBg` |
| Raw `SnackBar(content: Text(...))` | Unstyled SnackBar | `errorSnackBar()` / `successSnackBar()` |
| `avoid_double_and_int_checks lint violation` in web build | Transitive dep locked to old `image`/`archive` by another pkg | Find blocking package; replace or upgrade it — see Chain 5 |
| `flutter build web --release` exits 1 with no Error lines | PowerShell `NativeCommandError` from Wasm dry-run stderr — build IS succeeding | Check `$LASTEXITCODE` explicitly; exit 0 = real success |
| `StateProvider<T>` in any `.dart` file | Riverpod 3 removed `StateProvider` — instant compile failure on upgrade | Replace with `NotifierProvider<T, S>` + `Notifier` subclass — see Chain 6 |
| `ExportSheet.show(` without `pdfBytesBuilder` on ledger data | PDF export fails or produces flat table instead of ledger | Always pass `pdfBytesBuilder: () => buildPdfLedger(...)` for ledger exports |
| PDF generation without `--dart-define=use_arabic=true` | The PDF package can bidi-reorder Arabic/Urdu without shaping | Keep the flag on every PDF-capable action; the shared font loader rejects unshaped output |
| `labels['key'] ?? 'English Fallback'` in PDF builders | Hardcoded English bypasses i18n | Use `trRead()` with locale; `??` fallback must be `'—'` or localized key |
| Missing `ChangelogVersion` entry after version bump | Users see stale "What's New" content | Add trilingual entry to `changelog_data.dart` on every version bump |
| `ref.read(authUserProvider).value` in async/export context | Null during stream loading → empty data or crash | `await ref.read(authUserProvider.future)` in all async/provider contexts |

## Vibe Debugging Anti-Patterns (Mandatory Awareness)

| Anti-Pattern | Definition | Prevention |
| --- | --- | --- |
| Whack-a-Mole Debugging | Each "fix" makes a new problem pop up elsewhere | Grep ALL instances of a bug pattern before fixing any single one |
| Symptom Chasing | AI fixes the error message, not the root cause | Trace full call stack before writing any fix code |
| Regression Spiral | 20 commits of increasing complexity for a 5-line fix | If diff > 50 lines for one bug, stop and re-evaluate |
| Vibe Debt | Accumulated complexity from AI-generated code nobody understands | Understand every line you write; never copy-paste without tracing |
| Confidence Theater | "Fixed!" with evidence (tests pass) but bug untouched | Claim requires exact code-path trace, not just "tests pass" |

## Scope-Aware Verification and Release

Run checks that match the requested change. There is no unconditional
release/deployment sequence for every code edit.

### Local Validation

- For Dart changes, run relevant tests and `flutter analyze lib --no-pub`.
- For test changes, run the targeted suite and `dart analyze test/`.
- For Firestore Rules changes, run the Rules Emulator suite from
  `tests/firestore-rules/`:

  ```powershell
  Push-Location tests/firestore-rules
  firebase emulators:exec --only firestore "npm test"
  Pop-Location
  ```

- For Markdown changes, run the repository Markdown lint command.
- Quote exact tool output for every validation claim. A focused suite's count
  is not the full-suite count.

### Production and Release Authorization

Version bumps, release builds, Hosting/Rules deployment, production data
changes, device installation, commits, pushes, tags, and GitHub releases are
separate operations. Perform them only when explicitly authorized by the user.

The current workflow side effects are:

- A push to `main` runs `.github/workflows/deploy-web.yml`, which deploys
  Firebase Hosting and Firestore Rules/indexes.
- A version tag or authorized manual dispatch can run
  `.github/workflows/release.yml`, which builds and deploys release surfaces.
- `.github/workflows/build-apk.yml` is a manual APK artifact build.

Do not push or dispatch a workflow as an implicit way to obtain deployment
permission. State clearly when production state and release artifacts remain
unmodified.

## Anti-Bypass Enforcement Matrix

| Claim made | Required evidence (non-bypassable) |
| --- | --- |
| "No analyze issues" | Must quote exact final line: `No issues found! (ran in Xs)` |
| "Dart analyze test clean" | Must quote: `No issues found!` |
| "Tests pass" | Must quote: `All N tests passed!` with N count |
| "APK built" | Must quote file path + size from build output |
| "Web built" | Must state `EXIT: $LASTEXITCODE` = 0 (PowerShell) |
| "Firestore rules deployed" | Must show `firebase deploy` `Deploy complete!` output |
| "Indexes deployed" | Covered by same `firebase deploy --only firestore:rules,firestore:indexes` |
| "Hosting deployed" | Must show separate `firebase deploy --only hosting` `Deploy complete!` output |
| "Deps upgraded" | Must show `flutter pub get` lockfile versions |
| "Version bumped" | Must show both `pubspec.yaml` AND `app_brand.dart` matching values |
| "Commit pushed" | Must quote commit hash AND `git push` output with branch name |
| "APK installed" | Must quote `adb install` `Success` output |

An AI agent that provides claims without quoting actual tool output is in violation of AGENTS.md Rule 21 and the claim is invalid. Never accept "I ran the tests and they passed" — always demand the exact output.

## Admin Auth Pipeline

When an admin's ID token is rejected mid-session (INVALID_ID_TOKEN):

1. `auth.currentUser?.getIdToken(forceRefresh: true)` → if OK, continue
2. If step 1 fails → `auth.signInWithCustomToken(token)` from secondary FirebaseApp
3. If step 2 fails → `authNotifier.signOut()` + redirect to `/login`

Never silently swallow `INVALID_ID_TOKEN` — always force refresh or sign out.

## Pre-Release Verification

When a release is explicitly requested, verify synchronized versions,
analyzers, relevant tests, both requested build surfaces, authorized
deployments, Git delta, and requested device installation. Local-only work
must not be described as a release or production signoff.

## Security Baseline

- Deny-by-default rules remain enabled
- Admin-equivalent role behavior must be aligned in app and rules
- No Firebase Storage, no Cloud Functions — zero-cost Firebase tier (Firestore + Auth only)
- User creation via secondary FirebaseApp (no server-side admin SDK needed)

## Done In This Baseline

- v3.10.4+1115 corrects super-admin workspace support feedback and inherited
  RTL row ordering using explicit LTR `pw.Directionality`; Arabic and Urdu
  statement samples were visually inspected in Chrome. Urdu output remains
  Naskh-style: an isolated `payv` Nastaliq proof lacks logo, text-extraction,
  pagination, and all-report Web/Android parity. The full Flutter suite passed
  628 tests, Rules Emulator passed 147 tests, both analyzers and Markdown lint
  are clean, Web `EXIT: 0`, Hosting and Rules/indexes deployed, and split APKs
  built at 30.7/32.2/33.6 MB. No Android device was connected for installation.
- v3.10.3+1114 fixes incomplete legacy workspace roster and seat data.
  Active/inactive user lists sort client-side so documents without optional
  `display_name` remain visible; selected-workspace seat reconciliation counts
  the full tenant-scoped active roster. The query-only hotfix does not change
  Rules/indexes, which were deployed with v3.10.2. Full Flutter suite:
  `01:21 +623: All tests passed!`; `flutter analyze lib --no-pub`:
  `No issues found! (ran in 15.3s)`; `dart analyze test/`:
  `No issues found!`; Rules Emulator: `146 passing (37s)`. Web `EXIT: 0`;
  Hosting deploy: `Deploy complete!`; split APKs built (30.7/32.2/33.6 MB).
  ARM64 installed on `R5GL22RGT9V` (`Success`, versionCode `3103414`).
- v3.10.2+1113 corrects workspace role management, roster-based seat
  reconciliation, logo size handling, and cash-receipt presentation.
  Tenant admins can create admin/seller accounts and change roles only among
  eligible non-owner users in their tenant; peer administrator deactivation,
  owner-role changes, and platform-role assignment remain denied. Seat
  reconciliations are selected-workspace-only, paged, and revision-checked.
  Logos resize locally while preserving transparency and are not processed by
  an AI service. Cash-receipt PDFs are compact bilingual one-page tables with
  no balance-movement section; receipt/ledger/balance writes remain atomic.
  Full Flutter suite: `01:26 +623: All tests passed!`; changelog regression:
  `00:00 +10: All tests passed!`; `flutter analyze lib --no-pub`:
  `No issues found! (ran in 103.6s)`; `dart analyze test/`: `No issues found!`;
  Rules Emulator: `145 passing (31s)`. Web `EXIT: 0`; Hosting and
  Rules/indexes deploy: `Deploy complete!`. Split APKs built at 30.7/32.2/33.6
  MB; ARM64 installed on `R5GL22RGT9V` (`Success`, versionCode `3103313`).
- v3.10.1+1112 workspace and receipt improvements: tenant management shows
  owner contact/email verification, live role counts, and the free-tier cap
  of 10 active non-platform-super-admin members; profile transitions and seat
  counters are validated atomically. Cash receipt detail and PDFs provide a
  fuller payment/balance/recipient breakdown without changing ledger math.
  Google Drive OAuth was not configured for this release, so Drive backup is
  unavailable while encrypted phone archives remain supported. Full Flutter
  suite: `01:20 +623: All tests passed!`; `flutter analyze lib --no-pub`:
  `No issues found! (ran in 98.8s)`; `dart analyze test/`: `No issues found!`.
  Rules Emulator: `140 passing (31s)`. Web `EXIT: 0`; Hosting and
  Rules/indexes deployments reported `Deploy complete!`. Split APKs built
  (30.6/32.1/33.6 MB); ARM64 installed on `R5GL22RGT9V` (`Success`,
  versionCode `3103212`).
- v3.9.85+711 bilingual financial documents: workspace admins select
  English-Arabic (default) or English-Urdu; the preference is saved in the
  invoice-header configuration and copied into invoice snapshots. Invoice,
  receipt, statement, seller, multi-shop, and flat financial PDFs use paired
  labels with explicit RTL line direction in ledger summaries/tables. Seller
  invoice Rules validate provider-shaped optional header data and enforce the
  configured pair. Full suite: 609 passed; Rules Emulator: 133 passing; both
  analyzers clean. Release build, production deployment, install, commit, and
  push are pending.
- v3.9.84+710 backup hardening: tenant workspace settings are read
  by their tenant document ID, avoiding the Rules-incompatible settings list
  query; concrete archived collection keys are validated separately from
  selectable categories. Seller archives retain assigned-route scope and
  reject another seller's inventory records. Backup role tests:
  `00:07 +16: All tests passed!`; full Flutter suite:
  `01:15 +603: All tests passed!`; `flutter analyze lib --no-pub`:
  `No issues found! (ran in 83.9s)`; `dart analyze test/`:
  `No issues found!`; Rules Emulator: `132 passing (48s)`. Firestore
  Rules/indexes deployed. Split APKs built (30.4/32.0/33.4 MB); ARM64
  installed on `R5GL22RGT9V` (`Success`, versionCode `3101110`). Hosting and
  Git publication remain pending because pushing to `main` triggers Hosting.
- Unreleased 2026-10-24 operational refresh and financial presentation:
  workspace settings/header forms follow real-time snapshots until locally
  edited; pull refresh is available on shops, invoices, shop detail, and
  settings. Shop totals remain full precision and are grouped by currency;
  invoice Pending filters outstanding sale invoices. Invoice voids tag linked
  ledger originals and reversals in the same transaction. A tenant-scoped
  invoice-ID query also catches legacy settlement payments missing from older
  invoice documents; new settlements append their transaction IDs atomically.
  Credit-balance voids retain actual cash-in payments as customer credit,
  while cash-refund voids hide them. Customer statements omit voided rows;
  admin history retains them. Receipt PDFs emphasize received amounts and
  include payment/balance/signature details; statement summary labels follow
  Arabic/Urdu direction and workspace headers. Full Flutter suite:
  `01:08 +599: All tests passed!`; focused invoice-void suite:
  `00:00 +22: All tests passed!`; `flutter analyze lib --no-pub`:
  `No issues found! (ran in 7.1s)`; `dart analyze test/`: `No issues found!`.
  Cross-device authenticated acceptance, production deployment, and release
  operations remain unperformed.
- Unreleased 2026-10-24 reduced-motion hardening: all shared `AppAnimations`
  presets bypass nonessential effects when `MediaQuery.disableAnimations` is
  enabled. `PressableWidget` remains tappable and semantically actionable with
  press-scale feedback suppressed. Both custom router transitions now bypass
  fade/scale or slide effects under the same preference. Router regressions:
  `00:05 +6: All tests passed!`; full Flutter suite:
  `01:01 +589: All tests passed!`; both analyzers clean. No business or
  authorization behavior changed.
- Unreleased 2026-10-24 login responsive hardening: the narrow login content
  width is capped to the available viewport as well as its 420-pixel maximum,
  preventing invalid constraints at intermediate widths. Regression coverage
  spans six widths and EN/AR/UR; the full Flutter suite and both analyzers pass.
  A public local-browser render was checked; authenticated role/theme and
  device acceptance remain pending.
- Unreleased 2026-10-24 invoice-permission audit: missing invoice/transaction reads now require active tenant-scoped access; first-time seller-inventory reads are admin-equivalent only; super-admin missing-settings reads are limited to workspace creation before the tenant document exists. Seller invoice Rules reduce redundant route/shop authorization work to keep real invoice transactions within the expression budget. Admins see localized guidance when their own inventory is empty. Local Rules Emulator: 128 passing; focused invoice widget tests: 2 passing. Not deployed or released.
- Unreleased v3.9.82+708 source inventory UI work: stock add/transfer choices distinguish loading, empty, and mapped error/retry states; the inventory screen waits for workspace carton settings rather than defaulting to 12 pairs during settings failures. Provider write and stock-audit behavior are unchanged.
- Unreleased v3.9.82+708 source frontend work: route, shop, product, and variant edit forms gate inputs and save until the active profile and matching record load, with mapped retry/missing-record states and prefilled existing values. Provider tenant/role checks and write behavior are unchanged; no release build or deployment was performed.
- Unreleased 2026-10-23 frontend sweep: invoice totals are currency-grouped; currency-filtered shops wait for route scope; invoice-profile failure, profile dirty state, and notification mark-all progress/errors are explicit; unlinked activity rows hide misleading navigation affordances; stat-card entrance motion respects reduced motion. Report account statements now use their shop route currency; seller report rows and PDF totals preserve currency groups across routes. The 32-route register also dispositions report-export feedback, user route options, backup/flush workspace states, tenant-admin presentation, and shop-form route-query retry. Focused regressions and both analyzers pass; the full current suite and authenticated rendered acceptance remain pending. No release operation was performed.
- Unreleased local RTL export hardening: shared PDF generation now fails closed when Arabic shaping is not enabled; tests verify embedded Noto Sans Arabic, Urdu-specific characters, and XLSX RTL/Unicode content. PDFs remain Naskh-style for Urdu; full Nastaliq shaping is unsupported by the current renderer. No release build or deployment was performed.
- v3.9.81+707 (2026-10-22): Removed app-managed device pairing and custom session approvals while retaining Firebase Auth, tenant-scoped workspace-admin CRUD/sorting, selected-super-admin support context, and financial protections. Shop opening balances, standalone ledger-to-shop batch links, and inactive-tenant access are covered by local Rules Emulator regressions. Release and deployment evidence is recorded in SESSION_LOG.md.
- v3.9.80+706 (2026-10-18): Workspace admins can register unlimited paired devices while keeping a shared bounded active-session policy; tenant-scoped paired-device registry includes account email/name and device/app/OS metadata with 200-record read caps and duplicate suppression. Pairing-off pending seller registrations can activate. Workspace admins can audited-soft-delete standalone cash entries with an atomic balance reversal; hard transaction deletion and invoice-linked deletion are denied. Verification and APK artifact details are recorded after release checks.
- v3.9.79+705 (2026-10-17): Workspace creation provisions its tenant-scoped owner account; workspace administrators can disable sellers with atomic active-session revocation and manage registered device/session access. Device/session slots remain per user, and client session enforcement is not a Firestore authorization boundary. PWA icon cache keys match this release.
- v3.9.78+704 (2026-10-16): Workspace owner selection is tenant-scoped, workspace editing requires an active super-admin context, save errors retain accurate mappings, Android/web launcher artwork uses a consistent scale, and shop invoice actions have improved spacing.
- v3.9.77+703 (2026-10-16): non-stock invoices default to disabled unless explicitly enabled per workspace; sale and credit-note numbering, invoice, ledger, balance, and stock writes are atomic and retry-safe; receipts and returns require reciprocal ledger/shop links; credit-note voids reverse original credit totals and stock. Multiline shop transaction descriptions and inventory audit rows are included. Rules Emulator: 122 passing; Flutter suite: 561 passing; Flutter/Dart analyzers and Markdown lint clean. Web/APK builds, authorized deployment, and phone install are pending.
- v3.9.76+702 (2026-10-16): seller-only pairing approval, workspace-admin pending-slot resume within platform caps, guarded platform-session reactivation, renewal checks that distinguish live records from revoked history, atomic logout revocation, pending-renewal termination, typed access errors, and missing-policy defaults. Validation: 113 Rules Emulator tests and 562 Flutter tests passed; both analyzers clean. Rules/indexes deployed. APKs built (30.5/32.1/33.6 MB); ARM64 installed on R5GL22RGT9V (`Success`, versionCode 3100302). No authenticated sign-in smoke test or Hosting deployment.
- v3.9.75+102: Fixed the post-registration timestamp sentinel cast behind super-admin sign-in failure; tenant sessions now validate the actual paired device slot, registration grace and queued checks protect login races, automatic sign-out is UID-scoped, and renewal cannot reactivate revoked sessions. Workspace-admin limits are shared/platform-configured, seller limits remain workspace-configurable, and platform sessions are separate. Invoice voids are atomic and balanced; receipt sequence Rules are enforced; invoice PDFs localize receipts and paginate. Android versionCode was raised above the connected device's installed package code for a data-preserving update.
- v3.9.61+100: Stock, tenant-enabled non-stock, and cash-receipt invoice modes; workspace-owned bilingual invoice headers snapshotted into PDFs; atomic per-workspace receipt numbering and balance writes; receipt rules and non-stock void inventory guard.
- v3.9.60+99: Login waits for registration and preserves errors; credential-only lockout, member policy/missing-slot reads, scoped registry queries, real pending device approval, atomic remove/block/reset, 30-day stale recovery, clock-skew feedback, foreground renewal/warning, and separate super-admin sessions. Session records are client-enforced only under the Spark architecture; they are not a Firestore authorization boundary.
- v3.9.59+98: Tenant/seller sign-in uses tenant/user-scoped access-record queries and links sessions to registered device slots; registration failures preserve their localized cause. Workspace management handles transient null profiles and visible write/owner-list errors; login system-bar contrast follows theme. Firestore rules were not changed.
- v3.9.58+97: Backup file export and Google Drive use distinct destinations; Drive backups do not create a duplicate local archive, restore copy reflects merge/replacement scope, local archives can be deleted, and workspace archival revokes member device/session access.
- v3.9.54+93: Status-chip labels and semantics are localized for EN/AR/UR; high-contrast semantic state colors meet 4.5:1 contrast against black.
- v3.7.5+53 (audit v16): Post-audit hardening sweep completed — route/shop form identity guards tightened; auth and network stream providers moved to `autoDispose`; transaction export queries capped at 2000 docs; remaining inventory dialog disposal fixed; shimmer placeholders switched to theme-derived surfaces; offline indicator now uses semantic error color; manual APK, CI, and release workflows aligned on Flutter 3.41.6 with expanded test reporting; Firebase Hosting immutable cache now includes `.wasm`; regression tests expanded for model `copyWith`, equality, settings assertions, and transaction ledger edge cases
- v3.7.0+48 (audit v14): Dep stack fully upgraded: fl_chart 1.2.0, share_plus 13.0.0 (migrated SharePlus.instance.share(ShareParams(...))), permission_handler 12.0.1, dart_jsonwebtoken 3.4.0, flutter_lints 6.0.0; 30 lint issues fixed (unnecessary_underscores, use_null_aware_elements, prefer_const_constructors, share_plus deprecations); all 4 CI workflows standardized on Flutter 3.41.6; governance hardened (Rules 19–22, Anti-Bypass Enforcement Matrix, Chain 6, Gates 12–15); README.md × 2 fully rewritten; markdown governance skill + instruction + CI gate 15 added; 90 markdown issues fixed to zero; temp artifacts purged; audit score 79/100 → 88/100
- v3.5.0+43 (audit v13): Governance layer (REGRESSION_REGISTRY.md, SESSION_LOG.md, MASTER_BLUEPRINT.md, CHANGELOG.md, AUDIT_REPORT_FOOTWEAR_ERP.md), CI/CD hardened (Flutter 3.29.2 pinned, timeouts, --coverage, 11 hygiene gates, APK size gate), 15 hardcoded Colors.* eliminated in 6 screens (RR-011), widget_test.dart placeholder replaced (RR-013), Firestore rules emulator test scaffold
- Firebase Storage fully removed — zero cost architecture
- Cloud Functions dependency removed — user CRUD via secondary FirebaseApp (no server needed)
- Role normalization in app user parsing and writes
- Firestore rules tolerate legacy role casing variants
- Dashboard provider now uses timeout + cached fallback
- Route/shop/variant/inventory forms map errors with AppErrorMapper
- SnackBar system redesigned: Material 3 container-color card-style across all 19 screens
- Added all-user profile route (/profile) for name/theme/language/security controls
- Kept settings admin-only and added screen-level admin guard
- User lifecycle: create via secondary FirebaseApp, soft-delete, password reset via email
- Edit user dialog: email read-only, password reset button (no direct password setting)
- Added admin-only delete actions for routes/shops/customers with provider guards
- Full invoicing system (sale invoices, credit notes, void/paid lifecycle)
- Stock transfer history with inventory_transactions provider
- Bad debt tracking with customer write-off flow
- L10n: 372+ keys × 3 languages with full parity
- Enterprise audit: all provider write guards, admin-only product creation, color consistency
- Seller self-update rules: display_name, updated_at, last_active (session heartbeat)
- Multi-device tested: Samsung A56 (Android 16/API 36), V2247 (Android 14/API 34) — zero errors
- Enterprise v3.0.0 upgrade (22 sections, 6 phases):
  - Design system: app_tokens, app_animations, app_sanitizer, input_formatters
  - 14 widgets (6 upgraded + 8 new), all with accessibility tooltips
  - 5 list screens with search/filter/shimmer/pull-to-refresh/listEntry animations
  - 7 forms standardized with PopScope/dirty-check/sanitizer/haptic
  - 5 detail screens enriched with charts/badges/grouping
  - Reports: monthly cash flow BarChart, outstanding PieChart
  - PDF export: Isolate.run() for all 4 functions, sanitized string interpolation (S-08)
  - Session guard: AppLifecycleListener, 8h admin hard session limit (S-10)
  - Base64 logo: 256×256 + flutter_image_compress + ≤50KB cap (S-07)
  - Firestore rules: docSizeOk() <50KB, withinWriteRate() 1s cooldown
  - Dark mode QA: theme-aware colors, no hardcoded Colors.white/grey
  - RTL QA: EdgeInsetsDirectional, no hardcoded left/right padding
  - Release: v3.0.0+7, 3 ABI-split APKs built
