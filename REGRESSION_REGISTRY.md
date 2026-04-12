# ShoesERP Regression Registry

**Maintained by:** Autonomous AI agent system (88-agent governance pack v2.0)  
**Last updated:** 2026-04-11 — Audit v13 / v3.5.0+43  
**Purpose:** Single source of truth for known regressions, deferred risks, and process improvements.

---

## Regression Registry (RR) — Active Entries

| ID | Severity | Component | Summary | Status | Since |
|----|----------|-----------|---------|--------|-------|
| RR-001 | P0-DEFERRED | `admin_identity_service.dart` | RSA private key stored in Flutter client heap (L35,L65). OAuth2 cloud-platform scope. Requires Blaze tier + Cloud Functions for secure signing. | Documented, no Spark-tier fix | v3.0.0 |
| RR-002 | P0-DEFERRED | Financial arithmetic | `double` floating-point used for monetary values. ±0.01 rounding gap in Firestore vs UI tolerated via epsilon equality check in `invoice_provider`. | Documented, deferred | v1.0.0 |
| RR-003 | P1-DEFERRED | `session_guard.dart:L377` | Admin lock overlay is tap-to-dismiss without biometric/password re-authentication. Full re-auth requires `local_auth` sprint. | Documented, deferred | v3.0.0 |
| RR-004 | P1-DEFERRED | Shop analytics / transaction list | Hard pagination caps: 150 transactions in live ledger, 500 shops in analytics listener. Full cursor-based pagination is a separate sprint. | Documented, deferred | v3.4.11 |
| RR-005 | P1-FIXED | Dashboard | Transient `permission-denied` shown during auth warm-up on `/` and `/inventory`. | Fixed v3.2.6 — role-scoped providers stay in loading state until auth settles | v3.0.0 |
| RR-006 | P1-FIXED | `product_provider.transferToSeller` | Transfer audit log written to `transactions` (wrong) instead of `inventory_transactions`. Type was `transfer_out` in code but `unknown` in Firestore. | Fixed v3.3.0 — correct collection + type | v2.0.0 |
| RR-007 | P1-FIXED | `excel` package (Wasm dep lock) | `excel 4.0.6` locked `archive ^3.x`, blocking `image` from upgrading past 4.3.0 (Wasm violation). `flutter build web --release` broke silently on CI. | Fixed v3.4.5 — replaced excel with custom xlsx writer using `archive ^4.0.0` | v3.4.0 |
| RR-008 | P2-FIXED | Seller data leak | After admin logout, seller session inherited admin-only providers (allInvoicesProvider, adminAllSellerInventoryProvider) from stale Riverpod cache. | Fixed v3.4.0 — providers added to `_invalidateRoleScopedProviders()` | v3.2.0 |
| RR-009 | P2-FIXED | Role casing drift | App wrote `'Admin'` (uppercase), rules checked `'admin'` (lowercase) → all admin writes failed silently on new installs. | Fixed v3.0.0 — `isAdminRole()` regex + `role.trim().toLowerCase()` on write | v1.0.0 |
| RR-010 | P2-FIXED | ABI-split APK in CI | Release workflow used `--split-per-abi` producing 3 split APKs; canonical requirement is fat APK only. | Fixed v3.3.0 — `flutter build apk --release` (fat) mandated throughout | v2.0.0 |
| RR-011 | P2-FIXED | Hardcoded `Colors.*` in 6 screens | `Colors.white`, `Colors.grey`, `Colors.red`, `Colors.black54` used in production screens — dark mode breakage risk. | Fixed v3.5.0 — replaced with AppBrand/cs constants throughout | v3.0.0 |
| RR-012 | P2-FIXED | CI Flutter version drift | `ci.yml` and `release.yml` used Flutter `3.22.x` while `build-apk.yml` and `deploy-web.yml` used `3.29.x`. Three-way divergence. | Fixed v3.5.0 — all 4 workflows pinned to `3.29.2` | v3.0.0 |
| RR-013 | P3-FIXED | Widget test placeholder | `app/test/widget_test.dart` contained a marketing `MaterialApp` smoke test with no real screen coverage. | Fixed v3.5.0 — replaced with auth flow smoke test + GoRouter guard | v1.0.0 |
| RR-014 | P3-FIXED | CI missing coverage + timeouts | Test job had no `--coverage` flag; all 3 CI jobs had no `timeout-minutes`; hanging builds possible. | Fixed v3.5.0 — coverage enabled, 20/30/10 minute timeouts added | v3.0.0 |
| RR-015 | P1-FIXED | Firestore rules: seller transaction over-permission | When approval toggle OFF, sellers could update `amount` and `type` on own transactions — allows fraudulent amount manipulation and cash_in/cash_out type flip. `updateTransactionNote()` provider was already restricted; rules were behind. | Fixed v3.5.0.1 — removed `amount`, `type`, `sale_type`, `created_at` from allowed field set; seller approval-disabled path now restricted to `description`, `updated_at`, `updated_by`, `edit_request_*` only. | v3.0.0 |

---

## Process Improvement (PI) Backlog

| ID | Category | Description | Priority |
|----|----------|-------------|----------|
| PI-001 | Security | Migrate SA key signing to Cloud Functions on Blaze upgrade. Eliminates RR-001. | P0 on tier upgrade |
| PI-002 | Financial | Replace `double` monetary arithmetic with integer-pence representation. Eliminates RR-002. Requires migration script for all Firestore `balance`,`amount` fields. | P0 on next accounting sprint |
| PI-003 | UX/Security | Implement `local_auth` biometric/PIN re-authentication for admin lock screen overlay. Eliminates RR-003. | P1 on next auth sprint |
| PI-004 | Performance | Replace hard pagination caps with cursor-based pagination (`startAfterDocument`). Required for routes >500 shops or sellers >150 transactions. Eliminates RR-004. | P1 on scale sprint |
| PI-005 | Testing | Add Firebase Rules Emulator tests (`tests/firestore-rules/`) for permission matrix. Track seller write boundaries + admin-only paths. | P2 — ongoing |
| PI-006 | Observability | Integrate Crashlytics custom keys for `user_id`, `role`, `app_version` to correlate crashes with user context. | P2 |

---

## Band-Aid Loop Closure Record

| Bug | Temp fixes applied | Root cause | Non-culprit rollbacks | Closed |
|-----|--------------------|------------|----------------------|--------|
| Wasm build failure (v3.4.5) | (1) `dependency_overrides` for archive, (2) replaced excel | Custom xlsx writer + archive ^4.0.0 was root cause | `dependency_overrides` removed before release | Yes — v3.4.5 |
| Dashboard permission-denied (v3.2.6) | (1) try/catch swallow, (2) typed fallback cache, (3) provider loading guard | Loading guard in role-scoped providers was root cause | try/catch swallow removed | Yes — v3.2.6 |

---

*Registry format: RR-NNN = Regression entry. PI-NNN = Process improvement backlog item.*
