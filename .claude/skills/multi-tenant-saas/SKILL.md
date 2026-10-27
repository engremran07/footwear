---
name: multi-tenant-saas
description: "Use when: auditing or changing ShoesERP multi-tenant authorization, workspace isolation, role parity, tenant onboarding, or SaaS readiness."
---

# ShoesERP Multi-Tenant SaaS Readiness

## Purpose

Use this workflow for tenant-bound business behavior that must remain
consistent as the number of workspaces grows. Application policy improves
consistency but is never a substitute for Firestore Rules.

## Sources of Truth

- `app/lib/models/user_model.dart`: canonical role parsing and tenant profile.
- `app/lib/core/utils/role_names.dart`: centralized capability grants.
- `app/lib/core/utils/permission_policy.dart`: active tenant and support-context checks.
- `app/lib/core/utils/tenant_scope.dart`: concrete-tenant validation and write scope.
- `app/lib/core/router/app_router.dart`: route authorization.
- Provider notifiers: authoritative client write guards and atomic writes.
- `firestore.rules`: independent authorization boundary.
- `tests/firestore-rules/rules.test.js`: positive and adversarial Rules contract.

## Tenant and Role Invariants

- Every ordinary business operation requires an authenticated actor, active
  profile, concrete active tenant, and same-tenant target documents.
- Never use a missing tenant or `__global__` as a new-write fallback.
- Sellers remain constrained to assigned routes and authenticated seller IDs.
- Supervisors receive tenant-scoped operational capabilities only; they do
  not inherit user administration, settings, backup, financial correction,
  invoice settlement, credit-note, or void rights.
- Legacy `manager` remains admin-equivalent in the supported code and Rules
  paths; platform super-admin remains workspace-scoped for business data.
- Super-admin business access requires a selected workspace, support reason,
  append-only access event, and valid context TTL. Platform metadata access
  does not imply access to tenant business records.
- `RoleCapabilities` and `PermissionPolicy` centralize app decisions.
  Firestore Rules must independently enforce identity, tenant, role, route,
  lifecycle, and financial invariants.

## Invoice Operation Matrix

Keep these permissions separate and verify each in the router, UI, provider,
and Rules:

| Operation | Admin / tenant admin | Supervisor | Seller |
| --- | --- | --- | --- |
| Create sale invoice | Tenant-scoped | Tenant-scoped | Assigned route and own identity |
| Create cash receipt | Tenant-scoped | Tenant-scoped | Assigned route and own identity |
| Settle invoice | Admin-equivalent only | Denied | Denied |
| Create credit note | Admin-equivalent only | Denied | Denied |
| Correct financial row | Admin-equivalent with audit reason | Denied | Denied |
| Void invoice | Admin-equivalent only | Denied | Denied |

Invoice creation does not authorize edits or lifecycle transitions. A permitted
invoice batch must keep its invoice, counter, linked transactions, shop balance,
and any stock deductions atomic and tenant-linked.

## Verification Protocol

1. Trace the full UI-to-provider-to-Firestore call path for each operation.
2. Verify visible controls and route guards against the shared app capability
   policy; keep provider-side role, actor, route, and tenant guards.
3. Replay complete Firestore transaction/batch writes in the Emulator,
   including reads that occur inside the transaction.
4. Cover each allowed role, seller wrong-route and wrong-identity attacks,
   inactive tenants, unassigned tenants, cross-tenant document access, and
   super-admin missing/expired support context.
5. Include at least 15 distinct workspace IDs in a tenant-isolation regression
   to catch fixed-tenant assumptions. This does not substitute for quota
   measurement, load testing, or production monitoring.
6. Run focused Flutter tests, the complete Rules Emulator suite, relevant
   analyzers, and Markdown lint. Quote exact output; distinguish local
   validation from production deployment.
7. Never deploy Rules, modify production data, publish, commit, or push without
   explicit user authorization.

## SaaS Readiness Claims

Do not describe the product as enterprise-ready or leak-proof based only on
role-matrix tests. Record and disposition data migration, backup/restore
consistency, Rules read-call cost, free-tier quotas, indexes, operational
monitoring, tenant lifecycle, and recovery risks separately. A 15-tenant
boundary test proves only the tested authorization paths for those fixtures.
