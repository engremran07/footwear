# ShoesERP AI Coding Rules (CLAUDE.md)

Last updated: 2026-03-29

## Runtime Override (Always First)

The live codebase is a route/seller distribution ERP.

- Roles: admin, seller (manager must be admin-equivalent)
- Collections: users, products, product_variants, seller_inventory, inventory_transactions, routes, shops, customers, transactions, invoices, settings
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
6. Any where+orderBy query requires index entry when fields differ.
7. Keep role handling canonical and normalized (trim/lowercase in app writes).
8. Keep admin-only write enforcement in submit methods (screen-level defense in depth).
9. Validate required identity fields (for example created_by/route_id/shop_id) before provider writes.
10. No Firebase Storage — company logos stored as base64 in Firestore, product images use external HTTP URLs. Do not add firebase_storage dependency.

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

## Pre-Signoff Verification

Run before marking production ready:

- flutter analyze lib --no-pub
- flutter test -r expanded
- flutter build apk --release
- firebase deploy --only firestore:rules,firestore:indexes

## Security Baseline

- Deny-by-default rules remain enabled
- Admin-equivalent role behavior must be aligned in app and rules
- No Firebase Storage — zero-cost Firebase tier (Firestore + Auth + Functions only)

## Done In This Baseline

- Firebase Storage fully removed — zero cost architecture
- Role normalization in app user parsing and writes
- Firestore rules tolerate legacy role casing variants
- Dashboard provider now uses timeout + cached fallback
- Route/shop/variant/inventory forms map errors with AppErrorMapper
- Added all-user profile route (/profile) for name/theme/language/security controls
- Kept settings admin-only and added screen-level admin guard
- Hardened user lifecycle: admin-only create/delete via Cloud Function, seller must have assigned route
- Added admin-only delete actions for routes/shops/customers with provider guards
- Full invoicing system (sale invoices, credit notes, void/paid lifecycle)
- Stock transfer history with inventory_transactions provider
- Bad debt tracking with customer write-off flow
- L10n: 372 keys × 3 languages with full parity
- Enterprise audit: all provider write guards, admin-only product creation, color consistency
- Seller self-update rules: display_name, updated_at, last_active (session heartbeat)
- Multi-device tested: Samsung A56 (Android 16/API 36), V2247 (Android 14/API 34) — zero errors
