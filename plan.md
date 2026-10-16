# Authentication, Session, and Device-Pairing Remediation Plan

**Plan date:** 2026-10-16
**Scope baseline:** `2266b53` (`authentications sessions login logout issuese`)
**Inputs:** `MASTER_AUTH_SESSION_DEVICE_PAIRING_AUDIT_2026-10-15.txt`, the attached static recheck, and its proposed patch.
**Plan status:** Core fixes validated; Firestore rules deployed; release APK built and installed on the connected phone. Authenticated sign-in smoke test and remaining product decisions are open.

## Objective

Stabilize tenant and platform sign-in, renewal, revocation, and device administration without weakening seller pairing, tenant boundaries, support-access auditing, or Firestore authorization. Determine which reported paths explain real user incidents using runtime evidence; static source review alone does not establish a production incident's specific cause.

## Evidence And Current Assessment

The checkout is clean at `2266b53`, which matches the baseline named by the static recheck. The attached patch is not applied. The older master audit names commit `25fd9d5` as its source, so its findings must not be treated as a description of this checkout without revalidation.

Initial assessments were static. The implementation was subsequently validated with 113 Firestore Rules Emulator tests, 562 Flutter tests, `flutter analyze lib --no-pub`, and `dart analyze test/`. Firestore rules/indexes were deployed. Version `3.9.76+702` was built; the ARM64 artifact installed on `R5GL22RGT9V` and the device reports versionCode `3100302`. No authenticated sign-in smoke test, Hosting deployment, or production business-flow verification was performed. The recheck's reported `node --check`, Dart grammar parse, and `git apply --check` remain claims from that attachment, not independently reproduced here.

### Recheck Findings

| Finding | Current-source assessment | Evidence and disposition |
|---|---|---|
| RC-001: super-admin same-slot login after sign-out | Fixed and emulator-validated | The reactivation allowlist permits dropping `revoked_at` and `terminated_by` only in the owner super-admin reactivation branch. Same-slot revoke/reactivate passes in the full 113-test Rules suite. |
| RC-002: workspace admins caught by seller pairing | Fixed and unit/Rules-validated | Workspace admins bypass seller pairing, matching pending admin slots resume in place within the current platform cap, and sellers remain subject to approval. Policy and Rules regression cases pass; device verification remains pending. |
| RC-003: revoked history vetoes a live renewal | Fixed in provider/policy; unit-validated | Renewal rejection now considers an eligible live record for the same installation. The policy tests cover live-plus-revoked and revoked-only cases; a provider integration/device-history reproduction remains pending. |
| RC-004: logout terminates an arbitrary session | Fixed in source; suite-validated | Current-installation logout selects active matching sessions and revokes all in one batch. Full tests pass; a multi-slot runtime reproduction remains pending. |
| RC-005: pending renewal can repeat | Fixed in source; suite-validated | A pending renewal terminates the current UID's signed-in session instead of starting another renewal cycle. The policy test and full Flutter suite pass. |
| RC-006: unit test cemented admin/pairing conflict | Fixed and unit-validated | The contradictory test was replaced with role-distinguishing assertions; focused policy tests pass. |
| RC-007: legacy `admin` cannot use workspace device controls | Confirmed as a policy/UI mismatch; decision required | `canManageTenantSecurity` permits `tenant_admin` and selected `super_admin`, while rules/notifier authorization are broader for tenant admins/admin-equivalent roles. Decide whether legacy `admin` should have this UI, then align router, screen, notifier, rules, and tests. Do not silently expand access. |
| RC-008: blocked-device recovery is absent | Confirmed | `resetDevice` accepts only `revoked`; blocked devices have no recovery transition and are not reusable. Decide whether blocking is intentionally terminal or provide a separately authorized, audited recovery path. |
| RC-009: Rules accept legacy `manager`, app does not | Not a defect as stated | `canonicalRoleName` maps `manager` to `admin`; Rules also treat `manager` as admin-equivalent. Preserve this compatibility unless a data migration and explicit role-policy change authorize removal. |
| RC-010: missing platform policy document | Confirmed and emulator-validated | A missing policy document caused workspace-admin registration to fail in the emulator despite the intended 3/2 defaults. Rules now explicitly handle an absent document, and a dedicated missing-policy registration test passes. |
| RC-011: sign-out decisions parse error strings | Fixed and test-validated | Renewal now classifies `SessionAccessException` codes instead of matching error text. Typed mapping tests and the full Flutter suite pass. |
| RC-012: device/session enforcement is client-side | Confirmed architecture constraint | Session records do not bind ordinary Firestore reads/writes to a live session. Keep documentation explicit: revocation controls app behavior, not direct ID-token authorization. Server enforcement is outside the current Spark client-only architecture. |

### Original Master-Audit Findings Rechecked

| Finding | Current-source assessment | Plan treatment |
|---|---|---|
| AUTH-001: wrong device slot used for post-write clock check | Fixed in source | The code resolves `session.deviceSlotId` with `deviceSlotIdForSession`, fetches that server document, and verifies its installation ID. Preserve this behavior; add/retain a regression with different device and session slot indexes. |
| AUTH-002: stale access-check race during login | Substantially fixed in source | Sign-in loading is checked, access checks are generation-scoped and queued, and missing-session enforcement has a 15-second grace. Keep a gated race test proving the queued post-registration server check runs. |
| AUTH-003: admin reads of absent session slots fail | Not supported by current Rules | `canReadAccessRecordSlot` authorizes based on the target user's tenant and `accessRecordSlotMatchesUser` explicitly accepts `resource == null`. The notifier still reads fixed slots; verify the actual multi-read transaction in the emulator rather than changing rules based on the old claim. |
| AUTH-004 / AUTH-020: tenant/platform revocation undone by renewal | Confirmed in current source; overlaps RC-003 | Resolve with RC-003 and explicit renewal-versus-interactive-login semantics. Ensure interactive login can resume a revoked session where policy allows, but background renewal cannot. |
| AUTH-005: tenant-admin security route rejected | Fixed in source | The router checks `canManageTenantSecurity` against the path tenant; that helper permits same-tenant `tenant_admin` and requires selected-workspace equality for `super_admin`. Add/retain router boundary tests, including foreign tenant IDs. |
| AUTH-006: transient registration errors sign out | Still present by design; UX/availability risk | Auth sign-in rolls back after registration failure, including transient failures, while preserving/rethrowing the underlying error. Keep fail-closed policy unless product/security requirements say otherwise; classify errors and ensure actionable messages and safe retry rather than retaining an unregistered authenticated session. |
| AUTH-007: stale async failure signs out a different UID | Fixed in source for inspected paths | `_signOutIfCurrentUid`, sign-out UID rechecks, and deferred token-refresh UID check are present. Add an account-switch-during-await regression so the guard remains durable. |
| AUTH-008: resume fails to restart renewal timer | Fixed in source | `_onAppResumed` restarts renewal for the resumed profile. Add/retain a pause/resume timer test. |
| AUTH-009: expiry/staleness relies on client clock | Confirmed residual risk | Session expiry and stale-device selection use `DateTime.now()` while Rules use `request.time`. Bound and test clock-skew behavior; assess server-time offset feasibility without weakening Rules. |
| AUTH-010: cached inactive profile can sign out user | Conditional, unresolved | Profile snapshots are consumed without explicit cache metadata checks, and inactive profile emission triggers sign-out. Reproduce/test cached-inactive then server-active sequencing before changing enforcement. |
| AUTH-011: reinstall rotates installation ID | Expected policy behavior, not a defect | Preserve pairing and slot-limit enforcement; improve specific error guidance only if device testing shows the UX is ambiguous. |
| AUTH-012: App Check activation failure mounts app | Stale finding for this baseline | Activation is awaited inside startup initialization before `startupReady` becomes true; failure selects the initialization failure UI. Preserve and test startup gate/configuration behavior. |
| AUTH-013: session search is ignored | Fixed in source | `filteredSessions` is passed to the session tab. Retain a widget test for matching/nonmatching rows. |
| AUTH-014: registry truncation/recovery | Partially open | Tenant registries use hard 200-row caps with a notice and no cursor paging. Retry exists for the registry stream error state. Plan paging and explicit completeness/truncation state; verify all streams have retry. |
| AUTH-015: blocked-device recovery missing | Confirmed, overlaps RC-008 | Resolve via explicit product/security decision, then add policy, UI, provider, Rules, audit metadata, and emulator coverage together. |
| AUTH-016 / AUTH-023: tenant access-policy authority mismatch | Stale for the current cap-only contract; retain boundary tests | Current UI and `updateTenantAccessLimits` allow same-tenant `tenant_admin`; tenant Rules allow those two cap fields only. Full tenant policy changes remain selected-super-admin-only. Test this intended split and prevent workspace admins from changing pairing/lifecycle fields. |
| AUTH-017: selected super-admin can open foreign security URL | Fixed in source | Router checks the requested tenant against `activeWorkspaceId` through `canManageTenantSecurity`. Retain foreign-workspace route tests. |
| AUTH-018: selected super-admin dashboard remains platform dashboard | Behavior confirmed; requirement needs product decision | Dashboard branches on super-admin with null tenant, which appears to remain true after workspace selection. Decide whether selected support context should expose workspace business metrics or remain platform-only; if changed, enforce selected-workspace scope in every provider and Rules path. |
| AUTH-019: workspace switching/sign-out can omit support end event | Confirmed residual audit gap | `selectWorkspace` writes a new start without ending an existing context. Sign-out attempts a batched end event but catches failure and proceeds to Firebase sign-out. Add atomic end+start switching and a visible/retryable policy for failed context cleanup. |
| AUTH-021: same-UID role changes retain timers | Fixed in source | Role is part of `shouldResetSessionContext`; listener resets the session clock and restarts role-sensitive timers. Retain same-UID role-change tests. |
| AUTH-022: admin export provider omitted from role invalidation | Fixed in source | `_invalidateRoleScopedProviders` invalidates `allTransactionsExportProvider`. Retain admin-to-seller cache-isolation coverage. |

## Implementation Plan

### Phase 0: Incident Evidence And Contract Freeze

1. Capture the affected account's UID transition (never credentials/tokens), normalized role, tenant/workspace, installation ID, device slot, session slot, statuses, expiry, last-seen timestamps, pairing policy, mapped login error, and the caller responsible for any sign-out.
2. Confirm whether the incident was an in-place update, reinstall/data clear, or new installation. Distinguish Firebase Auth becoming null from a router redirect while Auth remains signed in.
3. Freeze role semantics: seller pairing remains tenant-configured; workspace admins use the shared platform cap; super-admin uses separate platform slots; no user approves their own device.
4. Record decisions for legacy `admin` access to workspace device administration, blocked-device recovery, and selected-super-admin dashboard behavior before implementing those product-dependent changes.

**Exit criteria:** incident evidence is sufficient to identify the triggering branch, or the issue is explicitly tracked as unreproduced with the exact missing evidence listed. Policy decisions are recorded before authorization changes.

### Phase 1: Login And Renewal Correctness (P0)

1. **Done:** RC-001 narrow platform-session reactivation rule fix; same-slot emulator test passes.
2. **Done:** RC-002 workspace-admin pairing exemption and in-place pending-slot recovery; seller approval/self-approval protections retained.
3. **Done:** RC-003 renewal revocation checks account for an eligible live same-installation record across tenant device, tenant session, and platform paths.
4. **Done:** RC-004 logout revokes every active matching session in a single bounded batch.
5. **Done:** RC-005 pending renewal ends only the currently checked UID's session.
6. **Done:** RC-011 typed access errors replace renewal's string matching and map to existing localized keys.
7. **Done:** RC-010 missing platform policy fallback is explicitly guarded and emulator-tested.

**Exit criteria:** a legitimate live session is not rejected due to unrelated revoked history; revoked-only renewal remains denied; same-slot sign-out/sign-in works for super-admin, workspace admin, and seller; pending seller remains pending; pending admin resumes only when the existing slot is still within the current platform cap.

### Phase 2: Authorization And Device-Control Consistency (P1)

1. Resolve RC-007: choose whether legacy workspace `admin` receives the same workspace device-control UI as `tenant_admin`. Align `canManageTenantSecurity`, router redirect, screen visibility, provider authorization, Rules, and role matrix tests.
2. Resolve RC-008/AUTH-015: choose whether `blocked` is a terminal security state. If reversible, introduce a distinct authorized recovery transition with actor, reason, timestamps, tenant scoping, and audit log; never treat a block as an ordinary reusable slot. If terminal, show that permanence and define how capacity is recovered safely.
3. Keep AUTH-003 rules unchanged unless emulator execution disproves the current missing-slot read path. Exercise `_setDeviceAccess` against one present session and the remaining missing fixed slots, including admin and selected super-admin actors.
4. Assert the cap authority contract: tenant admins may update only `max_devices_allowed`, `max_active_sessions_allowed`, and timestamp fields in their own tenant; only selected super-admins may update pairing/reset/lifecycle policy; platform workspace-admin caps remain super-admin-controlled.
5. Test same-tenant and foreign-tenant security routes, self-approval denial, cross-tenant control denial, and role-specific visible actions.

**Exit criteria:** client UI/notifier and Rules grant the same role actions; no cross-tenant or self-approval path is introduced; blocked-device behavior is documented and tested.

### Phase 3: Auth Lifecycle And Support-Access Reliability (P1/P2)

1. Add deterministic guard tests for a pre-registration revoked snapshot completing after successful registration; verify the stale result is discarded and a queued server recheck runs.
2. Add UID-switch tests for delayed registration failure, stale guard completion, and deferred token-refresh failure. Preserve the current expected-UID checks.
3. Test transient Firestore/network registration failure mapping and retry behavior. Do not keep an authenticated user without an access record unless a reviewed policy explicitly permits it.
4. Test profile cache behavior: cached inactive followed by server-active, and server-confirmed inactive. Change enforcement only if the test proves cached data can cause an invalid sign-out; do not weaken confirmed inactive-account enforcement.
5. Verify `AppCheck.activate` failure stays on the initialization failure surface and that the retry path reruns initialization; no change is planned unless runtime/config tests falsify the current startup gate.
6. Test session renewal after pause/resume and same-UID role/tenant changes, including timer cancellation/rearming and role-specific timeout changes.
7. Make `selectWorkspace` end the prior support context and start the next one atomically, recording both events. Define a safe, visible failure path for `endWorkspaceAccess` or sign-out cleanup failure, while preserving server-enforced eight-hour expiry.
8. Decide whether selected super-admins should see selected-workspace dashboard metrics. If yes, scope every dashboard query to `active_workspace_id`, keep platform metadata separate, and test no-workspace/own-workspace/foreign-workspace cases.

**Exit criteria:** no stale asynchronous operation signs out a different UID; cached state cannot be mistaken for confirmed authorization; renewal resumes correctly; support access has balanced start/end records or a visible, auditable failure state.

### Phase 4: Device Registry Operability And Time Semantics (P2)

1. Replace tenant registry hard caps with cursor-based paging or an explicit load-more contract. Keep a visible truncation indicator until all pages are loaded; do not silently imply completeness at 200 records.
2. Verify retry actions cover tenant, device, session, user, policy, and platform-session providers. Keep the existing session search behavior and add widget tests for both tabs.
3. Assess client-clock expiry and 30-day stale-device decisions against Firestore `request.time`. Define a bounded server-time offset or another Spark-compatible approach; do not relax Rules TTL/expiry limits.
4. Add boundary tests for clock offsets around the five-minute tolerance, expiry limit, and stale-device threshold, including expected localized user errors.
5. Confirm installation identity persistence on in-place Android update and rotation on clear-data/reinstall/web-origin changes. Treat approval/capacity enforcement for a new installation as expected behavior, not an auth bypass.

**Exit criteria:** registry completeness is explicit, retries recover, time-boundary behavior is predictable, and installation changes produce actionable policy outcomes.

### Phase 5: Verification, Documentation, And Release Readiness

1. **Done:** focused session/error policy tests; full Flutter suite (`562` passed); Flutter and Dart test analysis clean.
2. **Partial:** Rules Emulator has `113 passing`, including platform/seller/admin same-slot re-login and missing-policy fallback. Direct notifier transaction tests and device-history reproduction remain pending.
3. **Pending:** widget/router role matrix, pagination/retry, blocked-device decision, and support-context transition tests.
4. **Done:** focused tests, full Flutter suite, both analyzers, Rules Emulator suite, repository Markdown gate, Firestore rules/indexes deployment, split-per-ABI build, and ARM64 in-place install.
5. Runtime-contract documentation and regression-registry updates are complete for the implemented fixes. Keep status changes evidence-based; do not treat package installation as verification of an authenticated sign-in flow.
6. For full release signoff, complete any required Hosting deployment if web release is in scope, authenticated device smoke testing, then Git audit and requested commit/push. Hosting deploy, authenticated sign-in smoke test, commit, and push were not performed here.

**Current result:** executable test/analyzer gates passed; Rules/indexes deployed; release APK set built; ARM64 package installed and version-confirmed. Remaining work includes authenticated device smoke testing, optional Hosting release, and unresolved product decisions.

## Required Decisions

1. Should legacy tenant `admin` users have the device-administration page and operations already permitted by Rules, or should both UI and Rules narrow to `tenant_admin`?
2. Is `blocked` a terminal security state, or should a separately audited administrator/super-admin recovery transition exist?
3. Should an active super-admin support context change the dashboard from platform metadata to selected-workspace business metrics?
4. Should a transient access-registration failure always roll back Firebase Auth, or is a bounded retry/recovery state required? Any change must retain the rule that business access is not mounted without valid scoped access.

## Non-Goals And Guardrails

- Do not disable seller device approval or allow self-approval.
- Do not weaken tenant scoping, platform session caps, expiry limits, or support-access reason/audit requirements to make a test pass.
- Do not claim device/session documents are a Firestore authorization boundary under the current client-only Spark design.
- Do not remove legacy `manager` compatibility without a verified data migration and contract change.
- Do not modify production business data. No commit/push or authenticated sign-in test was performed as part of this release.
