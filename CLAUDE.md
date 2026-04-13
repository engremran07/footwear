# ShoesERP AI Coding Rules (CLAUDE.md)

Last updated: 2026-04-13

## Runtime Override (Always First)

The live codebase is a route/seller distribution ERP.

- Roles: admin, seller (manager must be admin-equivalent)
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
    primary, with optional extra pairs (0–11). Always fat APK: flutter build apk --release.
16. Admin has no assigned_route_id — admin is the warehouse AND a field seller.
    Admin can own seller_inventory docs (seller_id = adminUid). isAdmin() in Firestore
    rules covers all admin operations including self-stock-allocation.
17. If a bug was addressed by multiple candidate fixes, and QA/user confirms the
    real culprit, you MUST run the Band-Aid Loop Reversal protocol: keep root-cause
    and mandatory guards, rollback non-culprit mitigations, and record final reasoning.

## Financial Pathways (never mix these)

```text
Pathway 1: SALE WITH STOCK
  → CreateSaleInvoiceScreen → InvoiceNotifier.createSaleInvoice()
  → Invoice + cash_out tx + optional cash_in tx + seller_inventory deduction
     (all in one atomic batch)
  → USE WHEN: new goods delivered to shop, stock deduction required

Pathway 2: CASH COLLECTION (old debt, no new goods)
  → ShopDetailScreen → TransactionNotifier.create(type: 'cash_in')
  → Cash_in ledger entry ONLY. No invoice. No stock movement.
  → USE WHEN: collecting outstanding balance, no new delivery

VOID / RETURN:
  → InvoiceNotifier.voidInvoice() — admin only
  → Returns stock to inventory (seller_inventory or warehouse)
  → Two refund modes: cashRefund (cheque/cash paid back) or creditBalance (deduct from balance)
  → Issues ONE reversal transaction (return tx). Cash refund adds a second cash_out tx.

NEVER create an invoice for cash-only collection.
NEVER create a standalone transaction for a new stock sale (always through invoice).
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

**Dev data flush:** If you delete transactions/invoices manually (e.g. in dev),
always follow with `node dev_reset.js` from the repo root to reset:

- All shop `balance` fields → `0.0`
- `settings/global.last_invoice_number` → `0`

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
| ABI-split APK build command | Wrong split APK | `flutter build apk --release` (fat) |
| Hardcoded `Colors.red`, `Colors.white` | Dark mode breakage | `AppBrand.errorFg`, `AppBrand.errorBg` |
| Raw `SnackBar(content: Text(...))` | Unstyled SnackBar | `errorSnackBar()` / `successSnackBar()` |
| `avoid_double_and_int_checks lint violation` in web build | Transitive dep locked to old `image`/`archive` by another pkg | Find blocking package; replace or upgrade it — see Chain 5 |
| `flutter build web --release` exits 1 with no Error lines | PowerShell `NativeCommandError` from Wasm dry-run stderr — build IS succeeding | Check `$LASTEXITCODE` explicitly; exit 0 = real success |
| `StateProvider<T>` in any `.dart` file | Riverpod 3 removed `StateProvider` — instant compile failure on upgrade | Replace with `NotifierProvider<T, S>` + `Notifier` subclass — see Chain 6 |

## Twelve Non-Negotiable Pre-Signoff Steps

**All 12 steps are mandatory for every session that touches code. No bypass.**

```bash
# 1 — Zero analyze issues
flutter analyze lib --no-pub
# Must end: No issues found! (ran in Xs)

# 2 — Zero test dir issues
dart analyze test/
# Must end: No issues found!

# 3 — All tests green
flutter test -r expanded
# Must quote: All N tests passed!

# 4 — No raw collection strings
grep -rn "\.collection\('" app/lib/ | grep -v "Collections\."
# Must return zero lines

# 5 — No Firestore writes in screens/widgets
grep -rn "FirebaseFirestore\|\.collection(" app/lib/screens/ app/lib/widgets/
# Must return zero lines

# 6 — No StateProvider (banned Riverpod 3)
grep -rn "StateProvider\b" app/lib/ --include="*.dart"
# Must return zero lines

# 7 — Version sync
grep -E "^version:|appVersion|buildNumber" app/pubspec.yaml app/lib/core/constants/app_brand.dart
# pubspec version X.Y.Z+N must match app_brand appVersion=X.Y.Z + buildNumber=N

# 8 — Zero markdown lint issues (Problems tab must be empty)
markdownlint "**/*.md" --ignore node_modules --ignore app/build
# Must exit 0 with zero output

# 9 — Firestore rules + indexes deployed (always, not just on change)
firebase deploy --only firestore:rules,firestore:indexes
# Must quote: Deploy complete!

# 10 — Web release build (PowerShell — check $LASTEXITCODE, not pipe output)
$ErrorActionPreference='Continue'; cd app; flutter build web --release; Write-Host "EXIT: $LASTEXITCODE"
# Must state EXIT: 0

# 11 — Firebase Hosting deployed
firebase deploy --only hosting
# Must quote: Deploy complete!

# 12 — APK build + GitHub commit audit + commit + push
flutter build apk --release
git log --oneline -5
git status --short  # confirm no unexpected artifacts
git add -A && git commit -m "type: summary — vX.Y.Z+N"
git push
# Must quote commit hash and push output
```

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

## Pre-Signoff Verification

See **Twelve Non-Negotiable Pre-Signoff Steps** above — all 12 steps are
mandatory. Key checks in brief:

- flutter analyze lib --no-pub
- flutter test -r expanded
- flutter build apk --release
- firebase deploy --only firestore:rules,firestore:indexes → Deploy complete!
- flutter build web --release → EXIT: 0
- firebase deploy --only hosting → Deploy complete!
- git log --oneline -5 + git status --short → no unexpected artifacts
- git add -A + git commit + git push → quote commit hash + push output
- If device connected: adb install -r → Success
- Verify admin and seller startup for `/` and `/inventory`; transient permission-denied UI during stream warm-up is a regression.

## Security Baseline

- Deny-by-default rules remain enabled
- Admin-equivalent role behavior must be aligned in app and rules
- No Firebase Storage, no Cloud Functions — zero-cost Firebase tier (Firestore + Auth only)
- User creation via secondary FirebaseApp (no server-side admin SDK needed)

## Done In This Baseline

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
