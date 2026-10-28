---
name: notification-center
description: "Use when: auditing tenant-scoped notification permissions, Rules mark-read integrity, feed flicker, unread badge refresh, shop-visibility subscriptions, or notification error feedback in ShoesERP."
---

# Skill: ShoesERP Notification Center

## Scope

Use for notification streams, unread counts, visibility filtering, notification
screen states, and mark-as-read writes. Keep notification reads scoped to the
active tenant and authorized role. Admin-equivalent roles and supervisors may
read and mark the tenant's admin notification feed. Sellers and platform
super-admins remain excluded, including super-admins with selected workspace
support context.

## Trace Before Changing

Follow the complete lifecycle:

```text
Auth/profile/tenant context
  → role-scoped notification provider
  → bounded notification query
  → referenced shop-ID visibility provider
  → notification screen and unread badge
  → provider notifier for read-state writes
  → Firestore Rules authorization
```

Inspect the screen, providers, notification/shop models, error mapper, rules,
and focused provider/widget/emulator tests. Separate actual authorization
failures from startup/loading states and from refresh flicker.

Read route redirects and `RoleGuard` behavior as part of this trace. A
profile-stream failure must not be interpreted as a missing profile,
redirected to bootstrap, or rendered as a permanent shimmer before the screen
can show its mapped error and retry action.

## Stability and Authorization

- Build the referenced shop-ID key from a sorted, deduplicated set. A
  read-state-only notification update must not recreate shop listeners.
- Riverpod 3 `AsyncValue.whenData()` can return loading when the source is
  refreshing, even when the previous value exists. If existing visible rows
  should remain on screen during that refresh, retain the last successful
  visibility result explicitly. Keep the initial load as loading and surface
  real errors as errors.
- Guard subscriptions until the active profile, active tenant, role, and
  selected/unexpired super-admin support context (when required) are confirmed.
  Never use UI visibility as a security boundary; Firestore Rules authorize
  every read and write.
- No-context and unsupported-role states must not query a placeholder or
  global tenant. Show actionable localized guidance.
- Key both feed and referenced-shop stream providers by the normalized
  concrete tenant ID. A singleton stream can retain its previous tenant's
  value during a workspace switch; do not rely on UI filtering to prevent that
  cross-tenant cache leak. `__global__` is not a notification query scope.
- Read-state mutations belong in the notification notifier. Validate the same
  role/tenant/support context before committing.
- Do not suppress write failures with `.ignore()` or success-shaped fallbacks.
  Map Firebase exceptions and show visible feedback so stale deployed Rules,
  inactive tenants, and mismatched documents can be diagnosed.
- Keep the auth/profile state machine explicit at the screen boundary:
  profile loading may show loading UI; a profile-stream error must show mapped
  retry feedback; a missing profile must show actionable access guidance; an
  unsupported role or tenant context must not start feed or shop listeners.
- The screen repeats capability and tenant checks even when the router also
  gates the route. If a route guard hides the screen on provider errors, give
  the route a safe error path; the screen must still avoid business queries
  until authorization is confirmed.

## Required Regression Coverage

- Stable sorted shop-ID key across notification read-state changes.
- Cached visible notifications remain visible during shop-visibility refresh.
- First visibility load remains loading; true visibility errors stay errors.
- Admin-equivalent tenant reads/writes succeed only in their scope.
- Supervisor reads/writes succeed only in their tenant; cross-tenant access is
  denied.
- Seller or missing-context access is denied without starting an unauthorized
  feed query.
- Profile-stream failures reach the screen as mapped errors with retry; they do
  not become an endless shimmer or route to profile bootstrap.
- Mark-as-read and mark-all failures display mapped feedback and retain
  retryable screen state.
- Role-matrix coverage includes legacy admin/manager, tenant admin, and
  supervisor access, plus seller and platform-super-admin denial across
  multiple concrete tenants.
- Run focused Flutter provider/widget tests and the Rules Emulator cases for
  changed authorization behavior. Quote exact test output and distinguish
  local emulator validation from production deployment.

## Known Riverpod Failure Mode

`AsyncValue.whenData(transform)` is not a stale-while-revalidate operator.
When the upstream stream transitions to loading, the transformed value may
also become loading and replace the entire list with shimmer. Preserve stale
data only where the UX requires it; do not hide first-load or genuine error
states, and do not solve flicker by broadening Firestore permissions.

## Confirmed Regression Patterns

- Check both loading boundaries: notification query refresh and referenced-shop
  visibility refresh. Preserving shop visibility alone does not prevent the
  screen from replacing cached rows when the upstream notification stream is
  loading with a previous value.
- A role can be operational without being account-admin. Keep the notification
  capability explicit in the user model, route guard, shell entry point,
  provider scope, and tenant-scoped Rules.
- Do not treat a displayed permission message as proof that Rules are correct
  or deployed. Identify whether the failed operation was the feed query, shop
  visibility query, mark-one update, or mark-all batch. Validate the exact
  request against the local emulator, then separately confirm authorized
  production deployment status.
- Never discard mark-read failures. Report the mapped error and retain normal
  navigation/retry behavior; an ignored write failure hides stale Rules and
  context mismatches.
- An auth/profile stream error is not equivalent to a null profile. Do not
  drive screen state from `AsyncValue.value` alone: inspect error and loading
  state before interpreting a null data value.
- Riverpod refresh/reload states may be loading while retaining the last
  profile in `AsyncValue.value`. Do not replace an authorized notification
  screen with shimmer solely because `isLoading` is true. Reuse that cached
  profile only while its user ID still matches the settled Firebase Auth UID;
  clear notification scope during auth loading/errors or on UID mismatch so a
  different account cannot inherit the prior tenant feed.
- Commit `6e5a433` made notification scope null while the profile stream was
  loading or errored, which tears down the tenant-keyed listeners during a
  same-user refresh. The UID-bound cached-profile guard prevents that listener
  churn during profile refresh without carrying scope across auth transitions.
- A generic “permission denied” message does not identify which Firestore
  operation failed. Trace profile loading, the notification feed query,
  referenced-shop queries, mark-one writes, and mark-all batches separately.
  Do not broaden Rules or treat the refresh fix as resolution of a remaining
  permission error until the denied operation and its tenant/profile state are
  evidenced.
- Seller invoice/transaction notifications are post-commit, best-effort writes.
  Do not couple them atomically to financial writes or silently depend on a
  per-user cooldown: a rejected notification must not invalidate an already
  committed ledger operation. Use a deterministic source-scoped notification
  ID and Rules that compare the notification against the persisted,
  same-tenant source. Test rapid valid notifications and detached or
  mismatched payloads. This source-link contract is separate from feed
  read/visibility authorization and does not prove production Rules are
  deployed.

## Read-State Integrity Contract

Marking a notification read is a one-way, tenant-scoped operation:

- Allow an authorized reader to transition an unread notification to
  `read: true`; do not allow resetting it to `false`.
- Update `read` and `read_at` together. The client must use a server timestamp,
  and Rules must reject a client-chosen or malformed timestamp.
- Apply the same per-document invariant to mark-one and mark-all batches.
  Batch writes must not broaden role or tenant scope.
- Deny notification access for missing, inactive, or sentinel tenant contexts;
  notifications are not a `__global__` inbox.
- Preserve the existing valid mark-read path for tenant admins, admin-equivalent
  roles, and supervisors. Sellers, platform super-admins, unassigned users,
  cross-tenant actors, and inactive tenants remain denied.

Add positive and adversarial Rules Emulator regressions for a valid mark-one
and mark-all, resetting `read`, changing only one field, malformed or
client-selected `read_at`, unassigned/global scope, inactive profiles or
tenants, and cross-tenant document IDs. Reproduce the failing assertion before
editing Rules, run the complete local emulator suite after the change, and
report deployment separately; a local pass does not prove production Rules
are deployed.
