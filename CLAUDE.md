# ShoesERP AI Coding Rules (CLAUDE.md)

Last updated: 2026-04-07

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

## Financial Pathways (never mix these)

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

## Vibe-Coded Debt Signals

| Pattern seen | What it signals | Correct pattern |
|-------------|----------------|----------------|
| `db.collection('transactions')` | Raw collection string | `db.collection(Collections.transactions)` |
| `if (user.isSeller && ...)` on stock source | Admin silently excluded | `sellerInventoryProvider(user.id)` for all |
| `.where('deleted', isEqualTo: false)` | Pre-DI-01 docs excluded | Client-side `d.data()['deleted'] != true` |
| `ref.read(provider)` in `build()` | Stale data guarantee | `ref.watch(provider)` |
| `flutter build apk --release --split-per-abi` | Wrong split APK | `flutter build apk --release` (fat) |
| Hardcoded `Colors.red`, `Colors.white` | Dark mode breakage | `AppBrand.errorFg`, `AppBrand.errorBg` |
| Raw `SnackBar(content: Text(...))` | Unstyled SnackBar | `errorSnackBar()` / `successSnackBar()` |

## Five Non-Negotiable Pre-Commit Checks

```bash
# 1 — Zero analyze issues
flutter analyze lib --no-pub

# 2 — All tests green
flutter test -r expanded

# 3 — No raw collection strings
grep -rn "\.collection('" app/lib/ | grep -v "Collections\."

# 4 — No Firestore writes in screens/widgets
grep -rn "FirebaseFirestore\|\.collection(" app/lib/screens/ app/lib/widgets/

# 5 — No split-per-abi anywhere
grep -rn "split-per-abi" .github/ app/ --include="*.{yml,yaml,md,sh}"
```

## Admin Auth Pipeline

When an admin's ID token is rejected mid-session (INVALID_ID_TOKEN):
1. `auth.currentUser?.getIdToken(forceRefresh: true)` → if OK, continue
2. If step 1 fails → `auth.signInWithCustomToken(token)` from secondary FirebaseApp
3. If step 2 fails → `authNotifier.signOut()` + redirect to `/login`

Never silently swallow `INVALID_ID_TOKEN` — always force refresh or sign out.

## Pre-Signoff Verification

Run before marking production ready:

- flutter analyze lib --no-pub
- flutter test -r expanded
- flutter build apk --release
- If web is part of the request: flutter build web --release and deploy hosting from the same versioned source tree
- Verify current About/version/contact content on both APK and web if those surfaces were part of the release request
- Verify admin and seller startup for `/` and `/inventory`; transient permission-denied UI during stream warm-up is a regression.
- firebase deploy --only firestore:rules,firestore:indexes

## Security Baseline

- Deny-by-default rules remain enabled
- Admin-equivalent role behavior must be aligned in app and rules
- No Firebase Storage, no Cloud Functions — zero-cost Firebase tier (Firestore + Auth only)
- User creation via secondary FirebaseApp (no server-side admin SDK needed)

## Done In This Baseline

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
  - Release: v3.0.0+7, 3 split-per-abi APKs built
