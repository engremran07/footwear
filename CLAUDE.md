# ShoesERP AI Coding Rules (CLAUDE.md)

Last updated: 2026-03-27

## Runtime Override (Always First)

The live codebase is a route/seller distribution ERP.

- Roles: admin, seller (manager must be admin-equivalent)
- Collections: users, products, product_variants, routes, shops, customers, transactions, settings
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

## Done In This Baseline

- Role normalization in app user parsing and writes
- Firestore rules tolerate legacy role casing variants
- Dashboard provider now uses timeout + cached fallback
- Route/shop/variant/inventory forms map errors with AppErrorMapper
