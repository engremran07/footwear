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
  - shops
  - customers
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
- /customers
- /customers/new
- /customers/:id
- /customers/:id/edit
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
flutter build apk --release
```

## 8) Autonomous Agent Checklist

Before writing code:

- Read AGENTS.md and CLAUDE.md
- Validate role/rules/collection alignment

Before finishing:

- Run flutter analyze lib --no-pub
- Run flutter test -r expanded
- Update deep-dive and READMEs if runtime assumptions changed
- If rules changed, deploy firestore:rules and firestore:indexes

## 9) Runtime Document Hierarchy

Conflict resolution order for instructions:

1. AGENTS.md (runtime contract)
2. CLAUDE.md (coding rules)
3. .claude/CLAUDE.md (local mirror/override helper)
4. Skill files under .claude/skills/

## 10) Current Audit Status

2026-03-30 enterprise audit:

- Firebase Storage fully removed — zero cost architecture (Firestore + Auth only, NO Cloud Functions)
- Cloud Functions dependency removed — user CRUD uses secondary FirebaseApp approach
- Company logo stored as base64 in Firestore settings doc (no CDN/Storage needed)
- Product image_url field supports external HTTP URLs only (no upload to Storage)
- Role normalization hardened in app + rules + storage.rules (regex matching)
- Dashboard aggregate fallback cache enabled
- Critical write screens map errors through AppErrorMapper
- SnackBar system redesigned: Material 3 container-color card-style (light bg + dark text + accent bar)
- All SnackBars across 19 screens converted to styled helpers (errorSnackBar/successSnackBar/warningSnackBar/infoSnackBar)
- Variant stock shown as cartons/dozens/pairs in product detail
- L10n: 372 keys × 3 languages — perfect parity
- All 21 provider queries covered by 17 composite indexes + 1 new seller_inventory(active+variant_name)
- Provider write guards: created_by validation, admin-only product/variant creation
- Color consistency: all semantic colors use AppBrand constants
- Seller self-update rules: display_name, updated_at, last_active (session heartbeat)
- Edit user dialog: email read-only, password reset via email (no direct password setting)
- Multi-device tested: Samsung A56 (Android 16/API 36), V2247 (Android 14/API 34)
