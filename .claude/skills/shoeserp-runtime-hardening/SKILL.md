---
name: shoeserp-runtime-hardening
description: "Use when: fixing permission-denied, resource-exhausted, route/inventory write failures, role/rules mismatches, Firestore index gaps, or aligning AGENTS/CLAUDE/README docs to live runtime architecture."
---

# ShoesERP Runtime Hardening Skill

## Purpose

Prevent regressions caused by architecture drift between code, rules, and agent instructions.

## Mandatory Checks

1. Role alignment

- Verify app role helpers in app/lib/models/user_model.dart

- Verify Firestore role helpers in firestore.rules

- Verify create/update user flows normalize role values before writing

1. Collection alignment

- Use only names from app/lib/core/constants/collections.dart

1. Query/index alignment

- For every where(A)+orderBy(B) where A != B, ensure index exists in firestore.indexes.json

1. Dashboard resilience

- Avoid all-or-nothing aggregate pipelines

- Catch FirebaseException/timeout on each aggregate query and degrade gracefully

- Maintain last-good dashboard cache fallback

- Never surface transient permission-denied / unauthenticated errors to users
  during auth/profile stream warm-up; keep startup in loading or cached state

1. Post-edit access verification

- After edits touching auth, router, dashboard, inventory, or Firestore rules,
  verify admin and seller flows for `/`, `/inventory`, and login startup

- Guard admin-only list/stream providers with `authUserProvider` before
  subscribing so seller credentials never trigger denied reads in the UI

- Prefer loading, empty, or cached fallback states over raw permission text
  while role-scoped providers settle

1. Release-surface sync

- If the user asks for web deploy + APK build/install in the same task, treat
  them as one release candidate and verify both are built from the same current
  version in `app/pubspec.yaml` and `app/lib/core/constants/app_brand.dart`

- If user-visible content still appears old on web after deploy, inspect
  `firebase.json` cache headers and Flutter web shell caching before assuming
  code changes were missed

- Do not mark web and APK as aligned until build, deploy, install, and git push
  all reflect the same release candidate

1. Error messaging

- Map Firebase exceptions through AppErrorMapper

- Use styled SnackBar helpers from `snack_helper.dart`:
  - `errorSnackBar(msg)` — light pink bg + dark red text + red accent bar
  - `successSnackBar(msg)` — light green bg + dark green text + green accent bar
  - `warningSnackBar(msg)` — light amber bg + dark orange text + amber accent bar
  - `infoSnackBar(msg)` — light blue bg + dark blue text + blue accent bar

- NEVER use raw `SnackBar(content: Text(...))` or hardcoded `Colors.red`

- For screens using `AppMessage` (requires WidgetRef): same card-style is applied automatically

- Container color constants live in `AppBrand` (errorBg/errorFg/errorAccent etc.)

1. Defense in depth on admin writes

- Admin-only screens must enforce admin checks inside submit/write methods.

- Do not rely only on router guards for sensitive writes.

1. Security-relevant write field validation

- Provider methods writing created_by/route_id/shop_id must reject empty values.

- Validate identifiers before creating/committing Firestore batched writes.

1. **shop.balance single pipeline — stale-UI failure prevention**

- `shop.balance` is the ONLY field that represents a shop's financial position.

- It MUST only be written by `InvoiceNotifier` or `TransactionNotifier` methods
  inside an atomic Firestore batch that also writes the transaction/invoice doc.

- All monetary displays (Total In/Out, route outstanding, dashboard AR) derive
  from this single field or from the live `shopTransactionsProvider` stream.

- **Maintenance boundary:** Never delete transaction/invoice rows or rewrite
  shop balances with client flush/reset tools or direct scripts. Those paths
  fail closed because multi-batch cleanup cannot preserve ledger links
  atomically. Use only a reviewed, tenant-scoped transactional maintenance
  procedure; archive/restore is the supported workspace lifecycle.

- **Inline audit trigger:** Any time you touch `transaction_provider.dart`,
  `invoice_provider.dart`, or `shop_provider.dart`, verify every write to
  `transactions` or `invoices` also updates `shop.balance` atomically. If any
  path skips the balance update, that is a critical data-integrity bug.

## Firebase Auth Recovery

Firebase Auth owns credential and token refresh. Do not invent a
`signInWithCustomToken` recovery path or reuse the account-creation
secondary-app flow to mint credentials; client code has no trusted custom-token
issuer.

- Preserve the signed-in state for transient network, timeout, and token-refresh
  failures. Surface a retryable state without clearing Firebase Auth persistence.
- For a confirmed disabled/deleted account or an explicitly invalid credential,
  follow the current auth provider's mapped recovery path and scope any
  sign-out to the UID that was checked.
- Before changing auth recovery, trace the actual Firebase exception and
  `auth_provider.dart`; do not convert every refresh failure into sign-out.

### insufficient_request_scope

- Cause: GCP service account missing `cloud-platform` OAuth scope.

- Fix: Re-generate service account key with `--scopes=https://www.googleapis.com/auth/cloud-platform` or use Application Default Credentials in CI.

### Service Account Credentials Not Provisioned

- Cause: `GOOGLE_APPLICATION_CREDENTIALS` env var missing in CI runner.

- Fix: Add `FIREBASE_SERVICE_ACCOUNT` secret to GitHub Actions; load via `google-github-actions/auth@v2`.

## Standard Failure Playbooks

### Notification feed refresh and permission feedback

- Trace the notification stream, unread badge, shop-visibility stream, screen
  rendering, and read-state writes together; do not diagnose flicker from the
  visible shimmer alone.
- Keep the shop-visibility subscription keyed by a sorted, deduplicated set of
  referenced shop IDs. Read-state-only notification snapshots must not restart
  those shop subscriptions.
- In Riverpod 3, `AsyncValue.whenData()` does not preserve stale data when the
  source enters loading during a refresh. If the UI must remain stable, retain
  the last successful visibility result explicitly; keep initial load and real
  errors distinguishable.
- Do not subscribe admin-only notification feeds until the profile, active
  tenant, role, and any required super-admin support context are confirmed.
  Firestore Rules remain authoritative; the client guard only avoids known
  unauthorized subscriptions.
- Never discard mark-as-read failures with `.ignore()`. Map and show failures,
  then add a regression for the exact screen action and role/context.
- Test stable shop-ID keys, cached visibility during refresh, first-load
  loading, real stream errors, and successful/denied read-state writes. Run the
  focused Rules Emulator cases whenever notification authorization tests
  change.

### permission-denied on writes

- Confirm user doc role and active status

- Confirm app role interpretation

- Confirm rules role interpretation

- If mismatch exists (manager/casing/legacy), align app writes and rules checks

### resource-exhausted on dashboard

- Identify expensive aggregate queries

- Avoid failing all metrics when one query errors

- Use cached fallback values and per-query timeout

- Consider materialized KPI doc for very high scale

### data not visible on lists

- Validate composite index coverage

- Validate collection names against constants

- Validate provider query matches deployed indexes

### Multi-workspace permission parity

- Treat `RoleCapabilities` and `PermissionPolicy` as the app-side source of
  capability decisions, but keep Firestore Rules as the independent security
  boundary. Reconcile each business operation across role model, router,
  screen affordance, provider guard, and Rules.
- Separate invoice creation from settlement, credit-note, correction, and
  void permissions. Admins, tenant admins, supervisors, and sellers may create
  sale invoices and cash receipts in their permitted scope; seller writes
  remain assigned-route scoped. Never infer correction rights from create
  access.
- Require a concrete active tenant and active profile on every business path.
  For super-admins, require the selected workspace, valid support reason,
  append-only access event, and unexpired support context.
- Add positive and negative emulator coverage for each role and cross-tenant
  access. Include a multi-workspace fixture with at least 15 distinct tenant
  IDs to detect hard-coded workspace assumptions; do not treat that test alone
  as proof of production quota or latency capacity.

## MCP/Copilot Modernization Deploy Startup Checks

If "MCP server GitHub Copilot modernization Deploy was unable to start":

- Validate extension/tooling installation state in VS Code

- Reload window and re-open workspace

- Verify no malformed agent/skill YAML frontmatter in workspace docs

- Confirm AGENTS.md and CLAUDE.md are valid markdown and not referencing unsupported tools

- If startup still fails, capture extension logs and isolate by disabling unrelated custom agents

## Required Documentation Updates

When runtime behavior changes, update in same change set:

- AGENTS.md

- CLAUDE.md

- README.md

- app/README.md

- SYSTEM_DEEP_DIVE_2026-03-27.md

## Example Remediation Patterns

1. Admin submit guard

- In screen _save(), read authUserProvider and abort with permission_denied snackbar if not admin.

1. Provider identity guard

- In notifier create/update methods, trim and validate created_by/route_id/shop_id; throw ArgumentError if empty.

## Multi-Tenant Permission Review

Use `RoleCapabilities` and `PermissionPolicy` for app-side role capabilities,
tenant matching, target-role eligibility, and super-admin support-context
checks. Do not duplicate role-to-route maps in screens, router guards, and
navigation. Firestore Rules remain authoritative and must independently
enforce the same business scope; the Dart matrix is not a Rules generator.

Verify the actual contract for each operation rather than relying on a generic
`isAdmin` check:

- Legacy `admin`/`manager` manages eligible seller profiles only.
- `tenant_admin` manages eligible seller and supervisor profiles in its own
  tenant, subject to owner, peer-admin, seat, and role safeguards.
- `supervisor` has tenant operational routes, shops, products, inventory,
  invoices, reports, and notifications, but not settings, backups, user
  administration, reassignment, financial corrections, credit notes, or
  invoice voids.
- `seller` stays route-scoped and does not receive administrative notification
  or report access.
- `super_admin` may access business data only with a selected tenant, a reason
  of at least 10 characters, a recorded support event, and unexpired context.
  The client must leave business routes when that context expires; Rules enforce
  the TTL regardless of client state.

New business writes must pass through `TenantScope.requireTenant()` and reject
both missing tenants and the legacy `__global__` sentinel. Preserve legacy
read handling only where a specific query or migration requires it. Never
broaden a Rules clause to make a client query succeed without proving its
tenant and role constraints.

When a workspace becomes inactive, keep ordinary business reads and writes
denied. Verify the narrowly scoped platform restoration path separately; do
not reactivate member profiles or allow a generic admin branch to bypass the
workspace lifecycle state.

Classify changes before editing Rules: UI presentation, internal state
refactor, query/index, schema migration, identity/membership, authorization
policy, or trusted writer. UI-only and refactor changes do not justify a Rules
rewrite. A `permission-denied` result requires tracing identity, profile
activity, tenant lifecycle, exact query/write set, and Rules conditions before
any policy change.
