# ShoesERP Deep Dive Audit (2026-03-27)

## Executive Summary

A full runtime audit and hardening pass was applied for recurring failures:

- permission-denied on route creation and inventory stock updates
- resource-exhausted on dashboard
- architecture drift between code and markdown/agent guidance

All high-priority runtime blockers requested in this pass are now implemented.

## Root Causes Confirmed

1. Role/value drift

- Legacy manager values and inconsistent role casing can cause backend denials.

1. Rules and app interpretation drift risk

- App and backend were close, but needed stronger normalization/tolerance.

1. Dashboard aggregate fragility

- Aggregate endpoints can fail under quota pressure and previously returned hard-zero fallbacks.

1. Agent/document drift

- Legacy references were still present in core docs, causing autonomous fix misalignment.

## Code Changes Implemented

1. app/lib/models/user_model.dart

- Role parsing now normalizes trim+lowercase before mapping.

1. app/lib/providers/user_provider.dart

- createUser/updateUser now normalize role strings before Firestore writes.

1. firestore.rules

- Added role helper checks tolerant to legacy role casing variants.

1. app/lib/providers/dashboard_provider.dart

- Added timeout per aggregate query.
- Added last-known-good cache provider fallback for each metric.
- Enabled keepAlive to reduce repeated expensive fetch churn.

1. app/lib/screens/route_form_screen.dart
2. app/lib/screens/shop_form_screen.dart
3. app/lib/screens/variant_form_screen.dart
4. app/lib/screens/inventory_screen.dart

- Write-path exception handling now maps through AppErrorMapper.

1. app/lib/screens/product_detail_screen.dart

- Variant stock label uses cartons/dozens/pairs formatting.

1. app/lib/screens/product_form_screen.dart
2. app/lib/screens/variant_form_screen.dart

- Added submit-time admin checks to enforce admin-only writes as defense in depth.

1. app/lib/providers/transaction_provider.dart

- Added required identifier validation (createdBy/shopId/routeId must be non-empty)
  before committing batch writes.

## Analyzer Verification

- Command: flutter analyze lib --no-pub
- Result: No issues found

## Revalidation (Post-Audit Hardening Increment)

- Targeted remediation added for permission-audit findings:
  - admin submit-time write guard for product/variant forms
  - security-relevant identifier validation in transaction provider
- Follow-up verification performed in same pass:
  - flutter analyze lib --no-pub
  - flutter test -r expanded
  - flutter build apk --release

## Documentation And Agent Alignment Changes

Updated and runtime-aligned:

- AGENTS.md
- CLAUDE.md
- README.md
- app/README.md
- .claude/CLAUDE.md
- .claude/skills/shoeserp-runtime-hardening/SKILL.md

## Pending Tasks Summary (Post-Implementation)

Completed in this hardening cycle:

- [x] Route/inventory permission hardening
- [x] Dashboard quota resilience hardening
- [x] Error mapping hardening on critical write screens
- [x] Variant stock display format hardening
- [x] Agent/doc runtime alignment hardening

Remaining operational tasks (environment/deploy):

- [ ] Deploy rules/indexes changes:
  - firebase deploy --only firestore:rules,firestore:indexes
- [ ] Rebuild production APK after deployment verification
- [ ] Validate with real manager/admin/seller test users in production project

## Recommended Production Validation Script

1. Sign in as admin-equivalent user (admin or legacy manager)
2. Create route, assign seller
3. Add inventory stock in cartons/dozens/pairs
4. Refresh dashboard repeatedly (10x) and verify no full-page failure
5. Sign in as seller and verify denied writes to routes/products/variants/settings

## Risk Register

1. Data quality risk

- Existing user docs with unexpected role strings outside admin/manager/seller still require cleanup.

1. Quota planning risk

- Cache fallback improves resilience, but very high traffic may still need materialized KPI documents.

1. Deployment drift risk

- If rules are changed but not deployed, runtime behavior will not match source code.

## 2026-03-29 Stabilization Addendum

Implemented in this pass:

1. Seller-to-admin session switch resilience

- Added provider invalidation on sign-in/sign-out to clear stale permission-denied stream state.

1. User lifecycle hardening

- Moved user creation to secondary FirebaseApp approach (no Cloud Functions needed).
- User deletion via soft-delete (set active=false, clear route assignments).
- Password reset via Firebase Auth reset email (admin cannot directly set passwords).
- Edit user dialog: email read-only, password reset button, role + route assignment.
- Enforced seller route assignment requirement on create/update across UI, provider, and rules.
- Prevented implicit auto-creation of route-less seller profiles during sign-in.

1. Access model refinement

- Added `/profile` route for all users (name, language, theme, security).
- Retained `/settings` as admin-only and added in-screen admin guard.

1. Admin-only destructive actions

- Added route/shop/customer delete actions in detail screens for admin only.
- Added provider-level admin guards for route/shop/customer delete methods.
- Added seller-only user deletion in admin user management; admin users are protected.

1. Report output consistency

- Account Statement and Seller Report now route through shared export sheet for unified PDF/XLSX/PNG/Print entry points.

1. Session and inventory stabilization (full-audit follow-up)

- Fixed `InventoryScreen` null-user transition crash during auth switching (seller/admin swaps).
- Centralized auth-session invalidation expanded to include family providers (route/shop/customer/product/transaction/seller inventory).
- Hardened Firestore role checks with regex to tolerate role whitespace/case drift (`admin|manager|seller`).
- Disabled Firestore disk persistence in app runtime to reduce stale cross-account cached state.
- SnackBar system redesigned: Material 3 container-color card-style (light bg + dark text + accent bar).
- All SnackBars across 19 screens converted to styled helpers (errorSnackBar/successSnackBar/warningSnackBar/infoSnackBar).
- cloud_functions dependency removed from pubspec.yaml and error_mapper.dart.

1. Multi-device compatibility pass (Samsung A56, Android 16 API 36)

- Added `last_active` to allowed seller self-update fields in Firestore rules (was causing PERMISSION_DENIED for session_guard heartbeat writes).
- Added composite index for `seller_inventory: active + variant_name` (admin all-inventory query without seller_id filter).
- Overflow hardening: stat_card, dashboard, reports, settings, inventory, customer_detail, shops_list, product_detail, route_detail, customers_list screens.
- targetSdk updated 34→35.
- Verified on Samsung Galaxy A56 (Android 16/API 36) and V2247 (Android 14/API 34): zero errors in logcat, zero overflows, zero crashes.
