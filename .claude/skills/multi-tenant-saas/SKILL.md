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
- Starting support access must atomically link the profile's
  `active_workspace_access_log_id` to the exact append-only
  `workspace_access_started` event. Rules must check both the post-batch
  profile from the event and the post-batch event from the profile update;
  a profile-only context update or an unrelated existing event is insufficient.
- Clearing or switching an active support context must atomically create a
  `workspace_access_ended` event and link its exact ID from the updated profile
  through `last_workspace_access_end_log_id`. Validate the event against the
  pre-update actor, workspace, reason, and prior start-event ID when present.
  A switch must also link the new start event in that same batch; never clear
  the old context first and append an end event later.
- `RoleCapabilities` and `PermissionPolicy` centralize app decisions.
  Firestore Rules must independently enforce identity, tenant, role, route,
  lifecycle, and financial invariants.
- The notification feed is a tenant-owned operational capability, not a
  globally shared inbox. AppShell badge, route, screen, provider query,
  referenced-shop visibility, mark-read writes, and Firestore Rules must use
  the same capability and concrete active workspace. Admin-equivalent roles
  and supervisors are authorized; sellers and platform super-admins are
  excluded, even when a super-admin has selected a support workspace.
- Key feed and shop-visibility providers by tenant ID so an account/workspace
  switch cannot reuse the previous tenant's cache. Profile errors must remain
  errors with retry feedback, not be normalized to a missing user or a
  success-shaped empty feed. Keep initial loading distinct from cached refresh.
- Workspace feature settings such as `allow_non_stock_invoices` live in the
  concrete tenant's `settings/{tenantId}` document. UI controls must use the
  settings notifier, preserve partial-update semantics, and have a regression
  for saving, leaving/reopening, and handling permission-denied writes. A
  setting toggle cannot commit unrelated dirty form fields.
- A UI capability toggle is not authorization. Any dynamically configurable
  policy must have a versioned, validated fail-closed data contract that the
  Rules enforce for the same tenant and operation. Do not add a client-only
  permission registry or widen a role through workspace settings.

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
   super-admin missing/expired support context. For support-access starts,
   deny profile-only updates, log-only writes, mismatched event IDs, actors,
   workspaces, reasons, and timestamps; also deny context clearing/switching
   without its linked end event or with a mismatched prior start ID. Allow
   only the complete linked batch.
5. Include at least 15 distinct workspace IDs in a tenant-isolation regression
   to catch fixed-tenant assumptions. This does not substitute for quota
   measurement, load testing, or production monitoring.
6. Run focused Flutter tests, the complete Rules Emulator suite, relevant
   analyzers, and Markdown lint. Quote exact output; distinguish local
   validation from production deployment.
7. Never deploy Rules, modify production data, publish, commit, or push without
   explicit user authorization.

For notification permission regressions, add a role-and-tenant test matrix
including admin, legacy manager, tenant admin, and supervisor access, seller
and platform-super-admin denial, and cross-tenant denials. Use multiple
concrete workspace IDs (at least 15 for a tenant-isolation scale check); this
does not replace quota measurement, load testing, or production monitoring.

## Destructive Workspace Operations

The current database flush/reset surfaces intentionally fail closed. Do not
enable or replace them with a multi-batch client deletion loop. A future
feature-specific reset requires a product-approved module scope, tenant-bound
server-side enforcement, dependency-aware preview, explicit confirmation,
idempotent progress/retry semantics, partial-failure reporting, immutable
audit history, and isolated non-production emulator coverage. Financial,
inventory, identity, workspace-root, and platform-audit data need separate
retention/recovery decisions.

## SaaS Readiness Claims

Do not describe the product as enterprise-ready or leak-proof based only on
role-matrix tests. Record and disposition data migration, backup/restore
consistency, Rules read-call cost, free-tier quotas, indexes, operational
monitoring, tenant lifecycle, and recovery risks separately. A 15-tenant
boundary test proves only the tested authorization paths for those fixtures.

Legacy tenant-backfill commands that assign every missing record to a single
default or selected tenant are not safe for multi-workspace data and must fail
closed. A replacement migration needs a per-record ownership map, dry-run
report, explicit environment allowlist, reviewed recovery plan, and isolated
emulator/staging verification before production authorization.
