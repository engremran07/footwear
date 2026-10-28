# ShoesERP Canonical Data Model

**Audit date:** 2026-10-27
**Repository baseline:** `6e5a4337f506d0713fe0463fb6f0ec0cef259b04`
**Status:** Source-derived model map; live production schema has not been read.

## Authority and ownership

- `Collections` in `app/lib/core/constants/collections.dart` is the app-side
  collection-name authority. It defines 15 names for 14 unique paths.
- `Collections.shops` and `Collections.customers` both resolve to the legacy
  Firestore path `customers`; the app entity is `ShopModel`, not a separate
  customer entity.
- `firestore.rules` is the server authorization boundary. Business records
  require an active profile, concrete tenant ownership, active tenant status,
  operation-specific role checks, and selected-workspace support context for
  platform super-admin business access.
- Tenant/business queries and writes must use the authenticated profile's
  concrete `tenant_id`. `global` and `__global__` are not valid fallbacks for
  new business writes.

## Canonical collection map

| Firestore path | App model / purpose | Tenant and key relationships |
|---|---|---|
| `tenants` | Workspace lifecycle and metadata | Document ID is the workspace ID; active state gates business access. |
| `users` | Firebase Auth-linked user profiles | Document ID is Auth UID; tenant-scoped roles and route assignment live on the profile. |
| `routes` | Sales routes | Tenant-owned; assigned seller identity and route/shop relationships are validated by providers and Rules. |
| `customers` | `ShopModel` (shops) | Tenant-owned; references route; balance is the financial source of truth. |
| `products` | Product catalog | Tenant-owned catalog entries. |
| `product_variants` | Product variants | Tenant-owned and linked to product. |
| `seller_inventory` | Seller allocation by seller/variant | Tenant-owned; sale deductions must match the invoice batch's exact deduction map. |
| `inventory_transactions` | Stock movement audit records | Tenant-owned; stock changes and audit events are atomic. |
| `transactions` | Shop ledger entries | Tenant-owned; linked to shop and optionally invoice; standalone balance changes are same-batch with the shop update. |
| `invoices` | Sale, receipt, credit-note, and lifecycle documents | Tenant-owned; references shop/customer, linked ledger rows, counter/sequence, and any stock deductions. |
| `settings` | Workspace settings and invoice-header configuration | Workspace scoped by the authorized tenant document path; platform configuration is separately protected. |
| `notifications` | Tenant notification feed | Tenant-owned; visible-shop subscriptions and mark-read writes are role/context scoped. |
| `audit_logs` | Application audit records | Collection exists in the canonical constants; each writer/schema requires a separate complete field audit. |
| `platform_access_logs` | Super-admin support-context audit | Append-only start/end events linked atomically to the profile transition. |

## Critical field and relationship invariants

- `users/{uid}`: Firebase UID, canonical role, active state, concrete tenant
  where applicable, route assignment for route-scoped users, and selected
  support-context fields for super-admin. A start event ID is stored in
  `active_workspace_access_log_id`; an end-event ID is retained in
  `last_workspace_access_end_log_id`.
- `shops` / Firestore `customers`: tenant and route ownership are required.
  Creation starts with `balance == 0` and no fabricated last-transaction
  cache. Only `InvoiceNotifier` and `TransactionNotifier` paths may mutate
  balance through atomic writes.
- `transactions`: must reference its tenant and shop. Invoice-linked rows are
  corrected only through authorized invoice lifecycle flows. Standalone
  cash-in/cash-out rows link to an exact same-batch shop-balance delta.
- `invoices`: sale/receipt/credit-note operations retain their distinct
  authorization. Invoice counters, linked transactions, aggregate shop-balance
  changes, and stock deductions are validated as one atomic batch.
- `seller_inventory`: a decrement must be the exact same-batch amount in the
  matching sale invoice's `seller_inventory_deductions`.
- `inventory_transactions`: warehouse transfers, adjustments, and returns
  append a tenant-scoped audit row atomically with the stock mutation.
- `platform_access_logs`: start events match the new profile context. End
  events match the prior context and the updated profile end-event pointer;
  workspace switches end the old context and start the new one atomically.

## Indexes and authorization

- Local `firestore.indexes.json` contains 26 composite indexes and 0 field
  overrides as of this inspection. This is a local declaration only; deployed
  index parity was not checked.
- Every `where(A) + orderBy(B)` query with different fields requires the
  corresponding composite index.
- Rules tests are in `tests/firestore-rules/rules.test.js` and run through
  `tests/firestore-rules/package.json`.
- App role capabilities are centralized in
  `app/lib/core/utils/role_names.dart` and
  `app/lib/core/utils/permission_policy.dart`; these do not replace Rules.
- `RoleCapabilities.matrix` is currently a compile-time map, not a
  super-admin-configurable policy document. No runtime permission schema is
  present in the canonical model.
- The database flush screen has disabled actions and its provider fails closed
  with `UnsupportedError`. A feature reset is not a supported data operation
  until its atomicity, authorization, recovery, and audit design is approved.

## Verification limits

This map records collection paths and critical relationships verified in the
current source. It is not a full field-by-field schema or migration inventory:
all model serializers, query converters, deployed documents, and historical
client versions were not exhaustively reconciled. The current supported model
definitions are in `app/lib/models/`; the Rules and indexes remain the
authoritative security and query-support sources. No production data was read
or changed.
