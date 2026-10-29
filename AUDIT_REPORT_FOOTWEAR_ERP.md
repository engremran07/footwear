# ShoesERP — Ultimate Master Audit Report

**Audit version:** v13 (88-agent governance pack v2.0)  
**Date:** 2026-04-11  
**App version:** v3.5.0+43 (post-remediation)  
**Auditor:** GitHub Copilot (Claude Sonnet 4.6) — autonomous multi-agent system  
**Baseline commit:** 3377697 (v3.4.11+42)  
**Branch:** main  
**Firebase project:** shoeserp-clean-20260327

---

## Scope-Specific Addendum — 2026-10-29 Pass 2 Financial Findings

### Finding-by-Finding Disposition

The attached Pass 2 report contains 21 findings. "Fixed" below refers to
current local source and test evidence, not production deployment. Partial
client-side checks are explicitly separated from Firestore Rules enforcement.

| Finding | Disposition | Evidence and remaining limit |
| --- | --- | --- |
| P1-01: seller stock-sale Rules access-call budget | Not reproduced in tested range | Emulator coverage exercises 30-line sales and sampled counts of 5, 10, 15, 20, and 30. There is no declared maximum or proof for more than 30 lines, so unbounded cart size remains unverified. |
| P1-02: settlement ignores credit notes | Fixed | `markAsPaid` settles the remaining amount after receipts and credits; credit-note writes update the original outstanding amount/status atomically. `mark_paid_outstanding_test.dart` covers credit-aware settlement. |
| P1-03: cash-entry retries can duplicate writes | Fixed for supported client flow | Standalone cash entries use a caller-stable idempotency key, deterministic tenant-scoped document ID, and Firestore transaction. The 20-second wrapper timeout was removed; delayed-network behavior was not fault-injected. |
| P1-04: money uses doubles and tolerance comparisons | Partially fixed; migration deferred | Parser/provider guards reject ambiguous and sub-cent input. Stored amounts and balances remain doubles and Rules retain existing tolerances. Integer minor-unit migration requires historical reconciliation, backup/PDF compatibility, Rules rollout, and a minimum-client policy. |
| P2-01: seller cash receipts do not notify admins | Fixed in current client/Rules | Receipt creation writes a linked `cash_in` invoice notification after its financial transaction; Rules accept only a matching cash-receipt invoice. Notification delivery remains best-effort and logged. |
| P2-02: amount caps are inconsistent and currency-agnostic | Partially fixed; currency policy remains unresolved | Local providers and Rules now apply the established `999999.99` ceiling to sale/credit invoices, receipts, standalone cash, seller edit requests, and corrections. SAR and PKR share the same provisional ceiling; no currency-specific business limits have been approved. |
| P2-03: ambiguous precision and sub-cent input | Fixed at parser/provider boundaries | `1.500` is rejected while supported grouping such as `1,500` remains valid; changed financial provider inputs reject more than two decimals. The broader server/double residual is tracked under P1-04. |
| P2-04: seller dashboard combines route currencies | Fixed | Seller dashboard totals use currency-grouped route/shop statistics instead of labeling a cross-currency sum with the first route's currency. A focused dashboard currency test exists. |
| P2-05: credit-note lines and 30-day window are not validated | Fixed for supported provider flow | Quantities are aggregated by variant against the original sale and active notes; the server Rules window uses request time. Seller-stock restores are additionally bounded cumulatively by the original sale's recorded deductions. |
| P2-06: sale lines can disagree with stock deductions | Partially fixed; Rules residual remains | Provider validates positive whole quantities, variant IDs, and exact pair deductions by variant (`qty` dozens plus `extra_pairs`, converted using workspace `pairs_per_carton`). Rules cannot iterate item lists, so a modified client can bypass this comparison; no periodic admin reconciliation report was added. |
| P2-07: each invoice stores a logo copy | Retained by current output contract | Invoice header snapshots and saved-logo fallback are required by the current PDF governance contract. The proposed removal would break historical branding/fallback behavior; storage cost has not been separately measured. |
| P2-08: invoice year uses device clock and credit notes share `INV-` | Fixed for new writes; historical identifiers unchanged | New sale, credit-note, and receipt numbers use the tenant-wide high-water sequence above the greater of the legacy invoice and receipt counters, with `INV-`, `CN-`, and `REC-` prefixes and no device-clock year. Firestore Rules validate the shared sequence on same-batch counter/invoice writes; receipt updates carry `last_cash_receipt_id` to bind the exact invoice. Existing identifiers and counters remain unchanged until advanced by a new operation. Deployment remains gated on a client compatibility/minimum-version rollout because older clients still increment only one counter. |
| P3-01: unreachable return-notification block | Fixed / no longer present | Current return/credit-note completion has no seller-notification call; the shared writer accepts invoice and standalone transaction sources, not `return`. |
| P3-02: invoice counter serializes concurrent sales | Hypothesis not measured | Counter increment is inside the same Firestore transaction as invoice writes. No concurrent-load emulator benchmark established a user-visible contention failure; changing to block allocation would alter numbering and is not justified by current evidence. |
| P3-03: transaction deletion is read-then-batch | Fixed | `deleteTransaction` re-reads transaction and shop inside `runTransaction`, then soft-deletes and reverses the exact balance atomically. |
| P3-04: `customer_id` remains dual-written | Finding conflicts with runtime contract | `customer_id == shop_id` is intentionally retained for legacy readers and is mandated by the current dual-write contract. The inaccurate provider comment was corrected rather than removing the field. |
| P3-05: idempotency pre-check query is dead and unauthorized | Fixed | The list-query pre-check is absent; the deterministic document ID is read inside the transaction. |
| P3-06: invoice void discovers linked transactions before its transaction | Partially mitigated; legacy edge remains | Void reads invoice-stored transaction IDs inside the transaction and reads each referenced row there. Current settlement atomically appends its payment ID to the invoice, causing transaction retries to observe concurrent current-client settlements. The outside query is retained to include legacy rows lacking invoice pointers; no forced interleaving test covers obsolete clients. |
| P3-07: seller edit setting name is inverted | Fixed with migration compatibility | Current writes use `allow_seller_edit_requests`; model/provider reads fall back to the legacy key. Serialization writes only the canonical key. |
| P4-01: literal `void` differs from the model constant | Fixed in Dart | Provider comparisons use `InvoiceModel.statusVoid`; Firestore Rules retain the canonical persisted string because Rules cannot reference Dart constants. |
| P4-02: duplicate amount constants | Fixed locally | Provider amount checks use the shared financial amount policy, and Firestore Rules enforce the same `999999.99` ceiling across invoice, receipt, standalone transaction, edit-request, and correction paths. Currency-specific limits remain open under P2-02. |

### Verification and Residual Risks

- The previous focused monetary/credit-note suite reported
  `00:00 +70: All tests passed!`. The follow-up stock sale/restore suite
  reported `00:00 +40: All tests passed!`.
- Previous Pass 2 validation: full Flutter suite
  `01:40 +759: All tests passed!`; Rules Emulator `201 passing (52s)`;
  `dart analyze test/`: `No issues found!`. Coverage includes valid invoice
  boundaries, over-limit sale/receipt/standalone transaction and correction
  batches, and a denied over-limit seller edit request.
- Shared-sequence correction: `InvoiceNumbering.nextSequence` allocates above
  the greater of the legacy invoice and receipt counters for sales,
  credit-notes, and receipts. Rules enforce the same next counter value and
  bind the advanced counter to the invoice in the same write. Regressions
  prove a receipt after invoice counter 4 uses 5, a sale after receipt counter
  4 uses 5, and a stale invoice/receipt counter update is denied. Current
  local verification: focused numbering suite `00:00 +5: All tests passed!`;
  full Flutter suite `01:48 +761: All tests passed!`; Rules Emulator
  `202 passing (57s)`; `dart analyze test/`: `No issues found!`. Flutter
  library analysis retains one pre-existing unused `_commit` diagnostic
  (`1 issue found. (ran in 8.1s)`). The emulator still prints expression-limit
  diagnostics for some broad negative transaction batches; the added
  counter-only stale-write denials evaluate and reject directly.
- The new Rules contract is local only. Older clients increment one counter
  independently and can be denied when the other counter is higher; no
  minimum-client enforcement or migration rollout has been implemented.
- `flutter analyze lib --no-pub` reports one pre-existing unused-element
  diagnostic for `TransactionNotifier._commit` at line 410
  (`1 issue found. (ran in 167.1s)`). The helper was traced to commit
  `805b6072`; it was not removed because it is unrelated to the financial
  policy changes.
- Repository Markdown lint and `git diff --check` exited 0. Hot restart was
  attempted through the connected Dart Tooling Daemon, but it had no running
  Flutter app.
- A composite invoice index for `(tenant_id, linked_invoice_id)` is present
  locally. The provider-side item-to-deduction check is not Rules enforcement.
  P1-04 remains release-blocking: stored monetary values and shop balances are
  still doubles with tolerance comparisons; integer minor-unit conversion,
  historical reconciliation, backup/PDF compatibility, and a minimum-client
  rollout strategy have not been implemented. Equal SAR/PKR caps do not settle
  currency-specific policy. Invoice-counter contention has not been measured.
- Safe cutover sequence identified; implementation remains blocked pending
  reviewed schema and access authorization:
  1. Inventory every monetary field and writer/reader, including shop balances,
     invoice lifecycle totals, ledger rows, backups/restores, and export/PDF
     calculations. Add dual-read and representation-consistency tests before
     changing persisted data.
  2. Release a compatibility client that reads legacy values while
     dual-writing validated integer minor units with legacy values in the same
     atomic financial operation. Rules must check both representations agree
     and preserve existing client writes during this migration phase.
  3. Take a verified, tenant-scoped backup and run a paged, read-only
     production preview. Reject sub-cent/ambiguous values, tenant mismatches,
     missing links, and shop-ledger reconciliation exceptions; do not infer
     shop balances by summing incomplete/voided historical ledger rows.
  4. Review the preview and reconcile exceptions before any write. Backfill
     only companion integer fields in idempotent tenant-scoped batches without
     changing historical monetary values or deleting ledger records.
  5. Establish and enforce a minimum compatible client version (old clients
     must fail with actionable update guidance), then deploy Rules requiring
     integer values and exact minor-unit balance deltas. Only after every
     tenant is reconciled may integer fields become the sole monetary source
     and legacy double fields be retired.
  No production reads or writes have been authorized for this session, and no
  approved backup artifact, reconciliation preview, or minimum-client
  mechanism is evidenced; therefore no backfill or release is safe yet.
- Rules/index deployment, Hosting, release builds, device delivery, commit,
  and push are separate operations and are not represented as completed by
  this audit entry.

---

## Scope-Specific Addendum — 2026-10-28 v3.10.14+1125 Notifications

### Verified Finding and Change

- The notification screen's referenced-shop visibility stream previously
  queried as many as 30 IDs at once. The Rules path combines tenant, active
  profile, role, and shop-visibility checks; the large query exceeded the
  Firestore Rules document-access-call budget in a larger workspace. This
  explains why smaller workspaces could work while JBM Impex failed.
- Shop visibility now resolves IDs in batches of five. App authorization and
  Firestore Rules were not weakened. A 50-shop emulator regression covers
  both workspace admins and supervisors across ten chunks.
- Android alerts are opt-in and foreground-only. They reuse existing
  tenant-scoped feed and visibility providers, add no Firestore listener or
  FCM sender, and request OS notification permission only after user action.
  Closed-app/background delivery is not supported.

### Local Validation

- Focused notification, error-mapping, and changelog suite:
  `00:04 +81: All tests passed!`; localization parity:
  `00:00 +13: All tests passed!`; full Flutter suite:
  `01:29 +708: All tests passed!`.
- `flutter analyze lib --no-pub`: `No issues found! (ran in 16.2s)`;
  `dart analyze test/`: `No issues found!`; full Rules Emulator:
  `191 passing (56s)`.
- Version `3.10.14+1125` is synchronized. The ARM64 APK signature verified
  with APK v2; ADB copied the APK to `R5GL22RGT9V` (`1 file pushed`) and
  installation returned `Success`, versionName `3.10.14`, versionCode
  `310143125`.
- Split APK sizes: ARMv7 `32,857,045` bytes, ARM64 `34,520,181` bytes, and
  x86_64 `36,142,717` bytes. The signed AAB is `75,804,395` bytes;
  `jarsigner -verify` reported `jar verified.` while warning that its
  self-signed certificate is not trusted locally and it has no timestamp.
  Play Console upload-key acceptance is not established.
- Web build: `EXIT: 0`; Firestore reported the Rules already current and
  deployed indexes successfully, preserving 23 remote-only indexes and 2
  field overrides. Rules/indexes and Hosting deployments reported
  `Deploy complete!`. Live `version.json` reports `3.10.14+1125`; the web
  shell and main bundle use `no-store, must-revalidate, no-cache`.

### Remaining Evidence

- The live JBM Impex notification feed still needs an authenticated check
  after deployment; local emulator coverage is not production evidence.
- The broader modernization/audit work and the existing unresolved production
  notification investigation remain open until that live check is completed.

---

## Scope-Specific Addendum — 2026-10-28 v3.10.13+1124 Release Delivery

### Verification

- Full Flutter suite: `01:43 +704: All tests passed!`;
  `flutter analyze lib --no-pub`: `No issues found! (ran in 20.9s)`;
  `dart analyze test/`: `No issues found!`; Firestore Rules Emulator:
  `190 passing (56s)`.
- Gradle's cross-volume plugin-source task was fixed by resolving packages
  with the existing same-drive `PUB_CACHE`. The exact
  `:flutter_plugin_android_lifecycle:compileDebugUnitTestSources` task reported
  `BUILD SUCCESSFUL in 55s`. Split APKs built at 31.2/32.8/34.3 MB; the AAB
  built at 72.1 MB and `jarsigner` reported `jar verified.` with an
  untrusted-local-certificate warning and no timestamp.
- The ARM64 APK was copied and installed on `R5GL22RGT9V` (`1 file pushed`,
  `Success`; versionName `3.10.13`, versionCode `310133124`). Web build:
  `EXIT: 0`. Firestore Rules/indexes and Hosting each reported
  `Deploy complete!`; live `version.json` reports `3.10.13+1124`. Twenty-three
  remote indexes and two field overrides absent locally were preserved.

### Remaining Work

- The user-reported notification permission/flicker issue is still open. The
  browser snapshot recorded a 400 resource response and canceled Firestore
  Listen request; neither identified a denied notification or shop-visibility
  query. No authenticated business data was inspected. Request the concrete
  failed operation and Firebase error code if the issue persists after
  deployment; do not broaden Rules or mask errors.
- Play Console upload, commit, and push were not performed. The broader
  multi-pass audit and modernization todos remain open.

---

## Scope-Specific Addendum — 2026-10-28 Mark-All Notification Batch (P2-01)

### Verification and Disposition

- **P2-01 — mark-all's 50-write batch lacked Rules Emulator coverage (not
  present in current worktree):** `NotificationNotifier.markAllAsRead()` caps
  its input at 50 and applies the same server-timestamped unread-to-read patch
  to each document in one batch. Current Rules authorize each update only for
  the tenant notification-reader roles and require the one-way state
  transition.
- The current Rules test suite already contains a 50-notification atomic
  mark-all case. The full Firestore Rules Emulator suite reported
  `190 passing (46s)`, including that case. No 20-call access-limit failure
  was reproduced at the configured 50-item feed cap.
- **Disposition:** the stated untested-batch finding is stale for the current
  worktree and is closed for the 50-item contract. No chunking or Rules
  change was added.

### Validation Boundary

- Local Rules Emulator only. This does not confirm production Rules are
  deployed or measure production write latency. No production operation
  occurred.

---

## Scope-Specific Addendum — 2026-10-28 Notification Visibility Error (P2-02)

### Verification and Disposition

- **P2-02 — one shop-visibility chunk error propagates to the derived feed:**
  confirmed as current behavior. A failed shop query marks the combined
  visibility stream as an error, and the derived feed enters an error state.
  The screen nevertheless retains and displays its last successful rows with
  a retry banner; on first load, it remains fail-closed and shows the mapped
  error rather than displaying shops whose active/deleted status was not
  verified.
- The error is tagged as `shops` or `notifications` internally. The screen
  displays that source only in debug mode, not in release. Focused notification
  unit/widget tests report `00:04 +23: All tests passed!`, including source
  attribution, cached-row retention, mapped errors, and retry UI.
- **Disposition:** the former claim that the feed always disappears is stale
  for cached sessions. The genuine residual is a first-load/partial-chunk
  failure that blocks the complete verified feed, plus limited release
  diagnostics. This is intentionally fail-closed; exposing notifications
  without proving shop visibility would weaken the existing filtering
  contract.

### Remaining Evidence Needed

- No authorized production/browser session or captured Firebase exception
  identified whether the reported permission denial originates in the
  notification query or one of the shop visibility chunks. The source label
  and underlying exception are available to local tests, but no production
  query path, Rules deployment state, or real failure was reproduced here.
- **Status:** leave the permission-denied runtime issue open pending the
  concrete source and Firebase error code. Do not mask it as success or
  broaden notification/shop reads. No Rules or client behavior change was
  made for this finding.

---

## Scope-Specific Addendum — 2026-10-28 Seller Notification Cooldown (P2-03)

### Verification and Disposition

- **P2-03 — a per-seller notification cooldown can discard valid events after
  their financial writes commit:** reproduced against the prior Rules contract.
  Seller notifications are best-effort writes after the invoice or standalone
  transaction commits, so a denied notification did not roll back the ledger
  operation.
- The per-user cooldown update was removed. Each seller notification now uses
  a deterministic source-scoped ID, and Rules require its payload to match a
  persisted same-tenant invoice or standalone transaction. Detached or
  altered source data remains denied; financial writes do not depend on
  notification success.
- A follow-up emulator failure identified an incomplete invoice test fixture:
  the seeded invoice omitted `shop_name` while the notification correctly
  supplied it. The fixture now matches a real persisted invoice. The full
  Rules Emulator suite reports `190 passing (48s)`. Focused writer/provider/
  notification-screen tests report `00:03 +20: All tests passed!`.
- **Disposition:** P2-03 is fixed in local source and has positive and
  adversarial emulator coverage. The separate reported notification-feed
  permission/flicker issue remains open; this fix does not identify or prove
  which production read or mark-read request was denied.

### Validation Boundary

- Local Rules Emulator and Flutter tests only. Rules/indexes remain
  undeployed; no production notification path was tested. No fresh APK/AAB,
  phone delivery, Hosting deployment, commit, or push was performed.

---

## Scope-Specific Addendum — 2026-10-28 Dashboard Cache Tenant Isolation (P2-04)

### Verification and Disposition

- **P2-04 — last-good dashboard metrics were globally cached:** reproduced.
  A test seeded metrics for workspace A, resolved the authenticated profile
  for workspace B, and held B's metric streams in loading. The dashboard
  rendered A's `metrics:11/22` values under B before the fix.
- The cache now stores one scope-tagged entry, keyed by user ID, role, active
  state, concrete tenant/workspace context, support-session identity, and
  sorted assigned route IDs. A fallback is used only for the matching profile
  scope. During profile loading, it also requires the cached profile UID to
  match the current Firebase Auth UID; missing profiles and permission/auth
  errors do not display cached business metrics.
- The regression now verifies that workspace B stays loading instead of
  showing A's values, and that same-workspace refresh still retains its own
  cached metrics. Focused dashboard suite: `00:09 +5: All tests passed!`;
  `flutter analyze lib --no-pub`: `No issues found! (ran in 8.1s)`;
  `dart analyze test/`: `No issues found!`.
- **Disposition:** P2-04 is fixed in local source. No Firestore Rules or query
  shape changed. This does not substitute for multi-tenant emulator coverage
  of other business collections.

### Validation Boundary

- Local Flutter tests and analysis only. A hot restart was unavailable because
  the connected Dart Tooling Daemon had no running Flutter app. No release
  build, phone delivery, deployment, commit, or push occurred.

---

## Scope-Specific Addendum — 2026-10-28 Router Route-Policy Duplication (P2-11)

### Verification and Disposition

- **P2-11 — the router maintained a second tenant-business route list:**
  confirmed as a structural drift risk. `RouterNotifier` classified business
  paths separately from `PermissionPolicy.canAccessRoute()`, so future route
  additions could receive inconsistent workspace-selection redirects.
- Route matching now returns one `RouteAccessDecision` from
  `PermissionPolicy`: allowed, denied, or workspace selection required. The
  router consumes that decision instead of keeping a second path list.
  Existing role, tenant, super-admin support-context, and unknown-route
  behavior is preserved; no permission was broadened.
- Policy and router regressions reported
  `00:14 +28: All tests passed!`; `flutter analyze lib --no-pub` reported
  `No issues found! (ran in 5.6s)`; `dart analyze test/` reported
  `No issues found!`.
- **Disposition:** P2-11 is fixed locally. Firestore Rules, indexes, and route
  declarations were not changed.

### Validation Boundary

- Local Flutter tests and analysis only. The Dart Tooling Daemon had no
  running app, so hot restart was unavailable. No release build, phone
  delivery, deployment, commit, or push occurred.

---

## Scope-Specific Addendum — 2026-10-28 Notification Profile Refresh (P3-04)

### Verification and Disposition

- **P3-04 — a profile refresh could clear the notification tenant scope and
  briefly replace the feed with an empty state:** the original failure mode
  is already fixed in the current worktree. `notificationProfileForState()`
  retains a cached profile only when its ID matches the settled Firebase Auth
  UID; Auth loading/errors and UID mismatches clear the scope. The screen also
  distinguishes profile errors from initial loading.
- The widget regression confirms that during a same-user profile refresh the
  tenant scope remains `tenant-1`, the cached notification remains visible,
  and shimmer does not replace the feed. Missing profiles, profile errors,
  feed errors, and shop-visibility errors have separate failure/retry
  coverage.
- Focused notification widget/provider tests reported
  `00:03 +23: All tests passed!`.
- **Disposition:** P3-04 is fixed in the current local source; no new code
  change was needed for this recheck. This does not resolve the separate
  permission-denied incident in P2-02: the denied production operation and
  deployed Rules version remain unverified. No Rules or index changes were
  made.

### Validation Boundary

- Local Flutter tests only. No production/browser reproduction or Rules
  deployment was performed. No release build, phone delivery, Hosting
  deployment, commit, or push occurred.

---

## Scope-Specific Addendum — 2026-10-28 Action-Specific Operational Guards (P3-05)

### Verification and Disposition

- **P3-05 — `isOperationalRoleName()` was an alias for checking
  `viewRoutes`, while callers used it to authorize route-counter, product,
  and inventory writes:** confirmed semantic drift. The current capability
  matrix already defines the corresponding write capabilities.
- The route-counter guard now checks `manageRoutes`, product administration
  checks `manageProducts`, and seller-stock return checks `manageInventory`.
  The misleading `isOperationalRoleName()` and
  `canManageOperationalDataRole()` wrappers were removed. Role sets remain
  unchanged for the current matrix; supervisor operational access remains
  allowed and seller operational writes remain denied.
- Added action-capability coverage for supervisors and sellers. Focused
  permission-policy tests reported `00:00 +12: All tests passed!`;
  `flutter analyze lib --no-pub` reported
  `No issues found! (ran in 10.0s)`; `dart analyze test/` reported
  `No issues found!`.
- **Disposition:** the misleading action guards are corrected locally.
  Firestore Rules and collection queries were not changed. The wider P1-04
  inventory of raw role checks remains open; this narrow correction does not
  claim full capability-policy migration.

### Validation Boundary

- Local Flutter tests and analysis only. No Rules changes, production
  deployment, release build, phone delivery, commit, or push occurred.

---

## Scope-Specific Addendum — 2026-10-28 Canonical Workspace Role Writes (P3-08)

### Verification and Disposition

- **P3-08 — `isWorkspaceAssignableRole()` uses exact lowercase role values
  while role-read helpers accept legacy aliases/casing:** verified as
  intentional write validation, not a bug. Existing Rules tests assert that
  workspace role writes must be canonical, and provider writers normalize
  roles before saving. Relaxing the predicate would accept noncanonical
  values on new writes without improving legacy-read compatibility.
- The focused Rules Emulator case reported `1 passing (9s)` and verified that
  the workspace role write using a padded uppercase value is denied.
- **Disposition:** no Rules change. Keep read compatibility separate from the
  canonical format required for new role writes.

### Validation Boundary

- Focused local Rules Emulator test only. Production Rules deployment status
  was not tested. No source or Rules modification was made for this finding.

---

## Scope-Specific Addendum — 2026-10-28 Notification Minor Findings (P4-01, P4-04)

### Verification and Disposition

- **P4-01 — unused `now` parameter on `notificationTenantIdFor()`:** not
  present in current source; the function has no `now` parameter.
- **P4-04 — stale "operational-admin" comment:** not present in the current
  notification screen. Its file header correctly describes the feed as
  available to admins and supervisors.
- **Disposition:** both findings are already resolved in the current
  worktree; no code change was needed.

---

## Scope-Specific Addendum — 2026-10-28 Runtime-Configurable Role Policy (P1-03)

### Verification and Disposition

- **P1-03 — per-workspace configurable role capabilities are absent
  (confirmed as an absent feature, not a current authorization defect):**
  `SettingsModel` exposes workspace invoice/edit-policy toggles but no
  `role_policy` or capability overrides. App permissions come from the
  canonical `RoleCapabilities`/`PermissionPolicy` implementation, while
  Firestore Rules independently enforce the role and tenant contract.
- The runtime contract specifies fixed, operation-specific role capabilities
  and says screens/providers must reuse that policy; it does not require
  administrators to redefine the role matrix at runtime. Adding deny-only
  overrides would require a schema, supported capability list, authorized
  editor policy, Rules enforcement, migration defaults, and positive/negative
  emulator coverage.
- **Disposition:** do not add a dynamic role-policy subsystem as an audit
  hotfix. Treat it as a product/security feature requiring an explicit
  capability list and governance decision. No current policy bypass was
  established by this finding alone.

---

## Scope-Specific Addendum — 2026-10-28 Client/Rules Release Skew (P1-02)

### Verification and Fix

- **P1-02 — a release could be published even when Rules/Hosting deployment
  failed (verified and gated locally):** In the release workflow, the
  GitHub Release job previously depended on validation, artifact building,
  and Rules tests, but not on the deployment job. It could therefore publish
  APK artifacts after a failed Rules or Hosting deployment.
- The release job now also requires successful completion of `deploy`.
  The current `deploy-web.yml` and `release.yml` source orders Firestore
  Rules/index deployment before Hosting, and both workflows gate deployment
  on the Firestore Rules test workflow. A local structural check confirmed the
  job dependency and step order.

### Remaining Version-Skew Boundary

- **Partial, not a production synchronization claim:** No workflow was run
  against GitHub or Firebase in this verification. The app has no startup
  Rules-version handshake, and the separate manual APK/AAB artifact workflow
  can still produce an artifact without deploying Rules. Production Rules
  timestamp, secret availability, and client/server compatibility remain
  unverified until the authorized release sequence succeeds.
- This work does not change application behavior or Firestore data. No
  production deploy, release build, device delivery, commit, or push occurred.

---

## Scope-Specific Addendum — 2026-10-28 Email Verification Sync (P1-01)

### Verification and Disposition

- **P1-01 — Auth-to-profile email verification update denied by Rules (not
  reproducible in current working tree):** The user self-update allowlist
  includes `email` and `email_verified`. Rules permit `email_verified` only
  when it equals the authenticated token claim, and permit an email mirror
  only when it equals the token email and that claim is verified.
- Both client paths (`signIn()` and `syncEmailVerification()`) reload Firebase
  Auth state and force-refresh the ID token before writing. The resume path
  also rechecks the current UID and verified state after refresh. Sync failures
  remain non-blocking and are logged.
- Rules Emulator regressions cover denial when an unverified claim attempts
  to set `email_verified`, success when a verified token synchronizes its
  email/profile state, and denial of a forged email. Focused run:
  `2 passing (8s)`.
- **Disposition:** the reported client/Rules mismatch is already corrected in
  the current working tree. No further code change is justified by the
  reproduced evidence. The test run does not exercise Firebase Auth's real
  network token refresh.

### Validation Boundary

- The emulator validated the Rules contract; source inspection validated the
  client ordering. No production Auth account/data access or deployment
  occurred. Production Rules version alignment remains a separate release
  gate.

---

## Scope-Specific Addendum — 2026-10-28 Large Invoice Rules Budget (P2-10)

### Verification and Disposition

- **P2-10 — large invoice batches may exceed Rules access-call limits
  (30-line scenario not reproduced):** Added a seller regression that creates
  an invoice with 30 lines and 30 distinct seller-inventory deductions in the
  same atomic write as the invoice counter, sale transaction, and shop balance.
  The full local Firestore Rules Emulator suite reported `190 passing (46s)`,
  including the new case. No Rules access-call-limit rejection occurred.
- The provider does read each deducted seller-inventory document before
  committing, so a 30-deduction invoice necessarily incurs those Firestore
  document reads. The emulator test does not measure production latency,
  Spark quota consumption, or overall workload cost.
- **Disposition:** the stated 30-line Rules ceiling concern is not reproduced
  and no Rules change is warranted. Keep read-cost/workload profiling as a
  separate open measurement; the emulator result is not a quota or performance
  certification.

### Validation Boundary

- Local emulator only. No production data was accessed and no Rules or index
  deployment, build, phone delivery, commit, or push occurred.

---

## Scope-Specific Addendum — 2026-10-28 Super-Admin Notification Access (P2-09)

### Verification and Disposition

- **P2-09 — platform super-admins cannot read tenant notifications during
  support access (intentional and documented):** `RoleCapabilities.matrix`
  does not grant `viewNotifications` to `super_admin`, and the independent
  Firestore Rules helper excludes super-admins from notification readers even
  when the selected support context is valid. Existing Rules Emulator
  coverage explicitly denies the selected-workspace feed, a different
  workspace feed, and mark-read writes.
- The runtime contract and project documentation already state that tenant
  notifications are available to admin/manager, tenant_admin, and supervisor
  roles, while sellers and platform super-admins are excluded. The focused
  role/policy suite reported `00:00 +11: All tests passed!`.
- **Disposition:** no capability or Rules change is warranted. Adding a
  support-only read permission would broaden platform access and conflict with
  the current privacy policy; treat that as a separate product/security
  decision, not an audit bug.

### Validation Boundary

- Current app policy, Rules source, Rules regression assertions, and the
  published runtime documentation were inspected. The emulator test itself
  was not rerun in this verification. No production access or deployment
  occurred.

---

## Scope-Specific Addendum — 2026-10-28 Profile-Read Error Routing (P2-08)

### Verification and Disposition

- **P2-08 — profile-stream errors routed to bootstrap as if the profile were
  missing (not reproducible in current source):** The router may send an
  authenticated user with a failed profile stream to `/bootstrap-profile`,
  but `BootstrapProfileScreen` renders the mapped error state with Retry for
  `authUserProvider` errors; it does not render the missing-profile message.
  The notification route separately retains its mapped profile-permission
  error and retry feedback.
- The screen regression asserts that a profile-read error shows `ErrorState`
  and Retry, not missing-profile copy. The router regression covers profile
  permission-denied feedback on `/notifications`. The combined focused run
  reported `00:11 +17: All tests passed!`.
- **Disposition:** the reported user-visible failure is not present in the
  current code path, so no router or screen workaround was added. This
  finding is closed for the current source revision; it does not establish
  that any earlier deployed build contains the same behavior.

### Validation Boundary

- Source and focused widget/router regressions were checked locally. No
  production account or Firestore data was accessed, and no deployment,
  release build, device delivery, commit, or push was performed.

---

## Scope-Specific Addendum — 2026-10-28 Super-Admin Listener Expiry (P2-05)

### Verification and Fix

- **P2-05 — persistent selected-workspace settings listener outlived context
  expiry (verified and fixed locally):** The router's expiry timer only
  refreshed route authorization. `settingsProvider` is non-`autoDispose` and
  remained subscribed to `settings/{tenantId}`; its document selection used
  the super-admin's `tenantId` without validating support-context age. The
  pre-fix regression returned `tenant-42` for a context older than eight
  hours.
- The provider now requires an active profile and a reasoned, unexpired,
  concrete super-admin workspace context before selecting its settings document. For a
  valid context it schedules self-invalidation at expiry and cancels the timer
  on disposal. The rebuild emits the no-active-workspace settings state and
  closes the old stream instead of reconnecting. The client TTL is centralized
  in `UserModel` and shared with router and tenant-scoped provider timers;
  Firestore Rules remain authoritative.
- Focused settings/model/permission/router suite:
  `00:11 +60: All tests passed!`; `flutter analyze lib --no-pub`:
  `No issues found! (ran in 5.5s)`; `dart analyze test/`:
  `No issues found!`.

### Boundaries

- No Rules or indexes changed. No Firestore read against production data was
  performed; the regression confirms the expired path returns the fallback
  before obtaining a Firestore instance.
- This is local and unreleased. The full Flutter suite, fresh release
  artifacts, device delivery, production deployment, commit, and push remain
  pending.

---

## Scope-Specific Addendum — 2026-10-28 Legacy `__global__` Compatibility (P2-06)

### Verification and Disposition

- **P2-06 — legacy global-tenant compatibility remains in read Rules
  (confirmed; removal blocked):** `firestore.rules` treats the sentinel as
  active for compatibility, has a legacy settings lookup fallback, and has a
  settings read branch for an unassigned profile. The Rules Emulator fixtures
  explicitly verify that an unassigned legacy admin can read a seeded global
  product, while new product, variant, route, shop, and inventory-log creates
  using `__global__` are denied. Notification reads for a null-tenant profile
  are separately denied.
- The two tenant-backfill scripts are fail-closed because assigning unscoped
  records to one tenant could disclose data across workspaces. No production
  data inventory, per-record ownership map, or approved recovery plan is
  available in this audit scope. Removing the legacy read branches now could
  strand existing business records or guess their ownership.
- **Disposition:** do not remove the compatibility branches until a reviewed,
  per-record migration map and recovery procedure establish that the legacy
  documents have been safely assigned or retired. New business writes must
  continue to require a concrete tenant. This finding remains open and is not
  claimed fixed.

---

## Scope-Specific Addendum — 2026-10-28 Archived Workspace Access UX

### Confirmed Finding and Fix

- **Medium — archived workspace had no member-facing recovery state (fixed
  locally):** Rules already denied ordinary business access when the tenant
  document was inactive, but the app shell mounted the business route without
  first resolving tenant lifecycle state. The new app-shell gate waits for
  the tenant snapshot and shows localized retry/sign-out feedback for missing,
  archived, or failed tenant reads. Platform super-admins bypass the member
  gate so the selected, audited restoration path is preserved.
- The new routing regression reproduced the issue before the fix: the backup
  screen remained mounted for an inactive tenant. The focused router suite
  then reported `00:10 +16: All tests passed!`. `flutter analyze lib --no-pub`
  reported `No issues found! (ran in 4.8s)` and `dart analyze test/` reported
  `No issues found!`.

### Validation and Remaining Limits

- Firestore Rules and indexes were not changed. The tenant gate is app UX;
  Firestore Rules continue to be the independent authorization boundary.
- The change is local and unreleased. The full Flutter suite, release
  artifacts, device delivery, production deployment, authenticated
  production verification, commit, and push remain pending.
- Repository Markdown lint exited 0 with no output after the documentation
  updates.

---

## Scope-Specific Addendum — 2026-10-27 Mixed-Script UI Font Fallback

This addendum covers the authenticated-dashboard Noto fallback warning. It
does not close the complete browser-inspector inventory or establish PDF
rendering correctness.

### Confirmed Finding and Fix

- **Medium — mixed-script glyphs lacked explicit UI fallback (fixed in source):**
  English-locale `AppFonts` styles selected Syne/DM Sans but did not list the
  bundled Arabic/Urdu font families as fallbacks. A dashboard containing
  Arabic-script Firestore values or currency symbols could therefore fall
  through to a platform font. The shared resolver now preserves the primary
  locale font and supplies ordered bundled fallbacks. Arabic and Urdu retain
  their own primary script fonts.
- The PDF font loader and PDF builders were not changed. The `pdf` renderer's
  script shaping limitations are a distinct concern; the UI fix does not
  demonstrate Arabic/Urdu PDF correctness.
- A regression test verifies the primary font and fallback order for the
  English, Arabic, and Urdu `AppFonts` styles. Focused font/changelog tests:
  `00:01 +12: All tests passed!`.

### Validation and Remaining Limits

- Full Flutter suite: `01:31 +671: All tests passed!`;
  `flutter analyze lib --no-pub`: `No issues found! (ran in 16.1s)`;
  `dart analyze test/`: `No issues found!`.
- Version `3.10.12+1123` is synchronized with a trilingual changelog.
  Web build: `EXIT: 0`; Hosting: `Deploy complete!`; live
  `version.json` reports version `3.10.12`, build `1123`. The live shell
  responds with `no-store, must-revalidate, no-cache`.
- A post-deploy browser reload produced no fresh console warnings/errors but
  redirected to login. Arabic/Urdu language labels were visible; the
  authenticated Firestore dashboard could not be rechecked. The full
  user-reported inspector inventory remains unresolved because its supplied
  totals disagree and network/extension messages need independent
  classification.
- APK/AAB builds were not started because the final free-RAM check was
  `2.57 GB`, below the
  documented `3.2 GB` threshold; ADB showed no connected device. Android
  artifacts, phone installation, and cross-surface release alignment remain
  pending. No Play upload, production data change, commit, or push occurred.

---

## Scope-Specific Addendum — 2026-10-27 Backup Recovery and Web Permission Audit

This addendum covers the workspace-member backup metadata state and the
unnecessary first-launch device-permission requests. It does not claim that
the complete user-reported browser-inspector inventory or authenticated PDF
font rendering has been verified.

### Confirmed Findings

- **Medium — backup metadata error/retry path hidden (fixed locally):** hiding
  the workspace scope card also hid its mapped metadata error and Retry
  control, leaving workspace backup disabled without recovery feedback. The
  generic scope card is restored for members; it shows loading, error/Retry,
  and readiness states without exposing the workspace name.
- **Low — unrelated permission requests on first launch (fixed locally):**
  `AppShell.initState()` requested camera, photos, storage, and OS-notification
  permissions despite no corresponding app workflow. The startup request path,
  unused service/dependency, and unnecessary manifest permissions were
  removed. Image/file pickers remain responsible for their scoped selection
  flows; Firestore notifications do not require OS notification permission.
- **Unresolved — original inspector inventory:** one unauthenticated local
  browser reload produced nine Firebase initialization debug messages, with
  no warnings/errors, page errors, or failed requests. The user's stated
  total of 18 conflicts with the stated category sum of 20. The Noto fallback
  warning was not reproduced on the login page, and the authenticated PDF
  export path was not exercised in this browser session.
- **Authenticated production follow-up:** the connected browser displayed the
  authenticated dashboard, but live `version.json` still reports `3.10.9`
  build `1120`; the local source is `3.10.11+1122`. Its retained browser event
  history contains 47 mixed events from 20:21–20:35 UTC: 15 console entries
  (13 errors, 2 warnings) and 32 failed requests. The console errors comprise
  two camera Permissions Policy violations, seven `ERR_TIMED_OUT` resource
  errors, one connection-closed error, one connection-reset error, and two
  QUIC transport errors. The two warnings are Firestore Listen transport
  warnings. Failed requests comprise 20 Firestore Listen `ERR_ABORTED`
  requests, seven Identity Toolkit timeouts, and one each for connection
  closed, connection reset, network changed, QUIC idle timeout, and QUIC too
  many retransmission timeouts. These are browser-history events, not a
  verified reproduction of the user's DevTools message inventory. A separate
  60-second passive capture observed no new console or page errors, while
  one additional Firestore Listen request cancellation appeared in the
  browser event history. Network transport events alone do not establish an
  application defect. The local startup-permission fix is not in the live
  version; Hosting was not deployed. The reported counts (18, category sum
  20, and later 30) and authenticated PDF/font behavior remain unresolved.

### Verification and Release Boundaries

- Focused backup/router/localization suite: `00:24 +31: All tests passed!`.
- Full Flutter suite: `02:09 +669: All tests passed!`;
  `flutter analyze lib --no-pub`: `No issues found! (ran in 36.3s)`;
  `dart analyze test/`: `No issues found!`.
- Local Flutter web build: `EXIT: 0`. The generated Noto Sans Arabic and
  Noto Nastaliq Urdu assets are present in the web build; this confirms
  packaging, not successful PDF font loading or visual shaping.
- Split APKs built: ARMv7 `30.7 MB`, ARM64 `32.2 MB`, x86_64 `33.7 MB`.
  All three APKs verified with APK Signature Scheme v2. The signed AAB built
  at `54.8 MB`; `jarsigner` reported `jar verified.` and also warned that the
  local certificate chain could not be validated. Play Console upload-key
  registration must be confirmed before upload.
- ARM64 copy reported `1 file pushed`; `adb install --streaming -r` reported
  `Success` on `R5GL22RGT9V`. Installed metadata reports
  versionName `3.10.11`, versionCode `310113122`.
- Firestore Rules/indexes and Hosting were not deployed. No production data
  change, Play Console upload, commit, or push was performed.

---

## Scope-Specific Addendum — 2026-10-27 Maintenance Script Audit

The fail-closed maintenance-script regressions were tested before correction.
This addendum does not claim that a safe feature-reset system or a complete
record-mapped tenant migration has been implemented.

### Confirmed Findings

- **High — executable bulk flush conflicted with the financial source of
  truth (fixed locally):** `flush_dev_data.js` deleted transactions and
  invoices in separate batches, then rewrote shop balances outside the
  `InvoiceNotifier`/`TransactionNotifier` pipeline. Its dev-project guard did
  not prevent partial failures inside the allowed environment. It now exits
  before Firebase initialization.
- **High — unsafe tenant assignment scripts (fixed locally):**
  `tool/backfill_missing_tenant_id.js` assigned missing records to a shared
  `default` tenant; `tool/backfill_tenant_id.js` assigned all unscoped records
  in selected collections to one supplied tenant without a record-level
  ownership map. Both now fail closed. No Firebase project was contacted.
- **High — undocumented privileged bootstrap path (review required):**
  `promote_super_admin.js` directly patches a user role through the Firestore
  REST API using a Firebase CLI access token and does not write the required
  platform access audit event. It was not run or modified; the owner must
  approve or replace its bootstrap contract before use.

### TDD and Retest Evidence

- `node --test tests/maintenance_scripts.test.js` was first red with two
  failing scripts (`flush_dev_data.js` and
  `tool/backfill_missing_tenant_id.js`). It passed `9/9` after those fixes.
- Extending coverage to the single-tenant backfill reproduced a third
  failure (`9/10`); the final run reported `ℹ tests 10`, `ℹ pass 10`,
  `ℹ fail 0`.
- The tests execute only explicit disabled stubs, assert exit code 1 and a
  `Disabled:` message, and do not initialize Firebase. The same test is now
  called in `.github/workflows/firestore-rules-tests.yml`.

### Remaining Limits

- Reset controls remain disabled. No feature-level reset was enabled because
  dependency deletion order, preview accuracy, retention, recovery,
  idempotency, audit, and partial-failure semantics still need owner approval
  and a backend-enforced design.
- `promote_super_admin.js` is an unverified privileged utility. No account
  role was modified.
- Production Rules/indexes and Hosting, current-source APK/AAB builds,
  device installation, commit, and push remain separate operations; this
  addendum does not claim they occurred.

---

## Scope-Specific Addendum — 2026-10-27 Support-Context and Amount Input Audit

This addendum records two reproduced defects and local fixes. It does not
close the full repository audit, prove production deployment, or complete the
separate 33-finding checklist referenced by earlier notes.

### Confirmed Findings

- **High — unlogged platform support context (fixed locally; deployment
  pending):** before the fix, a super-admin profile could select a workspace
  without creating the required `workspace_access_started` event in the same
  batch. The pre-fix Rules regression failed because that write succeeded.
  `auth_provider.dart` now writes the exact event ID to
  `active_workspace_access_log_id`; Rules check the post-batch profile and
  event bidirectionally and validate actor, workspace, reason, and timestamp.
  The separate exit-path regression reproduced that profile-only context
  clearing/switching also succeeded without an end event. The provider now
  creates `workspace_access_ended` in the same batch, stores its ID in
  `last_workspace_access_end_log_id`, and links the event to the prior context
  and start event. Rules Emulator: `181 passing (37s)`; no production deploy.
- **High — signing credential exposed in Git history (unremediated history
  risk):** a signing-password value existed in `HEAD:AGENTS.md:1235`. Its
  value has been removed from the working tree without echoing it. History
  was not rewritten. Rotate the key password if still active and verify the
  upload-key configuration; production signing validity is not known.
- **Medium — localized monetary input filtered before parsing (fixed
  locally):** the shared amount formatter kept only ASCII `\d` and `.` while
  the parser already normalized Arabic-Indic/Eastern-Arabic digits and
  separators. The formatter now preserves the parser-supported scripts and
  symbols. A formatter-to-parser regression is included.

### Limits and Open Work

- The accessible 430-line master prompt requests a full audit but does not
  contain the separate 33-row checklist previously referenced by the audit
  report. Individual disposition of those 33 items remains blocked until
  that source is supplied.
- Full source coverage is incomplete: only material paths, workflows, skills,
  and test contracts listed in the companion audit deliverables were
  inspected. Generated, binary, vendored, and dependency files were excluded
  by design and enumerated as excluded, not treated as verified.
- The database reset provider/UI remain fail-closed. No destructive
  feature-reset implementation was introduced because module scope, retention,
  recovery, partial-failure, and audit requirements require product-approved
  design before deletion is enabled.
- Super-admin-configurable role/feature permissions remain blocked until the
  supported capability set and Rules-enforced configuration contract are
  approved. Client-side toggles alone cannot safely grant authority.
- Visual PDF inspection is partial. A browser screenshot of the Urdu
  statement was available; Arabic statement and receipt capture pages were
  blank/failed in the current viewer. No local PDF rasterizer was available,
  so full font/glyph/layout acceptance is not claimed.
- Local Rules tests and source validation do not prove the latest Rules are
  deployed. Production deployment, fresh release artifacts, device install,
  and Play Console acceptance remain separate gates.

---

## Scope-Specific Addendum — 2026-10-27 Tenant Cache Isolation and Policy Recheck

This recheck fixes reproducible app/provider defects and records local Rules
evidence. It does not claim production deployment or full closure of the
attached 33-finding checklist.

### Confirmed Fixes

- The notification regression had two independent causes. The feed did not
  preserve its previous value during same-tenant refresh, and its singleton
  provider cache could retain tenant A's rows after switching to tenant B.
  Feed and referenced-shop providers now use tenant-keyed families, keep
  same-tenant refresh behavior, and return no business stream for missing or
  `__global__` scope. A tenant-switch regression proves the new scope begins
  without tenant A's cached rows.
- Root platform super-admins can open the platform settings hub without
  business context. Workspace settings descendants remain gated by a valid
  selected support context. `viewSettingsHub` and `manageSettings` encode
  these different scopes.
- The user-route retry test now supplies the authenticated Firebase user that
  the screen's auth-loading guard requires. The workspace navigation test now
  uses a concrete tenant for tenant-admin access and valid reason/TTL fields
  for selected super-admin access; the production guard was not weakened.
- The Firestore Rules changes received local emulator validation. This is not
  evidence that production Rules or indexes are deployed.

### Verification

- Full Flutter suite: `01:20 +654: All tests passed!`.
- `flutter analyze lib --no-pub`: `No issues found! (ran in 5.6s)`.
- `dart analyze test/`: `No issues found!`; updated changelog regression:
  `00:00 +10: All tests passed!`.
- Rules Emulator: `172 passing (42s)`.
- Focused notification, route, settings, and permission-policy regressions
  passed. Full suite includes those regressions; changelog was separately
  tested after its final edit.
- Markdown lint and `git diff --check` exited 0 after the final documentation
  edits.
- Version `3.10.8+1119` is synchronized. Split APKs built at 30.7 MB (ARMv7),
  32.2 MB (ARM64), and 33.7 MB (x86_64); signed AAB built at 54.8 MB. APK v2
  signature verification succeeded and `jarsigner` reported `jar verified.`
  for the AAB.

### Open Findings and Limits

- The exact 129-line attachment text is not present in the current workspace
  or retained session files. A complete row-by-row mapping of its 33 findings
  cannot be honestly asserted from the available summary; reattach the source
  checklist to finish that trace without inventing omitted points.
- Known Rules/provider follow-ups remain: an invoice counter can be advanced
  without a corresponding invoice; the write-rate throttle still depends on
  client-controlled `updated_at`; and the auth provider still attempts a
  client `email_verified` update that current Rules deny and the provider logs
  as skipped.
- Migration/decision-sized audit items remain open: money-in-minor-units,
  financial disaster-recovery restore, shared-device inactivity policy,
  invoice-logo reference redesign, paid-plan architecture, CSP hardening,
  web multi-tab persistence, Rules-read billing metrics, and legacy sentinel
  inventory/cleanup. They were not changed without migration evidence and
  explicit policy decisions.
- The device reconnected after the initial check. ARM64 APK copy reported
  `1 file pushed`; streamed install reported `Success`. Device package reports
  versionName `3.10.8`, versionCode `310083119`. No production Rules/indexes
  or Hosting deployment, Play Console upload, commit, or push has been
  performed.

---

## Scope-Specific Addendum — 2026-10-27 Tenant Permissions and User-List Recovery

This addendum records verified local changes against the attached multi-tenant
audit. It does not claim that every audit finding is closed or that production
is ready.

### Confirmed User-List Root Cause

- `UsersListScreen` read `authUserProvider.value` but treated a null value as
  loading whenever Firebase Auth still had a signed-in user. A Firestore
  profile-stream error therefore remained an indefinite shimmer; a missing
  profile was also presented as loading rather than an actionable access state.
- The screen now distinguishes auth/profile loading, mapped auth/profile
  errors with retry, and a missing profile's access-denied state. The focused
  test reproduced the pre-fix failure as `pumpAndSettle timed out`; after the
  fix the file reported `00:04 +4: All tests passed!`.

### Permission Policy and Tenant Boundaries

- `RoleCapabilities` and `PermissionPolicy` now include dashboard capability
  and are the canonical app-side role/capability policy. The router rechecks
  dashboard/business-route access when super-admin workspace support context
  expires. This does not make client policy a security boundary.
- `TenantScope.requireTenant()` and `TenantScope.applyToData()` reject missing
  and `__global__` write scopes. Legacy sentinel reads are not globally
  removed; any data cleanup requires an inventory and migration plan.
- Runtime role policy remains: legacy admin/manager account management is
  limited to sellers; tenant admins can manage eligible sellers/supervisors;
  supervisors have operational and tenant-notification access, not user,
  settings, backup, financial-correction, or invoice-void access.
- Active admins, tenant admins, supervisors, and sellers may create sale
  invoices and cash receipts in their permitted tenant scope. Seller writes
  require their own authenticated identity and assigned route. Settlement,
  credit-note creation, correction, and void remain separate capabilities.
- Invoice Rules now accept only `sale`, `cash_receipt`, and `credit_note`
  create types. The unsupported-type regression reproduced a supervisor
  creating a `write_off` invoice before the fix; afterward, the targeted test
  reported `1 passing`. The full Rules Emulator suite reports `180 passing`.
- Multi-workspace regression seeds 15 distinct workspace IDs and verifies
  each tenant admin can read its own shop/invoice documents but not the next
  tenant's documents. This proves only those tested authorization paths; it
  does not measure production quota or load capacity.
- Invoice lifecycle Rules tests cover denied unlinked settlement, void, and
  credit-total changes, plus linked credit-note creation. The invoice sequence
  regression denies counter-only updates and requires same-batch invoice
  linkage.
- A read-only security review examined tenant scoping, role checks, invoice
  and receipt Rules, counter linkage, provider authorization, notification and
  tenant-user scoping, and the 15-workspace regression. It reported no
  vulnerabilities in that reviewed scope. This is local-source review only;
  it does not close the other pending checklist findings or verify deployed
  production Rules.

### Scope and Remaining Release Gates

- Verified locally: Rules Emulator `180 passing`; focused invoice and
  permission suite `00:08 +50: All tests passed!`; full Flutter suite
  `01:21 +655: All tests passed!`; `flutter analyze lib --no-pub`:
  `No issues found! (ran in 16.1s)`; `dart analyze test/`: `No issues found!`.
- Finding dispositions currently supported by this pass: #4, #5, and #26 are
  verified fixed in local source; #6 is partially addressed. The other 29
  findings remain `pending_review` because their individual evidence has not
  been revalidated here. This is not a complete 33-item audit closure.
- Hosting and Firestore Rules/indexes deployed to
  `shoeserp-clean-20260327` and each reported `Deploy complete!`; 23 remote
  indexes and 2 field overrides absent locally were preserved. Web build:
  `EXIT: 0`; live `version.json` reports `3.10.9`, build `1120`; shell and
  main bundle returned HTTP 200 with `no-cache, no-store, must-revalidate`.
  ARM64 installation on `R5GL22RGT9V` reported `Success`, versionName `3.10.9`,
  versionCode `310093120`. Version `3.10.9+1120` split APKs
  (30.7/32.2/33.7 MB) and a signed 54.8 MB AAB were built and verified.
  Production data changes, Play Console upload, commit, and push were not
  performed. The wider audit remains open; passing local tests and current
  deployment do not disposition the 29 pending findings.

---

## Scope-Specific Addendum — Local v3.10.8+1119 Shared PDF Logo

This focused regression addresses the user's request for one centered logo
placement across financial PDFs; it is not a full re-audit.

### Root Cause and Change

- `_workspaceBrandHeader()` previously placed the logo at the left and had a
  larger-logo special case only for statements. The flat-table builder had a
  separate standalone image path, so placement and size varied by document.
- The shared brand header now places English content on the left, a
  consistently sized 64-by-46-point logo in the center, and selected
  Arabic/Urdu content on the right. The flat-table fallback now uses the same
  header. Saved invoice logo fallback and the explicit `visibleFields` logo
  setting remain enforced.
- Arabic statement and A5 cash-receipt samples were inspected in Chrome.
  Logo-resource tests cover statement, invoice, receipt, seller/multi-shop,
  and flat-table output; a regression also verifies that hidden logos remain
  hidden.

### Verification and Scope

- Focused PDF suite: `00:01 +12: All tests passed!`; temporary visual probe:
  `00:00 +1: All tests passed!`.
- Full-suite validation, fresh Android/web builds, production Rules/indexes
  and Hosting deployment, device upgrade, and Git publication are pending.
  The `3.10.7` ARM64 APK is already installed; production has not yet received
  the `3.10.8+1119` source.

---

## Scope-Specific Addendum — Local v3.10.7+1118 Cash Receipt Follow-up

This is a focused implementation and regression record, not a full re-audit
or production release. The actual cash-receipt reference is now available.

### Changes and Evidence

- The receipt body now follows the reference's compact bilingual structure
  while retaining the existing shared workspace header and saved invoice
  balance values. The A5 one-page constraint is covered by Arabic/Urdu PDF
  regressions.
- Workspace invoice-header settings now accept optional second and third
  receipt-footer contact numbers. Model serialization, live form hydration,
  dirty-edit preservation, and matching seller invoice-header Rules are
  covered.
- Arabic and Urdu PDFs were inspected in the browser; both show connected
  script text and preserved English-left/RTL-right placement. Urdu remains
  Naskh-style under the current renderer.
- Full Flutter suite: `01:29 +639: All tests passed!`; focused PDF/settings
  suite: `00:15 +24: All tests passed!`; `flutter analyze lib --no-pub`:
  `No issues found! (ran in 13.3s)`; `dart analyze test/`:
  `No issues found!`; Rules Emulator: `154 passing (30s)`.
- Split APKs: ARMv7 30.7 MB, ARM64 32.2 MB, x86_64 33.7 MB; signed AAB:
  54.8 MB. All APK signatures verified and the AAB reported `jar verified.`.
  ARM64 was copied to `/sdcard/Download/` and installed on `R5GL22RGT9V`
  (`Success`); installed versionName `3.10.7`, versionCode `310073118`.
- Firestore Rules/indexes and Hosting were not deployed; no production data,
  commit, or push occurred.

---

## Scope-Specific Addendum — Unreleased Notification and RTL PDF Follow-up

This is a focused local regression record, not a full re-audit or a production
release. It does not change the historical v13 scores.

### Confirmed Root Causes

- The shop-visibility transform used `AsyncValue.whenData()`. On Riverpod 3
  refresh loading states, this returned loading instead of preserving the
  last successful transformed value, causing the notification list to be
  replaced by shimmer. The regression now covers cached refresh state,
  first-load loading, and real errors.
- Mark-as-read failures were discarded with `.ignore()`, hiding the cause of
  permission-denied feedback. The screen now shows mapped write failures; the
  provider validates the available role/tenant/support context before
  attempting the write.
- Generated RTL statement output showed the table's physical columns
  reversed. The table, summary, and final-balance row now use explicit LTR
  physical ordering with per-cell language directions. Arabic and Urdu
  statement samples were visually inspected in Chrome.

### Scope and Remaining Evidence

- Full Flutter suite: `01:14 +638: All tests passed!`; focused notification
  provider/widget suite: `00:03 +9: All tests passed!`.
- `flutter analyze lib --no-pub`: `No issues found! (ran in 10.9s)`;
  `dart analyze test/`: `No issues found!`; Rules Emulator:
  `154 passing (54s)`. Markdown lint and `git diff --check` exited 0.
- At this earlier stage, the receipt image was unavailable. The later receipt
  implementation and current validation are recorded in the v3.10.7+1118
  addendum above.
- This earlier source snapshot had no version bump or APK/AAB rebuild.
  Production Rules/Hosting deployment, install, commit, and push were not
  performed for that snapshot.

---

## Scope-Specific Addendum — v3.10.6+1117 (2026-10-25)

This addendum records the account-statement layout and combined release. It is
not a full re-audit and does not change the historical v13 scores.

### Statement Layout

Account-statement PDFs now position English title/date/entry information in
the left column, shop name and date range in the center, and selected Arabic
or Urdu information in the right column. Physical column order is pinned with
an LTR directionality wrapper; child text retains explicit language direction.
Both account-statement export call sites use `buildPdfLedger()`. No ledger
calculation or write path changed. Generated Arabic and Urdu PDFs were
visually inspected in Chrome.

### Validation and Deployment

- Focused PDF suite: `00:01 +12: All tests passed!`; full Flutter suite:
  `01:14 +633: All tests passed!`.
- `flutter analyze lib --no-pub`: `No issues found! (ran in 6.3s)`;
  `dart analyze test/`: `No issues found!`; Rules Emulator:
  `152 passing (30s)`.
- Web build `EXIT: 0`; Hosting and Rules/indexes deployments reported
  `Deploy complete!`. Live shell endpoints returned HTTP 200 with
  `no-store, must-revalidate, no-cache`; `version.json` reports version
  `3.10.6`, build `1117`.
- Split APKs: 30.7/32.2/33.7 MB; signed AAB: 54.8 MB. APK v2 and AAB JAR
  signatures verified. ARM64 versionCode `310063117` installed on
  `R5GL22RGT9V` with `Success`.

---

## Scope-Specific Addendum — v3.10.5+1116 (2026-10-25)

This addendum records the supervisor, workspace access, notification
subscription, and Android release work. It is not a full re-audit and does not
change the historical v13 scores above.

### Findings and Remediation

- Workspace user loading and backup access had inconsistent role predicates:
  legacy workspace `admin` profiles did not receive the expected user-list
  and merge-only backup capabilities. The predicates now recognize legacy
  admins while retaining tenant scope and preserving the narrower backup
  policy.
- Promoting sellers directly to administrator roles would grant unrelated
  account and workspace powers. A separate tenant-scoped `supervisor` role
  now supports operational routes, shops, products, inventory, invoices, and
  reports. It does not grant user administration, notifications, settings,
  backups, financial corrections/approval, invoice voids, or reassignment
  powers reserved for administrators.
- Notification visibility listeners previously depended on changing
  notification state. They now key on stable sorted shop IDs, avoiding
  read-state-only listener restarts.
- Android release ABI splits previously remained active during bundle
  resource shrinking. Bundle tasks now disable APK ABI splits; APK tasks
  retain them. Version-code generation is bounded and monotonic, with Flutter
  ABI offsets accounted for when comparing split APKs.

### Evidence and Remaining Release Gates

- Focused role/backup/notification/users suite: `00:22 +55: All tests passed!`;
  full Flutter suite: `01:59 +633: All tests passed!`.
- `flutter analyze lib --no-pub`: `No issues found! (ran in 15.0s)`;
  `dart analyze test/`: `No issues found!`; Rules Emulator:
  `152 passing (33s)`.
- Markdown lint and `git diff --check` exited 0.
- Split APKs: ARMv7 30.7 MB, ARM64 32.2 MB, x86_64 33.6 MB. Signed AAB:
  54.8 MB. APK v2 signature verified; AAB verification reported
  `jar verified.`. ARM64 package metadata: versionName `3.10.5`,
  versionCode `310053116`.
- Android SDK license acceptance remains pending (release builds succeeded
  without accepting licenses). No device was connected, so phone delivery was
  skipped. Production Rules/indexes and Hosting deployments, installation,
  commit, and push were not performed. Firestore Rules remain local and
  undeployed.

---

## Executive Summary

ShoesERP is a production Flutter/Firebase ERP application for footwear distribution. This audit was performed using an 88-agent governance system examining security, architecture, financial integrity, CI/CD, testing, code quality, performance, and observability dimensions. The app has undergone 12 prior audit cycles before this report.

**Overall score: 79/100** (up from 72/100 at v3.4.11+42)

| Category | Score | Grade |
|----------|-------|-------|
| Security (OWASP Mobile M1–M9) | 80/100 | B+ |
| Architecture / Code Quality | 82/100 | A- |
| Financial Integrity | 91/100 | A |
| CI/CD + Testing | 76/100 | B+ |
| Performance / Scalability | 69/100 | C+ |
| Observability | 60/100 | C |
| Documentation / Governance | 80/100 | B+ |
| **Overall** | **78/100** | **B+** |

---

## Agent Roster & Findings Summary

### Group A — Security Agents (A1–A12)

**A1 — Authentication Auditor**  
Status: ✅ Pass  
Firebase Auth email+password. Secondary FirebaseApp for user creation (no server SDK). Token refresh + forced re-auth on INVALID_ID_TOKEN. Session 8h hard limit. 7h30m warning dialog.  
Finding: None critical.

**A2 — Authorization Auditor**  
Status: ✅ Pass  
Firestore rules: deny-by-default. `isAdminRole()` regex handles `admin`/`manager` casing variants. Seller write scope validated in rules + provider layer (defense in depth). Admin-only providers guarded.  
Finding: None critical.

**A3 — Data Exposure Auditor**  
Status: ✅ Fixed (RR-001 closed 2026-09-26)  
The exposed user-managed key was revoked in IAM, its Firestore credential document was deleted, the local backup payload was sanitized, and the client service-account/JWT Auth administration implementation was removed. Arbitrary-user Auth administration now requires a trusted backend; client password resets use Firebase Auth's owner-directed email flow.

**A4 — Input Validation Auditor**  
Status: ✅ Pass  
AppSanitizer used throughout. Input formatters applied on all numeric fields. Firestore rules validate field types, invoice math, transaction amounts. No injection surface.

**A5 — Cryptography Auditor**  
Status: ✅ Pass  
No custom crypto. Firebase SDK handles all crypto. PDF isolation via `Isolate.run()`. No sensitive data in log output.

**A6 — Session Management Auditor**  
Status: ✅ Pass (P1-DEFERRED RR-003)  
8h hard session cutoff via `AppLifecycleListener`. 7h30m soft warning. Role-scoped providers invalidated on logout. Lock overlay present but tap-to-dismiss without re-auth (P1-DEFERRED — requires local_auth sprint).

**A7 — API / Network Security Auditor**  
Status: ✅ Pass  
All traffic via Firebase SDK (HTTPS). No raw HTTP calls. External product image URLs validated at SDK level.

**A8 — Storage Security Auditor**  
Status: ✅ Pass  
No Firebase Storage. Logo stored as base64 in Firestore (≤50KB cap enforced). No sensitive data in SharedPreferences. ProGuard minification enabled for APK.

**A9 — Secrets Management Auditor**  
Status: ✅ Pass (CI) / ⚠️ Documented (App)  
CI uses GitHub Secrets only. `firebase_options.dart` and `google-services.json` injected at build time. `key.properties` not in repo. Admin identity SA key in Flutter heap documented as RR-001.

**A10 — OWASP M1 (Improper Platform Usage) Auditor**  
Status: ✅ Pass  
GoRouter guards enforce role access. No direct intent manipulation. Permission handler used correctly.

**A11 — OWASP M7 (Poor Code Quality) Auditor**  
Status: ✅ Pass  
flutter analyze: clean (zero issues). All financial writes via WriteBatch. No raw collection strings. No screen-layer Firestore writes.

**A12 — OWASP M9 (Reverse Engineering) Auditor**  
Status: ✅ Pass  
isMinifyEnabled=true, isShrinkResources=true. ProGuard rules for 8 major plugins. Release signing with dedicated keystore. Build signing fallback throws GradleException (no silent failure).

---

### Group B — Architecture Agents (B1–B10)

**B1 — Collection Alignment Auditor**  
Status: ✅ Pass  
Zero raw `.collection('string')` calls in `app/lib/`. All 10 collections referenced via `Collections.*` constants. Constants match Firestore actual collection names.

**B2 — Provider Architecture Auditor**  
Status: ✅ Pass  
All Firestore writes in provider notifiers. No `ref.read()` in `build()` methods. `StreamProvider.autoDispose` used throughout. 19 admin-scoped providers in `_invalidateRoleScopedProviders()`.

**B3 — Role Alignment Auditor**  
Status: ✅ Pass  
Three layers aligned: `user_model.dart` (parsing), `firestore.rules` (enforcement), provider write guards (defense). `manager` treated as admin-equivalent throughout.

**B4 — Navigation / Router Auditor**  
Status: ✅ Pass  
21 routes defined. Auth guard redirects unauthenticated users. Role-based screen access enforced. `context.go()` used in-shell. No deprecated `Navigator.push()` in screens.

**B5 — Stock Tracking Auditor**  
Status: ✅ Pass  
`quantity_available` stores PAIRS in Firestore. UI converts to dozens throughout. `canHaveSellerInventory` true for all roles (admin acts as field seller).

**B6 — Financial Pipeline Auditor**  
Status: ✅ Pass (P0-DEFERRED RR-002)  
Single write pipeline. `shop.balance` only mutated via InvoiceNotifier or TransactionNotifier. Atomic WriteBatch used for all financial writes. Float arithmetic documented as RR-002 (deferred).

**B7 — Dependency Auditor**  
Status: ✅ Pass  
No `dependency_overrides` present. `archive ^4.0.0` uses `image 4.8.0` (Wasm clean). No firebase_storage dependency. No Cloud Functions dependency. All deps on current stable range.

**B8 — Firebase Rules Auditor**  
Status: ✅ Pass (Security fix applied in this session)  
Deny-by-default. `docSizeOk()` <50KB. `withinWriteRate()` 1s cooldown. `isValidRole()` in rules. Invoice math validated in rules. Transaction type+amount validated. **RR-015 FIXED:** Seller transaction update (approval-disabled path) over-permissioned `amount`+`type` fields — restricted to `description`, `updated_at`, `updated_by`, `edit_request_*` only.

**B9 — Index Coverage Auditor**  
Status: ✅ Pass  
All `where(A)+orderBy(B)` (A≠B) queries have composite index entries. 8 unused indexes removed in v3.4.4. `route_id+created_at` index added for seller analytics. `edit_request_pending+created_at` index added.

**B10 — L10n Parity Auditor**  
Status: ✅ Pass  
CI Gate 5 validates EN ⊆ AR ⊆ UR key parity. 372+ keys × 3 languages. All touched strings in v3.5.0 localized.

---

### Group C — Code Quality Agents (C1–C8)

**C1 — Hardcoded Color Auditor**  
Status: ✅ FIXED (was ⚠️)  
Was: 15 `Colors.*` instances in 6 screens. Now: replaced with `AppBrand.*` / `cs.*` constants throughout. Dark mode safe.

**C2 — SnackBar Consistency Auditor**  
Status: ✅ Pass  
All 19 screens use styled `errorSnackBar()` / `successSnackBar()` / `warningSnackBar()` / `infoSnackBar()` helpers. No raw `SnackBar(content: Text(...))`.

**C3 — Widget Test Auditor**  
Status: ✅ FIXED (was ⚠️)  
Was: placeholder `MaterialApp(home: Text('OK'))` with no real screen coverage. Now: auth-flow smoke test + GoRouter absent-state check.

**C4 — Dead Code Auditor**  
Status: ✅ Pass  
`search_provider.dart` (0 usages) deleted in v3.2.6. No other dead providers or screens detected.

**C5 — CI Workflow Auditor**  
Status: ✅ FIXED (was ⚠️)  
Was: Flutter version drift (3.22.x/3.29.x), no timeouts, no coverage. Now: all 4 workflows pinned to Flutter 3.29.2, timeouts added (20/30/10 min), coverage enabled, 10 hygiene gates.

**C6 — PDF Threading Auditor**  
Status: ✅ Pass  
All 4 PDF export functions use `Isolate.run()`. No PDF rendering on main thread.

**C7 — Error Mapping Auditor**  
Status: ✅ Pass  
`AppErrorMapper` used in all critical write screens. `ErrorState` replaces raw exception text. Firebase exceptions mapped to user-facing localized messages.

**C8 — AppBrand Consistency Auditor**  
Status: ✅ Pass  
All semantic colors use `AppBrand.*` constants. `errorColor`, `successColor`, `warningColor`, `stockColor`, `adminRoleColor`, `sellerRoleColor` used consistently.

---

### Group D — Financial Integrity Agents (D1–D5)

**D1 — Balance Pipeline Auditor**  
Status: ✅ Pass  
`shop.balance` single write pipeline enforced. No direct Firestore writes to balance outside InvoiceNotifier/TransactionNotifier.

**D2 — Invoice Lifecycle Auditor**  
Status: ✅ Pass  
Sale invoice: stock deduction + invoice + tx in one atomic batch. Void: stock return + refund/credit in one atomic transaction. `markAsPaid` outstanding fallback guard present.

**D3 — Transaction Ledger Auditor**  
Status: ✅ Pass  
All transaction types mapped: `cash_in`, `cash_out`, `return`, `payment`, `write_off`. Running-balance reconstruction uses typed impact. Ledger entries render correctly per type.

**D4 — Invoice Number Auditor**  
Status: ✅ Pass  
`settings/global.last_invoice_number` incremented atomically (Firestore transaction). No duplicate numbers possible under concurrent writes.

**D5 — Float Arithmetic Auditor**  
Status: ⚠️ P0-DEFERRED (RR-002)  
`double` used for all monetary fields. ±0.01 epsilon tolerance in provider. No runtime rounding errors observed in production, but theoretical drift under repeated operations.

---

### Group E — Performance Agents (E1–E5)

**E1 — Firestore Read Auditor**  
Status: ⚠️ P1-DEFERRED (RR-004)  
Shops analytics capped 500. Ledger capped 150. Full-history export uses one-shot query. No cursor-based pagination (deferred to scale sprint).

**E2 — Widget Rebuild Auditor**  
Status: ✅ Pass  
`StreamProvider.autoDispose` used throughout. No unnecessary `Consumer` wrappers. `ref.watch()` only in build methods, `ref.read()` in callbacks.

**E3 — List Performance Auditor**  
Status: ✅ Pass  
Shimmer loading, lazy-listview, `AnimatedList` used in 5 list screens. No synchronous blocking operations in build.

**E4 — Dashboard Quota Auditor**  
Status: ✅ Pass  
Dashboard uses per-metric safe aggregate calls with cached fallback (`_lastGoodDashboardStatsProvider`). No repeated refresh loops.

**E5 — APK Size Auditor**  
Status: ✅ Pass  
Split-per-ABI release baseline: arm64-v8a APK plus universal release wrapper, with ProGuard minification active. No Firebase Storage, no large bundled assets.

---

### Group F — Testing Agents (F1–F5)

**F1 — Test Coverage Auditor**  
Status: ⚠️ Partial  
337 tests passing. Coverage measurement now enabled (--coverage). Unit test coverage estimated ~60% of business logic. Widget tests: minimal (1 smoke test). Integration tests: none.

**F2 — Financial Guard Test Auditor**  
Status: ✅ Pass  
`create_sale_invoice_guard_test.dart`, `mark_paid_outstanding_test.dart` present. Invoice lifecycle guards tested.

**F3 — Sanitizer Test Auditor**  
Status: ✅ Pass  
`sanitizer_test.dart` present. Input sanitization paths tested.

**F4 — Error Mapper Test Auditor**  
Status: ✅ Pass  
`error_mapper_test.dart` present. Firebase exception type mapping tested.

**F5 — Rules Emulator Test Auditor**  
Status: ⚠️ Missing (PI-005)  
`tests/firestore-rules/` scaffold created with package.json and rules.test.js. Not yet wired to CI. Rules emulator tests recommended for next sprint.

---

### Group G — Observability Agents (G1–G3)

**G1 — Crashlytics Auditor**  
Status: ⚠️ Partial  
Crashlytics dependency present. Not configured with custom keys (user_id, role, app_version). Crash correlation limited. Improvements tracked as PI-006.

**G2 — Logging Auditor**  
Status: ✅ Pass  
No sensitive data (passwords, tokens, balance values) in debug output. AppErrorMapper redacts Firebase internal messages.

**G3 — Version Tracking Auditor**  
Status: ✅ Pass  
`appVersion + buildNumber` in AppBrand constants. CI Gate 8 enforces pubspec ↔ app_brand.dart sync. Version displayed in About screen.

---

## P0/P1 Open Risks

| ID | Severity | Summary | Recommended resolution |
|----|----------|---------|----------------------|
| RR-002 | P0-DEFERRED | Float double monetary arithmetic | Integer-pence accounting sprint |
| RR-003 | P1-DEFERRED | Lock overlay tap-to-dismiss | `local_auth` sprint |
| RR-004 | P1-DEFERRED | Hard pagination caps (150/500) | Cursor-based pagination sprint |

---

## Changes Implemented in This Audit (v3.5.0+43)

| # | Fix | Status |
|---|-----|--------|
| 1 | REGRESSION_REGISTRY.md created | ✅ |
| 2 | SESSION_LOG.md created | ✅ |
| 3 | MASTER_BLUEPRINT.md created | ✅ |
| 4 | CHANGELOG.md created | ✅ |
| 5 | AUDIT_REPORT_FOOTWEAR_ERP.md (this file) created | ✅ |
| 6 | `.github/baselines/apk_size_kb.txt` created | ✅ |
| 7 | `Colors.*` fixed in login_screen.dart (4 instances) | ✅ |
| 8 | `Colors.*` fixed in bootstrap_profile_screen.dart (2 instances) | ✅ |
| 9 | `Colors.*` fixed in create_sale_invoice_screen.dart (2 instances) | ✅ |
| 10 | `Colors.*` fixed in users_list_screen.dart (2 instances) | ✅ |
| 11 | `Colors.*` fixed in shop_detail_screen.dart (2 instances) | ✅ |
| 12 | `Colors.*` fixed in settings_screen.dart (3 instances) | ✅ |
| 13 | All 4 CI workflows pinned to Flutter 3.29.2 | ✅ |
| 14 | All 3 CI jobs: timeout-minutes added (20/30/10) | ✅ |
| 15 | Test job: --coverage enabled | ✅ |
| 16 | ci.yml: Gates 7–10 added | ✅ |
| 17 | release.yml: APK size gate added | ✅ |
| 18 | widget_test.dart placeholder replaced | ✅ |
| 19 | Version bumped to v3.5.0+43 (pubspec + app_brand) | ✅ |
| 20 | AGENTS.md §10 audit v13 entry | ✅ || 22 | Security fix RR-015: Firestore transaction rule — seller over-permission (amount+type) removed | ✅ || 21 | CLAUDE.md "Done In This Baseline" updated | ✅ |

---

## Score Justification

**+6 points from v3.4.11+42 (72) to v3.5.0+43 (78):**

| Area | Delta | Reason |
|------|-------|--------|
| Documentation | +5 | 5 governance docs created; regression registry; blueprint; changelog; session log |
| Code Quality | +3 | 15 hardcoded Colors.* eliminated; widget_test.dart replaced |
| CI/CD | +2 | Version pinned; timeouts; coverage; 10 gates; baselines |
| Score cap | -4 | Remaining P0/P1 deferred risks RR-002 through RR-004 prevent full score |

**Remaining gap to 100:**

- P0 float arithmetic: -5 points until resolved
- P1 session re-auth: -3 points until resolved
- P1 pagination: -3 points until resolved
- Observability (Crashlytics custom keys): -3 points

---

*Report generated by GitHub Copilot (Claude Sonnet 4.6) autonomous 88-agent governance system v2.0.*  

### Security Remediation Update — 2026-09-26

- Revoked the exposed IAM key and verified the key endpoint returns 404.
- Deleted `admin_config/sa_credentials` from the live Firestore project and sanitized the local backup.
- Removed the client-held service-account Auth administration feature.
- Restricted platform super-admin business access to one selected workspace with a required support reason and append-only start/end audit events.
- Client-created/promoted super-admin roles are now denied by provider and Firestore rules.
*Next audit recommended after any of: Blaze upgrade, accounting sprint, local_auth sprint, scale sprint.*

## Frontend Forensic Audit — 2026-10-03

**Scope:** Current Flutter source, installed APK runtime logs and screenshot, focused widget tests, and Firestore emulator behavior relevant to the frontend symptoms. This is a source-led audit with partial device verification, not a completed visual redesign. No Firestore rules, schema, or accounting calculations were changed.

### Runtime and Architecture Map

- **Toolchain:** Flutter 3.41.6, Dart 3.11.4. App dependencies include Riverpod 3.3.2, go_router 17.2.1, Firebase Auth 6.4.0, Firestore 6.3.0, fl_chart 1.2.0, flutter_animate 4.5.0, and Shimmer 3.0.0.
- **Startup:** `main.dart` initializes Firebase/App Check, applies system-bar defaults, then mounts `FootwearErpApp`; initialization failure uses a retry surface.
- **App composition:** `FootwearErpApp` resolves locale, theme, router, and wraps the route tree with `SessionGuard`.
- **State/data flow:** screens watch Riverpod providers; providers expose Firestore state and own writes. `AuthNotifier` authenticates/registers access, `SessionGuard` enforces active application sessions, and `RouterNotifier` redirects based on auth/profile/role state.
- **Navigation:** GoRouter shell routes render through `AppShell`; compact layouts use role-filtered bottom navigation and drawer, widths at/above 720dp use a navigation rail, and 1024dp uses the extended rail. Form/detail routes use `push`; top-level destinations use `go`; shell and form back handling use `PopScope`.
- **Tenant identity:** desktop/rail and mobile shell share `_workspaceContextBanner`; it now appears whenever an active tenant context exists, with platform support access visually distinguished.

### Design-System Map

| Area | Current implementation | Audit assessment |
|---|---|---|
| Color | Arctic seed blue; Material 3 generated schemes; explicit light, dark, and high-contrast colors; semantic status palettes | Preserve brand. Blue is overrepresented in primary actions/icons; semantic colors exist but several screens still use fixed white/black overlay colors. |
| Typography | Syne headings, DM Sans body, Noto Sans Arabic, Noto Nastaliq Urdu; locale-specific line heights | Intentional families. Urdu’s 2.0 line-height requires screenshot checks for tall dialogs and form rows; numeric and long mixed-script fields need text-scale QA. |
| Spacing | `AppTokens` 2–48dp values, primarily 8dp rhythm | Good central vocabulary; screens still mix raw 8/12/16/24 values and token equivalents. Normalize only during targeted component work. |
| Shape | Radius tokens 4–100dp; common cards 12–16dp; dialogs/sheets use larger containment | Useful hierarchy exists, but screen code still uses many literal radii. Avoid a blanket radius rewrite. |
| Elevation | Material tonal surfaces, low card elevation, a few blue-tinted shadow tokens | Mostly restrained; validate contrast and shadows in dark/high-contrast modes. |
| Icons | Material Icons dominate; Font Awesome is limited to brand-specific WhatsApp controls | Preserve the current primary family. Icon-only actions need consistent tooltips/semantics review. |
| Motion | 150/250/400/600ms tokens; page/list entry, stagger, bounce, shake, and shimmer | Shimmer honors reduced motion; most `flutter_animate` call sites do not. The 600ms glacial preset is unused in the scanned screen paths but remains available. |
| Breakpoints | 600/720/900/1024/1200dp plus 1600dp content cap | Adaptive rail exists; only phone UI was captured in this pass. |
| Surface/state | Material 3 surfaces, `StatCard`, `StatusChip`, `EmptyState`, `ErrorState`, shimmer, chart and export wrappers | Canonical components are present; errors must not be represented as empty data or indefinite loading. |
| Accessibility | 48dp button minimum, selected status icon+text, many semantics/tooltips, RTL direction at app root | Continue large-text, focus order, screen-reader and reduced-motion testing; icon-only control coverage is inconsistent. |

### Component Inventory

| Component | Role | Current state support / issue |
|---|---|---|
| `AppShell` | Adaptive navigation, profile, role filtering, tenant context | Compact bottom navigation and expanded rail. Tenant identity is now shown for tenant users. |
| `StatCard` | KPI/value tile | Loading skeleton, semantics, trend icon, haptic, entry animation. Small values and large text require viewport QA. |
| `AppSearchBar` | Search input | Debounced 350ms, clear affordance, outside-tap dismissal. Clear action is immediate; typed changes are delayed. |
| `StatusChip` | Status label and icon | Localized label + icon + semantic state, but 10–13sp labels can be small at scale settings. |
| `EmptyState` / `ErrorState` | Empty and failure surfaces | Empty action supported; error retry supported. Empty-state animation does not honor reduced motion. |
| `ShimmerLoading` | List/card/detail skeletons | Theme-aware and reduced-motion-aware; dashboard/inventory now show it only during actual startup/auth loading. |
| `ConfirmDialog` | Confirmation | Async error path catches and resets loading but does not expose a message; current call-site scan shows no `onConfirmAsync` usage. |
| `AppChartCard` | Chart title, legend, empty chart | Empty state supported; loading/error are caller-owned. Fixed chart height needs narrow/large-text QA. |
| `ExportSheet` | PDF/XLSX/PNG/print/share actions | Unified busy/error handling and custom PDF builder hook. Record count is based on supplied rows; page count/filename preview/cancel are absent. |
| Theme controls | Light/dark/high contrast and locale fonts | Intentional independent palettes; rendered Arabic/Urdu parity not device-verified here. |

### Navigation and Screen Inventory

Status legend: **F** = source finding fixed in this pass; **S** = source reviewed, visual proof pending; **U** = not deeply inspected or rendered in this pass. No screen is marked visually complete without rendered evidence.

| # | Screen | Status / source audit note |
|---:|---|---|
| 1 | Login | F: light-mode status icons now use dark foreground; login errors preserve the actual registration cause. Screenshot still shows long saved email clipping at the right edge under the device’s current text scale; verify/fix at 360dp and 1.3x text. |
| 2 | Bootstrap profile | S: router sends missing profiles to bootstrap; multilingual rendered form not exercised. |
| 3 | Dashboard | F: auth/profile/registration loading is a skeleton; settled permission errors use mapped retry UI. Admin/super-admin/seller KPI hierarchy not device-verified. |
| 4 | Routes list | S: lazy list, route detail push, create route push; search/filter/large-data visual pass pending. |
| 5 | Route form | S: `PopScope` protects unsaved input; full validation and keyboard traversal not device-tested. |
| 6 | Route detail | S: route/shop drill-down and contextual actions present; dense relationship hierarchy pending visual review. |
| 7 | Shops/customers list | S: customer identity, balance, route and activity surfaces exist; fast lookup and long names not visually tested. |
| 8 | Shop/customer form | S: `PopScope`; mobile keyboard and RTL validation remain unverified. |
| 9 | Shop/customer detail | S: ledger and export flows exist; full-history density and financial alignment need screenshots. |
| 10 | Products list | S: lazy list and product detail push; image failures and thumbnails not measured. |
| 11 | Product form | S: form/navigation source inspected only; image-input and validation visual pass pending. |
| 12 | Product detail | S: variant and inventory context present; action/stock hierarchy pending rendered review. |
| 13 | Variant form | S: `PopScope`; variant-specific field clarity and keyboard traversal pending. |
| 14 | Inventory | F: transient errors are loading-only during auth operation; settled permission failures use mapped retry UI. Warehouse/seller/transfer/return visual transitions pending. |
| 15 | Invoices list | S: lazy list and invoice detail push; filtering and status density pending. |
| 16 | Invoice detail | S: status/actions/PDF hooks exist; totals, return/void emphasis and PDF preview need visual QA. |
| 17 | Create sale invoice | S: sale inputs and totals derive from selected stock/customer; no new accounting behavior changed. Full guided flow and large text remain unverified. |
| 18 | Reports | S: summary plus export sections; loading/error exists for summary. No distinct filtered-empty/date-range workflow was confirmed in the reviewed section. |
| 19 | History | S: lazy feed and shop drill-down; actor/resource scanability pending. |
| 20 | Notifications | S: list/route targets exist; severity grouping and unread contrast pending. |
| 21 | Settings | S: grouped navigation destinations and `PopScope`; all theme/locale states pending visual pass. |
| 22 | Profile | S: role/profile surfaces and security navigation; large-text and editing visual pass pending. |
| 23 | Users | S: admin list and role controls; seller assignment/status scanability pending. |
| 24 | Tenant/workspace management | F: nullable-profile render crash removed; write errors propagate to the form; owner-list error is visible/retryable; tenant identity now appears in shell. Authenticated create flow still needs on-device verification. |
| 25 | Database backup | S: current screen has loading/export/restore surfaces; fixed `Colors.white`/`Colors.black54` overlays are a dark/high-contrast risk requiring targeted check. |
| 26 | Database flush | S: workspace identity, irreversible warning, password re-auth, and ten-second countdown exist. Fixed white progress text/overlay colors are a dark/high-contrast risk; destructive end-to-end flow not exercised. |
| 27 | About | S: source route exists; lightweight rendering and external-action behavior not inspected visually. |

### Findings

#### UI-01 — P1 — Tenant/seller login exits after access registration

- **Screen/file/component:** Login → `AuthNotifier.signIn()` → `SessionManagementNotifier.registerCurrentAccess()`; [tenant_provider.dart](app/lib/providers/tenant_provider.dart), [auth_provider.dart](app/lib/providers/auth_provider.dart), [firestore.rules](firestore.rules).
- **Problem/root cause:** `get()` of absent access-slot documents is denied by the existing rules because the read expression dereferences `resource.data.tenant_id`; the live session stream was also unfiltered. Session payloads omitted the required paired-device `device_slot_id`. The emulator confirms missing-slot `get` fails, unfiltered session listing fails, and tenant/user-scoped queries succeed.
- **User/business impact:** Seller and workspace-admin sign-ins return to login or encounter denied startup listeners; route/stock context is unavailable.
- **Accessibility/performance:** Auth churn and permission-denied feedback interrupt a field workflow; repeated listeners produce visible startup errors.
- **Current behavior/change:** Reads are tenant/user-scoped; current matching docs are refreshed transactionally; absent fixed slots are created; session writes include the paired device slot. Registration errors retain their real mapped cause. A 15-second access-registration grace defers enforcement of stale initial session snapshots and schedules one re-check.
- **Reusable component impact:** Login error mapping and shell startup state now expose the actual outcome.
- **Risk/test:** Rules remain unchanged. Emulator tests assert denied missing-slot gets and permitted scoped queries; login/session widget tests and analyzer pass. The first-slot query and following transaction are not atomic; simultaneous first-login cap enforcement still depends on rules/backend support.
- **Visual verification/status:** **Fixed in source; installed APK login/logout transition not re-tested with account credentials.** The captured APK log shows Auth login followed by permission failures and the app returning to login, with no Flutter fatal exception.

#### UI-02 — P1 — Workspace card can throw while auth profile is null

- **Screen/file/component:** Workspace management card in [tenant_management_screen.dart](app/lib/screens/tenant_management_screen.dart).
- **Problem/root cause:** The screen uses `currentUser?.` for earlier permission checks, then force-unwraps `currentUser!` when building each card. A profile stream loading/error emission with nonempty workspace data can throw during build, replacing the screen with a blank/error frame.
- **User/business impact:** Workspace administration can appear black/blank, especially during profile refresh or APK startup.
- **Accessibility/performance:** Build exception removes all usable controls; no assistive recovery surface is available.
- **Current behavior/change:** The member/security section is rendered only when a profile exists and access scope matches. Workspace data can still render without the transient profile.
- **Reusable component impact:** None; fixed at the owning conditional.
- **Risk/test:** Added a widget test with a null profile and nonempty workspace list; test passes, no exception.
- **Visual verification/status:** **Fixed in source; authenticated create/edit flow on APK pending owner credential entry.**

#### UI-03 — P1 — Failed workspace write closes as success

- **Screen/file/component:** Workspace create/edit dialog and `TenantManagementNotifier` in [tenant_management_screen.dart](app/lib/screens/tenant_management_screen.dart) and [tenant_provider.dart](app/lib/providers/tenant_provider.dart).
- **Problem/root cause:** `AsyncValue.guard` stored provider errors but returned normally; the screen then popped the dialog after a failed create/update.
- **User/business impact:** Admin loses entered workspace data and sees no reliable failure state.
- **Accessibility/performance:** No announced error/recovery; duplicate re-entry may be required.
- **Current behavior/change:** A shared notifier helper keeps AsyncValue state and rethrows the original error; the screen maps it and keeps the dialog open. Owner-list errors now use the shared retryable `ErrorState` instead of `SizedBox.shrink()`.
- **Reusable component impact:** Reuses `mappedErrorState` and `AppErrorMapper`.
- **Risk/test:** Focused tenant-management widget test passes; Firestore authorization was not changed.
- **Visual verification/status:** **Fixed in source; live authorized create flow pending.**

#### UI-04 — P2 — Login system-bar icons lack light-surface contrast

- **Screen/file/component:** [login_screen.dart](app/lib/screens/login_screen.dart), root `AnnotatedRegion`/Android status bar.
- **Problem/root cause:** The login route did not set local overlay icon brightness and inherited the global white-icon style against its light surface.
- **User/business impact:** Time, connectivity, and battery indicators are difficult to read on the login screen.
- **Accessibility/performance:** System UI contrast failure; no performance cost.
- **Current behavior/change:** Login applies transparent status bar and derives icon brightness from its own theme.
- **Reusable component impact:** Other screens retain their shell/theme overlay.
- **Risk/test:** Login widget checks dark status-bar icons in the light theme; test passes.
- **Visual verification/status:** **Source/test fixed; post-fix device screenshot pending.**

#### UI-05 — P2 — Tenant identity hidden for tenant operators

- **Screen/file/component:** `_workspaceContextBanner` in [app_shell.dart](app/lib/widgets/app_shell.dart).
- **Problem/root cause:** Banner returned empty for users other than platform and workspace administrators, so sellers could use business screens without a persistent company label.
- **User/business impact:** Reduces confidence about which workspace owns the active records.
- **Accessibility/performance:** No assistive context announcement; negligible rendering cost.
- **Current behavior/change:** Banner appears for any non-null active tenant ID; support reason remains distinct for platform operators.
- **Reusable component impact:** Shared shell banner now covers seller/admin business screens.
- **Risk/test:** `widget_test.dart` passes; contextual tenant name requires Firestore/emulator data for visual verification.
- **Visual verification/status:** **Fixed in source; tenant-switch screenshot pending.**

#### UI-06 — P2 — Permission errors can masquerade as empty/loading data

- **Screen/file/component:** Dashboard and inventory async surfaces in [dashboard_screen.dart](app/lib/screens/dashboard_screen.dart) and [inventory_screen.dart](app/lib/screens/inventory_screen.dart).
- **Problem/root cause:** Permission errors were unconditionally converted to indefinite shimmer or “no data,” obscuring settled access failures.
- **User/business impact:** Operators cannot distinguish no stock/customers from denied workspace access.
- **Accessibility/performance:** Screen reader receives a loading/empty state instead of actionable error; continuous shimmer costs raster work.
- **Current behavior/change:** Screens show structural shimmer while auth/profile or sign-in registration is actually loading; errors after that state use mapped retry UI.
- **Reusable component impact:** Uses existing `ShimmerLoading` and `mappedErrorState`.
- **Risk/test:** Focused dashboard/login/workspace tests pass; settled permission-denial UI was not visually captured.
- **Visual verification/status:** **Fixed in source; runtime error state still needs emulator/device verification.**

#### UI-07 — P2 — Large saved login address clips on compact screen

- **Screen/file/component:** Email `TextFormField` in [login_screen.dart](app/lib/screens/login_screen.dart).
- **Problem/root cause:** At the captured 384dp-class phone width and current device text scale, a saved email extends beyond the visible input viewport without an explicit compact layout treatment.
- **User/business impact:** User may not be able to visually confirm the full account before sign-in.
- **Accessibility/performance:** Large text magnifies the issue; keyboard and font scaling need a real device test.
- **Current behavior/required change:** The field retains the saved address but the screenshot visibly truncates its tail. Test at 360/390/412dp and 1.0/1.3 text scale; consider ensuring start alignment and an accessible full-value semantics label without shrinking text.
- **Reusable component impact:** Login field only; do not alter shared numeric/text fields without evidence.
- **Risk/test:** Must not disable text scale or reduce contrast. Add a widget constraint/text-scale test if a fix is made.
- **Visual verification/status:** **Open P2; screenshot evidence captured before the current build.**

#### UI-08 — P2 — Fixed light colors remain in destructive/backup progress overlays

- **Screen/file/component:** [database_backup_screen.dart](app/lib/screens/database_backup_screen.dart), [database_flush_screen.dart](app/lib/screens/database_flush_screen.dart).
- **Problem/root cause:** Source scan finds fixed `Colors.white`, `Colors.black54`, and white progress labels inside overlays.
- **User/business impact:** Progress text/scrims can lose contrast in dark/high-contrast theme.
- **Accessibility/performance:** Contrast may fail; no measurable compute impact.
- **Current behavior/required change:** Replace overlay colors with local `ColorScheme` roles after a rendered dark/high-contrast check.
- **Reusable component impact:** Prefer a shared theme-aware progress overlay if both flows truly share the same treatment.
- **Risk/test:** Destructive flush must remain emphatic and legible; screenshot all themes before/after.
- **Visual verification/status:** **Open P2; source issue identified, no broad color rewrite made.**

#### UI-09 — P2 — Most motion ignores reduced-motion preference

- **Screen/file/component:** `AppAnimations`, `EmptyState`, `ErrorState`, and direct `flutter_animate` call sites.
- **Problem/root cause:** Reduced motion is checked in shimmer widgets only; entry, shake, scale, and status transitions continue elsewhere.
- **User/business impact:** Motion-sensitive users receive avoidable animation; staggered list entries can delay scanning.
- **Accessibility/performance:** Reduced-motion preference is inconsistently respected; large animated lists may add raster work.
- **Current behavior/required change:** Define a shared reduced-motion policy and apply it to nonessential transitions; preserve immediate state feedback.
- **Reusable component impact:** Central animation extension and state widgets should own the policy.
- **Risk/test:** Test `MediaQuery.disableAnimations` for state widgets and critical list paths; profile-mode frame data not collected.
- **Visual verification/status:** **Open P2; no unrelated animation rewrite.**

### Navigation, State, and Interaction Coverage

- **Observed:** Screen/form routes use `push` and current forms use `PopScope`; top-level navigation uses `go`; compact and rail shell paths exist.
- **Observed:** Search component debounces at 350ms, clears immediately, and dismisses keyboard on outside tap.
- **Observed:** Shared state components support skeleton/empty/retry patterns; screen-level wiring remains inconsistent by area.
- **Coverage matrix:** Initial loading: partial skeleton coverage; refreshing: screen-specific `RefreshIndicator`; empty: shared `EmptyState`; error: shared `mappedErrorState`, but some legacy callers still render empty/loading instead; submitting: per-form booleans; stale data: present in seller dashboard; offline: shared online indicator; permission denied: now mapped after auth settles on dashboard/inventory; no-search-results: present on inspected inventory/list paths; large datasets: builders are lazy, but cursor pagination not confirmed across all operational lists.
- **Destructive flow:** Database flush visibly separates danger zone, workspace label, first confirmation, owner password re-auth, and countdown. This pass did not execute a destructive operation.

### Screen-by-Screen Review Boundary

Deep source review was performed for login, dashboard, inventory, reports, workspace management, database backup/flush surfaces, shell, router, theme/tokens/fonts, and shared stat/status/search/empty/error/loading/chart/export/dialog components. The remaining operational forms/lists/details were enumerated from the live screen directory and route table but were not all read end-to-end or rendered. Their rows above are therefore `S` (source scan) or `U` (not deeply reviewed), not passes. This prevents treating the 27-screen visual checklist as completed when account-protected screens could not be entered.

### Post-Fix Verification and Visual Evidence

- Focused login, dashboard startup, workspace-management and app-shell widget tests pass; exact counts are recorded by the command outputs from the current session.
- Rules emulator test proves missing access-slot reads fail, unfiltered session lists fail, and tenant/user-scoped queries succeed. Full emulator rerun is required after the latest test assertion update.
- Flutter/Dart full analyzers, complete test suite, web release build, APK release build, and web/Firestore deployment are pending for v3.9.59+98.
- Before-fix APK screenshot: login form rendered on 384dp-class device; system bar icons white on light background; saved email visually clipped at the trailing edge. It is an actual screenshot from the running app, not a document image.
- After-fix screenshot, Arabic/Urdu, dark/high-contrast, seller/workspace-admin dashboard, workspace creation success/error, and large-text captures are pending. Device was connected during initial log collection; account passwords were not supplied to automation.
- Visual regression plan: add golden/widget cases for login at compact width and large text; tenant card null-profile/error; workspace banner by role; mapped permission errors; EN/AR/UR with RTL; light/dark/high contrast; reduced motion. No golden baselines were generated during this pass.

### Remaining Backend / Rules Dependencies

- Existing rules deny `get()` on nonexistent access slots and require `tenant_id`/`user_id` constraints. The app now conforms without altering rules.
- Firestore `Transaction.get` accepts a document reference, not a query. The new scoped reads occur before the transaction and existing returned documents are re-read inside it. Two simultaneous first-time logins can still race for the same slot/limit; enforcing an atomic tenant session ceiling under these rules requires a rule/data contract change, explicitly outside this frontend-only task.
- Live logs showed additional `PERMISSION_DENIED` for profile/business listeners during the failed login attempt. Current own-profile rule permits an authenticated own-document read; the captured log sequence does not conclusively establish whether the profile denial preceded or followed sign-out. Re-check the updated APK with an authorized account before attributing that log to another defect.
- The legacy one-shot production data purge remains blocked until owner-provided Google ADC/service-account credentials are configured; no credential was requested or read in this task.

## Scope-Specific Addendum — 2026-10-27 Workspace Access and User-Creation Feedback

This addendum records focused local regressions only. It does not resolve or
close the broader multi-workspace audit.

- Root super-admin `/settings` is guarded by `viewSettingsHub`; tenant settings
  descendants retain their stricter capability guards. The regression verifies
  the metadata hub is visible without an active workspace selection. Its first
  rerun failed because the assertion used `Platform settings` instead of the
  actual translated `Platform Settings`; the corrected assertion passes.
- The create-user dialog previously showed mapped failures in a SnackBar behind
  the modal. It now renders the error within the dialog, presents pending
  progress, and disables repeated submission while the provider request is in
  flight. Seller-route validation feedback is also shown in-dialog on this
  flow. Tenant authorization and provider writes are unchanged.
- Firebase Auth email uniqueness is project-wide and remains unchanged. A
  registered email cannot create a second Auth identity merely by selecting a
  different workspace; duplicate-email errors now remain readable in the
  dialog.
- Missing invoice/receipt settings errors map to localized EN/AR/UR setup
  guidance. This message does not initialize settings or confirm that missing
  settings caused any reported live workspace failure.
- Focused validation:
  `flutter test -r expanded --dart-define=use_arabic=true test\widget\users_list_workspace_context_test.dart test\widget\app_router_backup_access_test.dart test\unit\core\error_mapper_test.dart`:
  `00:10 +60: All tests passed!`; `flutter analyze lib --no-pub`:
  `No issues found! (ran in 9.5s)`; `dart analyze test\`:
  `No issues found!`.
- No live workspace data or sanitized Firebase error code was available to
  establish the cause of the second workspace's invoice, receipt, or user
  creation failures. Production Rules/indexes and Hosting were not deployed in
  this segment; production behavior remains unverified.

## Scope-Specific Addendum — 2026-10-28 Non-Stock Toggle Persistence

The invoice-header toggle's write path was missing: it changed local widget
state but wrote only when the form's Save button was pressed. The setting is
now saved immediately through the tenant-scoped settings notifier, with
failure rollback and mapped feedback. A route-reentry regression failed
before the change and passed afterward; another test covers a denied write.
The single-setting write does not commit unrelated unsaved invoice-header
fields.

The same validation pass fixed an app-shell compilation error and updated a
stale test that expected tenant admins to be denied the read-only maintenance
screen. Component reset controls remain disabled. Notification access remains
limited to admin/manager, tenant_admin, and supervisor roles; seller and
platform super-admin access is denied.

Focused affected tests: `00:00 +54: All tests passed!`; full Flutter suite:
`01:26 +684: All tests passed!`; `flutter analyze lib --no-pub`:
`No issues found! (ran in 9.1s)`; `dart analyze test/`:
`No issues found!`. Local Rules Emulator evidence is `182 passing (41s)`.
Production behavior remains unverified; this work is local and unreleased.
