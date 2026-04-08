---
mode: agent
description: 20-gate quality gate runner for ShoesERP. Run this after implementing any change to verify all quality standards are met before committing. Blocks on any failure.
---

# ShoesERP 20-Gate Post-Implementation Checklist

Run all 20 gates in order. A single failure BLOCKS the release. Fix root cause before proceeding.

## Gate 1 — Static Analysis
```bash
cd app && flutter analyze lib --no-pub
```
Expected: "No issues found!"

## Gate 2 — Full Test Suite
```bash
cd app && flutter test -r expanded
```
Expected: All tests pass (minimum 335). No deletions allowed; fix failing tests before proceeding.

## Gate 3 — Firestore Rules Deployed
```bash
firebase deploy --only firestore:rules
```
Verify rules include `docSizeOk()` and `withinWriteRate()` on all creates/updates.

## Gate 4 — Firestore Indexes Deployed
```bash
firebase deploy --only firestore:indexes
```
Verify every `where(A)+orderBy(B)` (A ≠ B) query has a composite index.

## Gate 5 — Version Consistency
Check that `app/pubspec.yaml` version and `app/lib/core/constants/app_brand.dart` version/buildNumber are identical.
```bash
grep "^version:" app/pubspec.yaml
grep "appVersion\|buildNumber" app/lib/core/constants/app_brand.dart
```

## Gate 6 — L10n Key Parity
All EN keys must exist in AR and UR. Run the hygiene gate from ci.yml Gate 5.
Zero missing keys acceptable.

## Gate 7 — No Dead Providers
Every provider defined in `app/lib/providers/` must have at least one consumer (ref.watch or ref.read) outside of its own file. Search for zero-consumer providers.

## Gate 8 — No Raw Firestore Collection Literals
```bash
grep -rn "\.collection('" app/lib/ | grep -v Collections\.
```
Expected: zero matches. All collection references use `Collections.*` constants.

## Gate 9 — Fat APK in All Documentation
```bash
grep "split-per-abi" README.md app/README.md AGENTS.md CLAUDE.md
```
Expected: zero matches in build command context. Only historical-note mentions acceptable.

## Gate 10 — Provider Write Guards
All provider methods that write `created_by`, `route_id`, `shop_id`, `seller_id` must validate non-empty before `batch.commit()`. Search for `.commit()` calls without preceding empty-check of identity fields.

## Gate 11 — allTransactionsProvider Invalidation
```bash
grep "allTransactionsProvider" app/lib/providers/auth_provider.dart
```
Expected: present in `_invalidateRoleScopedProviders()`.

## Gate 12 — Admin-Only Screen Defense-in-Depth
All admin-only screens (settings, user management, reports admin view) must enforce admin check in the submit/write method, not just at the router guard. Search for `isAdmin` check in:
- `app/lib/screens/settings_screen.dart` submit methods
- `app/lib/screens/users_list_screen.dart` write methods

## Gate 13 — Financial Pathway Routes Correct
Verify:
- `createSaleInvoice()` is ONLY called from invoice creation screens (not from cash-collection flows)
- `TransactionNotifier.create(type: 'cash_in')` is ONLY called from shop detail cash collection (not from invoice creation)
- No standalone transaction for a new stock sale

## Gate 14 — Seller Route Constraints
All seller-facing shop/transaction creation must include `route_id` validation. Sellers cannot create shops or transactions outside their `assigned_route_id`. Check that all seller shop create calls pass `route_id`.

## Gate 15 — SA Credentials Provisioned
Check `admin_config/sa_credentials` Firestore doc exists (manual confirmation or note in PR).
If `AdminIdentityService` features are in scope, verify `clearCache()` is called on sign-out.

## Gate 16 — PDF Generation in Isolate
```bash
grep -rn "Isolate.run\|compute(" app/lib/ | grep -i "pdf"
```
All 4 PDF export functions (invoice, route, inventory, report) must use `Isolate.run()`.

## Gate 17 — Session Guard Active
Verify `SessionGuard` wraps the root widget in `app/lib/app.dart`. Admin hard limit is 8h, warning at 7h30m.

## Gate 18 — Firestore Rules docSizeOk + withinWriteRate
```bash
grep -c "docSizeOk()\|withinWriteRate()" firestore.rules
```
Expected: ≥2 occurrences of each.

## Gate 19 — withinWriteRate Rule Present
```bash
grep "withinWriteRate" firestore.rules
```
Expected: present in all high-frequency write paths (seller_inventory, products, product_variants).

## Gate 20 — Release Surface Sync
- `app/pubspec.yaml` version == `app/lib/core/constants/app_brand.dart` version ✓ (Gate 5)
- APK built from same source as web ✓
- Both deployed before commit ✓
- git tag v{version} created after successful deploy ✓

---

## Pass Criteria
All 20 gates green → proceed to commit. Any gate failure → fix root cause, re-run failed gate.

## Blocking Patterns (never commit with these)
- `flutter analyze` errors
- Test failures
- Missing allTransactionsProvider in _invalidateRoleScopedProviders
- Version mismatch between pubspec.yaml and app_brand.dart
- L10n key missing from any language
