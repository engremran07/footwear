---
name: notification-center
description: "Use when: fixing notification feed flicker, unread badge refresh, shop-visibility subscriptions, role-scoped notification queries, or mark-as-read permission feedback in ShoesERP."
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
