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
