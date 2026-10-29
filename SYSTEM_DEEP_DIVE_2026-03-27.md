# ShoesERP System Deep Dive

Last updated: 2026-10-28

## Backup and Restore

The backup screen delegates persistence and authorization to `DatabaseBackupNotifier`. It creates encrypted archives, saves them through the system file picker for phone storage, and supports later import from the selected file. A saved archive can be explicitly uploaded to Google Drive when online and Drive OAuth is configured; this action is user-triggered and is not background synchronization. The app also maintains its private local archive. Destination-specific timestamps are shown.

Backups are scoped to the signed-in user's workspace and role. Tenant admins and legacy workspace admins merge records into their own workspace; only a platform administrator with an active support workspace may choose replacement and prune records in that selected workspace. Supervisors have no backup access. Seller archives contain currently assigned-route data. Seller restore accepts only the seller's own eligible, unlinked cash-in/cash-out rows; each transaction and matching same-route shop-balance delta are written in one Firestore transaction. It never restores seller invoice, inventory, or another seller's ledger records. Restore previews and confirmation copy must describe the operation the selected role can actually perform.

Workspace settings are fetched by `settings/{tenantId}` document ID rather than a tenant-field collection query, because Rules authorize the known tenant document path but cannot prove the broader query. Backup selection categories (such as `inventory`) are distinct from archive collection keys (`seller_inventory`, `inventory_transactions`, and `product_variants`); restore validates the concrete keys and each role's allowed scope before writing. Selected super-admins must have an active support workspace. Seller inventory records in an imported archive must belong to the signed-in seller.

The restore preview shows one warning selected by the effective restore mode: merge keeps records absent from the archive, while replacement may prune within the selected support workspace. Restore re-authentication is owned by `AuthNotifier` and shared with destructive flush confirmation; backup restore uses backup-specific localized prompt text.

App-private encrypted archives are listed through the shared restore picker and can be deleted after confirmation. Phone files use the system picker for save/import. Passphrases are required for encrypted backup creation and restore; creation asks for confirmation to catch entry mistakes. Archive checksum, workspace, creator, and current seller-route scope are validated before restore or Drive upload. Errors from preference, file-list, export, Drive, and restore operations are surfaced through the shared error mapper.

Workspace members see a generic backup scope/readiness card while their
workspace metadata is loading. The card retains mapped failure and Retry
states, and successful metadata loading enables backup without revealing the
workspace name. A prior privacy change hid the entire card and inadvertently
removed the only metadata retry path; the generic card preserves both privacy
and recovery feedback.

## Workspace Archival

Workspace archival and restoration are selected-super-admin provider operations. The tenant lifecycle update does not change member profiles; Firestore Rules require both an active profile and active tenant, so business reads and writes stop while the tenant is archived and resume only after restoration. A super-admin may select an existing inactive tenant with a reason of at least 10 characters; selection is logged in `platform_access_logs`, and the selected context remains subject to the eight-hour Rules limit. The workspace screen requires explicit confirmation before archive or restore. Emulator tests cover inactive selection, restoration, and denial of member business access before restoration.

The app shell watches the tenant document for ordinary authenticated workspace
members before mounting business-route content. It keeps the shell in a
loading state until the tenant is known, then shows localized retry and
sign-out feedback for missing, inactive, or failed tenant reads. The
platform-super-admin restoration path is excluded from this member gate.
Firestore Rules continue to deny inactive-tenant business reads and writes.

## Database Flush and Reset

The client flush/reset screen and its provider fail closed. Deleting multiple
collections in sequential client batches can partially complete, leave
references dangling, or violate the requirement that ledger rows and
`shop.balance` changes are linked atomically. The legacy plaintext project
export, destructive whole-collection restore, and direct-balance reset scripts
also fail closed. The supported recovery path is the encrypted,
workspace-scoped app backup; tenant administrators merge without pruning, and
selected super-admins may replace only the active support workspace.

The Settings screen exposes the maintenance-page entry to authorized
workspace admins using the same `PermissionPolicy` route decision as
`/settings/flush`. This is navigation visibility only: all component reset
controls remain disabled, provider reset methods remain fail-closed, and
Firestore Rules continue to enforce their independent authorization.

Tenant roots cannot be hard-deleted by Firestore Rules. Archive/restore is the
workspace lifecycle path and preserves the tenant anchor for its business
records. A general-purpose destructive maintenance workflow requires separate
transactional design and operational authorization; it is not provided by the
client.

## Authentication and Workspace Access

Firebase Authentication is the app's only sign-in mechanism. After Firebase Auth succeeds, the app loads the matching user profile and validates that it is active, has a supported role, and belongs to a concrete tenant unless it is a platform super-admin. The router and role-scoped providers wait for profile state and preserve mapped errors; no device registration, pairing approval, custom access slot, renewal timer, or app-managed session gate participates in sign-in.

The tenant-scoped `supervisor` role grants operational access to routes,
shops, products, inventory, invoices, reports, and tenant notifications. It
does not grant user, settings, or backup access, or financial
correction/approval, invoice-void, route-seller assignment, or shop-route
reassignment rights.
Tenant admins may create or assign only supervisor and seller roles to eligible
non-owner accounts; admin, tenant-admin, and platform roles remain restricted.

## Platform Permission Requests

App startup does not request camera, photo, storage, or OS-notification
permissions. The product has no camera-capture or OS-push-notification
workflow; image selection and backup file operations use system pickers.
Firestore notification-feed authorization is separate from browser/Android
notification permission. Permission requests must be added only for a
specific workflow, at the point that workflow is invoked, and tested against
the platform and browser permission policy instead of requested globally on
first launch.

The local release web build was loaded once in an unauthenticated browser at
the login route: nine Firebase initialization debug messages were captured,
with no console warnings/errors, uncaught page errors, or failed requests.
This did not validate authenticated screens or PDF export. A later
authenticated dashboard exposed missing UI fallback for Arabic-script
Firestore values under the English theme. The shared `AppFonts` resolver now
preserves English primary families and adds ordered bundled Noto fallbacks;
Arabic and Urdu retain their locale-specific primary families. This UI fix
does not alter the separate PDF font/shaping path. The reported inspector
total and category counts still disagree.

## Selected-Workspace Listener Expiry

The selected platform super-admin workspace context expires after eight hours
in Firestore Rules. The router refreshes at the client-side expiry boundary,
but that redirect alone is not enough for persistent Riverpod listeners.
`settingsProvider` is intentionally non-`autoDispose`; it now validates the
support context before resolving `settings/{tenantId}`, schedules
self-invalidation at the same shared TTL, cancels its timer on disposal, and
switches to a no-active-workspace state at expiry. This closes the old
settings stream instead of re-subscribing after a profile refresh. The
user-model, router, and tenant-user provider timers share one client TTL
constant. Client timers are lifecycle hygiene only; Firestore Rules continue
to enforce the authoritative server-time limit.

The regression reproduced the stale path before the fix:
`settingsDocumentIdForUser` returned `tenant-42` for a support context older
than eight hours; the fixed provider returns `__no_active_workspace__`
without opening Firestore. Focused settings/model/permission/router tests:
`00:11 +60: All tests passed!`; `flutter analyze lib --no-pub`:
`No issues found! (ran in 5.5s)`; `dart analyze test/`:
`No issues found!`. Rules/indexes were unchanged and not deployed.

## Mixed-Script UI Font Fallback

Firestore names, descriptions, and formatted currency may contain Arabic or
Urdu script regardless of the selected app locale. Shared `AppFonts` styles
therefore keep the locale's primary family and provide ordered bundled
Arabic/Urdu fallback families. Tests check fallback configuration across
heading, body, and text-theme styles. Browser inspection is needed to verify
actual glyph output; UI font fallback does not prove PDF shaping, print,
image, or spreadsheet rendering.

Firestore Rules enforce active-profile status, active-tenant status, role permissions, and tenant ownership on business documents. A platform super-admin may see workspace metadata globally, but business data requires a selected workspace and a support reason; selection and exit are recorded in append-only `platform_access_logs`, and Rules enforce the eight-hour support-context limit. This audited workspace context is distinct from the removed app-managed access controls.

An inactive workspace can be selected to establish audited support context for
its lifecycle restoration path. The client permits selection when the tenant
document exists; Rules continue to deny ordinary business reads and writes
until the tenant is restored. The tenant-management screen offers confirmed
archive/restore actions only for the currently selected workspace and never
changes member profile activity.

## Notification Feed Stability

Profile-stream refreshes may emit `AsyncLoading` while Riverpod retains the
last successful profile value. The notification scope may use that retained
profile only when its ID matches the settled Firebase Auth UID. This preserves
the current tenant feed during a same-user refresh; auth loading/errors or an
identity mismatch must clear the scope to prevent cross-account cache reuse.
The screen retains the already-authorized feed only when the current tenant
still matches the authorized tenant scope. A widget regression reproduces the
feed disappearing under the previous unconditional loading gate; the focused
widget and provider suites and full Flutter suite pass after the correction.
This is app-state continuity, not an authorization grant; Firestore Rules
remain authoritative.

The notification center and unread badge use one active-tenant-scoped stream.
Legacy admin, tenant-admin, and supervisor profiles can read and mark
notifications for their own workspace; sellers and platform super-admins
remain excluded, including selected-context super-admins. Shop visibility is
resolved from only the shop IDs referenced by that bounded feed. The child
shop listener depends on a sorted,
deduplicated shop-ID key rather than notification objects, so read-state-only
snapshots do not cancel and recreate shop subscriptions.

During either a feed refresh or referenced-shop visibility refresh, the UI
retains the last successful visible notification set rather than replacing it
with shimmer. The first load remains loading, and true stream errors remain
errors. Notification feed subscriptions and read-state writes require an
active profile, active tenant, authorized role, and selected/unexpired
super-admin support context where applicable. Firestore Rules remain
authoritative. Mark-as-read failures are mapped and presented; non-critical
notification creation failures are logged without masking the committed
financial operation.

Both feed and referenced-shop streams are keyed by the normalized concrete
tenant ID. This prevents Riverpod's retained provider state from displaying
the previous workspace's notifications after a workspace switch. A missing or
`__global__` context starts no notification query; the existing cache behavior
is retained only within the same tenant.

Read-state mutation is one-way: only an unread-to-read transition is allowed,
and `read` plus `read_at` must change together. The notifier sends
`FieldValue.serverTimestamp()` for both individual and batch operations;
Firestore Rules require the resolved value to equal `request.time`. Arbitrary
client timestamps, partial updates, read resets, inactive profiles/tenants,
unassigned/global tenant scope, and cross-tenant access are denied. Focused
Rules Emulator coverage includes valid mark-one and mark-all batches and these
negative cases. The earlier full local emulator run reported `185 passing
(46s)` and logged non-failing expression-limit diagnostics in other Rules
paths. During the v3.10.14+1125 deployment, Firebase reported the checked-in
Rules were already current; indexes deployed successfully without deleting
remote-only indexes or field overrides.

## Notification Visibility Query Budget and Android Alerts

The notification feed resolves referenced shops in five-ID chunks. This
preserves active-tenant, role, and shop-visibility checks while bounding Rules
document-access calls for larger notification feeds. A 50-shop emulator
regression exercises ten chunks for both workspace admins and supervisors;
the complete local Rules Emulator suite reports `191 passing (56s)`.

Android alerts are an explicit opt-in, foreground-only presentation of newly
arriving unread notifications that are visible to the active user. The app
reuses the existing tenant-scoped feed and shop-visibility providers; it adds
no Firestore listener, FCM integration, or backend sender. Permission is
requested only after the user enables the feature. Alerts are private, silent,
and deduplicated per user/workspace. They do not arrive while the app is
closed or suspended. Sellers and platform super-admins remain excluded.

Version `3.10.14+1125` focused notification, localization, and error-mapping
tests pass; the full Flutter suite reports `01:29 +708: All tests passed!`.
The Rules Emulator reports `191 passing (56s)`. Production Rules/indexes and
Hosting deployments completed, and live `version.json` reports
`3.10.14+1125`. This does not substitute for an authenticated JBM Impex
production check.

## Standalone Transaction Retry Integrity

The notifier rejects overlapping writes by throwing rather than completing a
second submission as a success-shaped no-op. When an idempotency key is
provided, a deterministic tenant-scoped document ID and Firestore transaction
serialize retries, writing the transaction and applying the corresponding
`shop.balance` delta atomically. The unkeyed batch path remains unchanged.
Focused provider tests cover caller-visible rejection and tenant-scoped ID
stability; the current tests do not include an emulator-backed concurrent
persistence race. Full Flutter suite: `01:34 +688: All tests passed!`;
`flutter analyze lib --no-pub`: `No issues found! (ran in 15.4s)`;
`dart analyze test/`: `No issues found!`. These changes remain local and
unreleased.

Platform settings-hub visibility is separate from permission to manage
workspace settings: a root platform super-admin may open the metadata-only hub,
while business-setting routes require an active, reasoned, unexpired selected
workspace context.

## RTL Statement and Financial Table Layout

`pdf` 3.12.0 may resolve child order using the page's RTL direction. Statement
table headers, data, summary, and final-balance rows explicitly pin physical
English-left/amount-right order with LTR directionality, while Arabic/Urdu
text and numeric amounts retain explicit per-cell directions. Every
logo-enabled financial PDF uses the shared workspace header with English
details left, a consistently sized company logo centered, and selected
Arabic/Urdu details right. This applies to statements, invoices, receipts,
seller/multi-shop reports, and flat exports; current logo bytes take priority,
and invoice snapshots provide the supported invoice/receipt fallback subject
to `visibleFields`. Arabic and Urdu generated statement and receipt headers
were visually inspected in Chrome. Urdu PDF shaping remains Naskh-style; full
Nastaliq rendering is not supported.

The local 2026-10-28 rendering follow-up found that mixed English-first
Arabic/Urdu values were assigned RTL paragraph direction whenever any RTL
character occurred, reversing the visible text order in invoice and statement
cells. Shared cell direction now follows the first cased script letter, while
numeric-only date values use LTR direction. Rasterized Arabic and Urdu invoice
and two-page statement samples were inspected after the correction. The
original production PDF was not available; its reported date discrepancy and
timezone interpretation remain unverified. No timestamp or date-format change
was made. The rendering correction was released in v3.10.16+1127; Hosting
reports the deployed version, and the matching ARM64 APK was installed on the
connected test phone. Firestore Rules and indexes were unchanged.

The 2026-10-29 follow-up traced an additional medial-letter defect in
English-first mixed-script values: the pinned `pdf` 3.13.1 renderer does not
shape Arabic-script glyphs when a text widget is LTR. The shared
`pdfTextForDirection` helper applies `bidi.logicalToVisual` before LTR layout,
without changing paragraph direction or English-first physical order. Shared
PDF text paths use the helper, with regression coverage for Arabic, Urdu,
already-shaped, and non-mixed text. The focused suite and both analyzers pass.
A synthetic raster was visually checked; the reported production PDF was not
available. This change is local and unreleased.

The supplied cash-receipt reference is now available. The local v3.10.7+1118
receipt body follows its compact bilingual structure, retains the existing
shared workspace header, uses saved balance fields, and remains a single A5
page. Workspace invoice-header settings support two optional receipt-footer
contact numbers. Arabic and Urdu receipt samples were visually inspected in
the browser. Full Flutter suite: `01:29 +639: All tests passed!`; focused
PDF/settings suite: `00:15 +24: All tests passed!`; both analyzers are clean;
Rules Emulator: `154 passing (30s)`. Split APKs/AAB were built and the ARM64
APK was installed; the hosted release remained undeployed.

## Invoice Modes and Workspace Headers

Invoice entry separates stock-backed sales, non-stock catalog sales, and cash receipt invoices. Non-stock sales retain product and variant detail while leaving seller inventory unchanged; Firestore rules enforce the workspace enablement setting and reject a stock sale without deduction metadata. Shop detail opens the shared invoice form with the current shop selected.

Cash receipt creation increments the tenant's receipt counter in the same Firestore transaction that creates the receipt invoice and `cash_in` ledger entry and reduces `shop.balance`. The settings update includes `last_cash_receipt_id` so Rules can bind the counter to the exact receipt invoice. Sale, credit-note, and receipt numbers share a high-water sequence allocated above the greater of the legacy invoice and receipt counters; Firestore Rules independently validate that next sequence on counter updates and linked invoice writes. Rules also bind the receipt, transaction, amount, and resulting balance so none of those writes can succeed alone. Ledger-only `cash_in` remains a separate operation when no receipt document is required.

Sale-invoice and cash-receipt creation is granted to active admins, tenant
admins, supervisors, and sellers through the app capability policy and
independently enforced by Firestore Rules. Seller creation is constrained to
the assigned route and authenticated seller identity. This create permission
does not grant settlement, correction, credit-note, or invoice-void rights.

Sale invoices link to their `cash_out` ledger row and, when money is received, to the matching `cash_in` row. The shop-balance delta must be written atomically with those records. These links are enforced for admins and sellers; seller rules additionally verify the exact outstanding-balance delta. Non-stock invoicing defaults to disabled when a workspace setting is absent and must be explicitly enabled. Transaction descriptions use a multiline field for notes.

Sale and credit-note invoice numbers are allocated from the greater of the workspace's legacy invoice and receipt counters inside the same Firestore transaction as the business writes. The operation advances its own legacy counter while preserving the shared high-water sequence. Deterministic tenant-scoped invoice IDs make retries idempotent without a query-before-write race. Credit-note transactions also update the original invoice's cumulative credit amount and shop balance atomically. A credit-note void reverses both the stock restoration and that cumulative amount; sale voids restore sale stock and apply the selected refund mode.

Unreleased Pass 2 policy changes use that same tenant-wide sequence without a
device-clock year and apply distinct `INV-`, `CN-`, and `REC-` prefixes for
sales, credit notes, and receipts. Historical identifiers are unchanged. The
current local source applies a shared `999999.99` maximum to SAR and PKR
financial writes in providers and Firestore Rules, including standalone cash
and correction operations. The amount is provisional and does not resolve
currency-specific limits.

The local staged minor-unit compatibility layer dual-reads and dual-writes
optional `financial_minor_units` companions for shop, transaction, and invoice
financial fields. A companion is used only when consistent with the legacy
value; mismatches fall back to that legacy value. Provider writes keep both
representations in the same atomic operation, and backup restore regenerates
companions without changing existing financial values. The tenant-scoped
backup preview and admin backfill API are implemented, but no production
preview or backfill has been run. The backfill updates companions only and is
paged at 100 documents by default, with a maximum page size of 400. Legacy
doubles and Rules tolerances remain authoritative; exact integer arithmetic,
historical reconciliation, compatible-client rollout, and strict Rules
cutover remain unresolved and release-blocking.

The sale provider aggregates item quantities by variant and converts `qty`
(dozens) plus `extra_pairs` to pairs using the active workspace's
`pairs_per_carton`. It rejects a sale unless that result exactly matches the
seller-inventory deduction map. Credit-note restore maps are cumulatively
bounded by the original sale's deductions, and voided notes do not consume
that allowance. This is a client-side integrity guard: Rules validate the
same-batch stock delta against the invoice's deduction metadata but cannot
iterate item lists to prove that metadata matches the item lines. Modified
clients remain a documented residual until the data representation is
server-verifiable.

SAR and PKR financial inputs allow at most two fractional digits. The amount parser rejects ambiguous three-decimal forms while preserving supported digit scripts and comma-grouped thousands; invoice, receipt, ledger, and transaction-correction providers enforce the same precision before writing. Credit-note item quantities are aggregated by variant and checked cumulatively against the original sale. Legacy linked notes are reconstructed with a tenant-scoped query capped at 50 documents and fail closed for larger or inconsistent histories. The Rules expression budget prevented adding an aggregate field to the existing linked invoice update contract, so this bounded reconstruction is used instead.

Shop creation Rules reject a nonzero opening balance or seeded cached
last-transaction summary. Standalone transaction creation must link to the
same-batch shop and exact balance delta. Multi-row invoice batches are checked
through invoice references and aggregate shop-balance validation; seller
invoice transaction Rules avoid redundant per-row delta evaluation to stay
within Firestore's expression budget.

Invoice, transaction, and seller-inventory client transactions may read
missing documents before creating or allocating them. Firestore Rules allow
these missing reads only within an active concrete tenant and the appropriate
role scope; super-admin reads require valid selected-workspace support context.
Missing seller-inventory reads are admin-equivalent only. During workspace
creation, a super-admin may read a missing settings document only while its
tenant document is also absent. Existing documents continue to use their
ordinary tenant/route authorization. The seller invoice path reuses scoped
profile/shop validation and keeps the complete atomic sale transaction within
the Rules expression budget.

Workspace administrators configure English, Arabic, and Urdu invoice names, subtitles, addresses, contact and registration details, template, accent color, and visible fields. New invoices store a header snapshot, and seller-created snapshots are checked against the workspace settings. PDF generation uses the invoice snapshot so later branding edits do not alter existing documents. Voiding a non-stock sale does not restore inventory.

## Release Surfaces

Web and Android builds use the same version from `app/pubspec.yaml` and `AppBrand`. Google Drive OAuth client IDs are deployment configuration, not source defaults; without them, file export remains available while Drive operations stay unavailable. Firebase Hosting must preserve no-cache headers for Flutter shell files and permit the Google static hosts required by Flutter web.

## Workspace Management UX

Workspace creation does not subscribe to a global user list. Editing an existing workspace loads active owner choices through a tenant-scoped user query. Full workspace edits are offered only to a platform super-admin with active access to that workspace; tenant admins retain their workspace-scoped business settings and CRUD. Validation and provider failures always release the save state, keep the dialog open, and use the shared mapper's specific error rather than treating generic state errors as PDF failures. Android and web launcher icons are generated from the same source image, with no additional Android adaptive foreground inset.

New workspace setup creates a tenant-scoped owner account after the workspace exists, then assigns that active `tenant_admin` as owner. Workspace user deactivation updates the active profile status; it does not manage custom device or session records. Route and shop updates remain guarded and tenant-scoped, and linked shop/route counts are reconciled atomically. Route, shop, and transaction sorting remains in the existing providers and screens.

## Inventory Selection and Units

The inventory screen reads the active workspace settings before rendering stock
quantity actions. If settings are loading, the screen remains in its loading
state; if settings fail, it shows the mapped retry state instead of silently
assuming 12 pairs per carton. Add-stock and warehouse-transfer dialogs receive
the loaded carton size and show localized loading, empty, or mapped retry
feedback for product, variant, and seller selectors. Stock adjustments,
transfers, and inventory audit writes remain in the existing provider
notifiers.

## Frontend Screen-State Sweep

The route register maps all 32 registered route patterns and the principal
role-filtered shell and contextual entry points. The latest unreleased UI pass
groups invoice summary totals by currency, withholds currency-filtered shop
rows until route scope is known, distinguishes invoice-profile loading/error
states, resets profile dirty state when the saved name is restored, and gives
notification bulk writes progress and mapped failure feedback. Feed rows
without a shop target do not show a navigation chevron, and stat-card entrance
motion is disabled when reduced motion is requested. The 2026-10-24 login
follow-up caps the narrow form width to the available viewport, preventing
invalid minimum/maximum constraints at intermediate window sizes; widget
regressions cover six widths and EN/AR/UR.

These changes leave provider writes, tenant scope, authorization, inventory
accounting, and invoice calculations unchanged. The complete Flutter suite
reported `01:20 +559: All tests passed!`; Flutter library and test analyzers
reported no issues. A subsequent targeted screen-state review covered
report-export busy/error handling, user route-option failures, backup/flush
workspace states, tenant-admin presentation, and shop-form route-query retry.
The named findings now have focused widget regressions and source dispositions;
broader dialog/sheet interactions and rendered browser/device acceptance remain
open because the user's browser pages were not shared into the session. The
current full Flutter suite was not rerun after those targeted additions. See
`docs/frontend/screen-register.md` and
`docs/frontend/ui-ux-audit-report.md` for the evidence and outstanding scope.

The follow-up multi-currency report review also fixed account-statement
currency resolution in both report and shop-detail exports. Seller report rows
now use their transaction route currency, current shop balances use the
current route currency, and PDF grand totals are grouped by currency rather
than combining unlike amounts. Admin report route metadata includes inactive
routes to preserve currency labels for historical transactions.

## Frontend Audit Evidence

The 2026-10-03 frontend review is recorded in `AUDIT_REPORT_FOOTWEAR_ERP.md`. It is source-led and includes a live Android login capture, but authenticated role flows, theme/locale matrix screenshots, expanded-size visual QA, and profile-mode performance measurements remain pending because the required account password was not entered into the tooling session.

## Shared UI Accessibility Foundation

`AppTokens.minTouchTarget` is the shared 48-logical-pixel target token used by
the horizontal filter-chip bar. `AppMotion` exposes the `MediaQuery` reduced-
motion preference for shared components. Empty/error illustrations, stat-card
value switches and entrances, status-chip transitions, and all shared
`AppAnimations` presets suppress optional motion when that preference is
enabled. `PressableWidget` keeps its tap and semantic actions while suppressing
scale feedback. Balance badge screen-reader labels use the selected locale and
expose the formatted amount as one semantic value.
The custom fade/scale and form slide transitions in `app_router.dart` also
return the route child directly when reduced motion is enabled; normal route
motion remains active otherwise.

Regression tests cover the filter target under RTL, EN/AR/UR semantics, the
success/error text-background contrast pairs used by the balance badge, and
disabled/enabled animation presets, route transitions, and press semantics.
The complete Flutter suite reports `01:01 +589: All tests passed!`; library
analysis reports `No issues found! (ran in 102.3s)` and test analysis reports
`No issues found!`. These results are not a substitute for full-screen reader,
device, or WCAG conformance evaluation. See
`docs/frontend/screen-register.md` and
`docs/frontend/ui-ux-audit-report.md` for screen coverage and remaining checks.

## Shared Contextual Record Actions (v3.10.15+1126)

Record-level secondary actions use `AppContextualAction`,
`AppContextualActions`, and the shared route/shop/transaction catalog. Current
integrations cover route and shop lists/details, product lists/details,
inventory variants, invoice lists, history, notifications, dashboard rows,
outstanding-shop reports, and the shop ledger. The presenter preserves the
existing primary tap and nested controls and opens from touch long-press, web
secondary click, context-menu/Shift+F10 keys, and semantic custom actions.
Shop-ledger actions retain their visible menu button for discoverability.

The resolver filters by entity, enabled state, active profile, concrete
tenant, and `PermissionPolicy` capability. Selection obtains the current
profile again and invokes the current eligible action callback. All routes,
confirmation flows, and notifier methods remain the existing guarded paths;
no direct Firestore write or authorization change was introduced. Unit and
widget regressions cover role filtering, inactive/unscoped users, row and
nested taps, long-press, keyboard menu invocation, and a narrow RTL large-text
layout. The full serial Flutter suite passed `02:40 +716: All tests passed!`;
focused release regressions passed `00:11 +33: All tests passed!`;
`flutter analyze lib --no-pub` reported
`No issues found! (ran in 16.2s)` and `dart analyze test/` reported
`No issues found!`. Hot restart was unavailable because the connected DTD had
no active app. Web build reported `EXIT: 0`; Hosting and Firestore
Rules/indexes each reported `Deploy complete!`; live `version.json` reports
`3.10.15+1126` and the shell uses `no-store, must-revalidate, no-cache`.
Split APKs (31.4/32.9/34.5 MB) verify with APK v2; the 72.3 MB AAB reports
`jar verified.` with a local self-signed-certificate warning and no timestamp.
ARM64 was copied and installed on `R5GL22RGT9V` (`Success`, versionCode
`310153126`). Authenticated browser/device and manual assistive-technology
acceptance remain unverified; Play Console upload was not performed.

## Edit-Form Loading and Recovery

Route, shop, product, and variant edit forms wait for the authenticated profile
and the requested record before presenting editable fields or enabling save.
Provider failures use the shared mapped error state with retry; missing or
out-of-scope records are not represented as blank editable defaults. Loaded
route assignments, currencies, and form values are applied before editing.
The screen-level gate is defense in depth only: provider role/tenant checks
and Firestore Rules remain the authorization boundary.

Focused widget coverage exercises profile/record loading, provider failure and
retry, missing records, and existing-value prefill. Browser/device visual
verification across the theme and locale matrix remains pending.

## CRUD and Sorting Guarantees

Tenant administrators may create, read, and update business records inside their own workspace, subject to collection-specific financial and role-management safeguards. Supervisors have the explicitly limited operational access described above. Sellers remain constrained to assigned routes and may not write administrator-only records. Provider guards validate the authenticated profile and tenant before writes; Firestore Rules independently enforce the same scope.

Route, shop, and transaction lists preserve their existing sort modes and query ordering. Shop creation and route-count reconciliation commit atomically, and administrator route reassignment adjusts both affected route counts in the same transaction. Referenced routes and shops use their existing deactivation workflow; invoice-linked ledger records remain immutable outside invoice correction flows. Standalone cash-in/cash-out removal retains the audited soft-delete and exact shop-balance reversal required by the financial-integrity contract.

Standalone `cash_in` and `cash_out` transactions can be soft-deleted only by a tenant admin-equivalent actor. The provider re-reads the transaction and shop, verifies the active tenant, actor, amount/type, and absence of `invoice_id`, then commits the delete marker, actor/timestamps, exact shop-balance reversal, and `last_balance_correction_transaction_id` in one batch. If the deleted row is the shop's latest transaction, the cached last-transaction fields are cleared in that batch. Rules enforce the reciprocal transaction/shop link and deny hard deletes. Sellers cannot delete transactions; invoice-linked financial records stay in the void/credit-note workflows.

## Invoice Integrity and PDF Behavior

Cash receipts carry a `cash_receipt_sequence` that must equal the new shared high-water sequence and the `settings/{tenantId}.last_cash_receipt_number` value in the same atomic write. Invoice and receipt counter changes must advance above both pre-write counters. Invoice voiding reads and updates the invoice, shop balance, stock documents, and reversal transactions in one Firestore transaction. Cash refunds reverse the full sale in the ledger, add the cash-out refund row, and reduce the receivable only by the outstanding amount. Non-stock invoice voids do not restore inventory.

Invoice PDFs use the captured workspace branding snapshot, localized payment method labels, mode-specific line tables, and `pw.MultiPage` with localized current/total page numbering. Long catalog invoices are covered by a page-count regression.

Arabic and Urdu PDF text requires the `pdf` package's `use_arabic` compile-time option; its default enables bidirectional ordering without Arabic letter shaping. The shared font loader rejects PDF generation with a typed, localized configuration error when that option is absent, so PDF, print, share, and PNG flows cannot silently produce unshaped RTL text. All test, debug, web, and Android build commands pass `--dart-define=use_arabic=true`.

PDFs embed Noto Sans Arabic for both Arabic and Urdu. Urdu output is Naskh-style rather than Nastaliq because the current PDF renderer does not support Nastaliq's complex OpenType shaping. The Flutter UI separately uses Noto Nastaliq Urdu. PNG pages are rasterized from the same PDF bytes; XLSX keeps Unicode text and RTL worksheet direction but relies on the spreadsheet app for font selection and shaping. Automated PDF tests check the embedded font name and Arabic/Urdu text across report builders; pixel-level verification in target browsers, PDF viewers, and printers remains a separate visual QA step.

## Operational Refresh, Header Sync, and Void Visibility

Workspace settings remain tenant-scoped Firestore snapshot streams. Invoice
header and general settings forms now rehydrate from newer snapshots while
their fields are clean, and keep local edits once the user changes a field.
The invoice header is the canonical editable branding control; legacy
`company_name` values are read for migration compatibility and are removed
when settings are next saved. Data-backed shops, invoice lists, shop ledgers,
and settings surfaces also expose pull-to-refresh without replacing the
underlying real-time listeners.

Shop analytics aggregate `cash_in`, `cash_out`, and outstanding balances by
each shop's route currency, with full numeric values and horizontal scrolling
instead of compact millions. The invoice Pending filter includes issued and
partially paid sales with outstanding balance and excludes receipts, paid
documents, and voids. Shop detail combines location and overdue age in one
responsive row.

Invoice voids retain append-only financial history: the invoice, shop balance,
stock, linked transaction audit metadata, and reversal rows commit in one
Firestore transaction. The provider also reads all invoice-linked transactions
through a tenant-scoped, fully paged `invoice_id` query so settlement payments
created by older versions are not missed. New settlement writes atomically add
their transaction ID to the invoice for race-safe void handling. Customer-
facing shop ledger streams and complete statement/report exports omit tagged
voided originals and compensating reversals, while admin-wide transaction
history remains available. Credit-balance void mode retains every valid
cash-in payment as customer credit; cash-refund mode hides those payments.
No hard deletion is introduced.

Receipt PDFs use the shared workspace header and a prominent amount-received
panel with payment method/reference, receiver, and signature fields. They use
an A5 page, remain single-page, and omit the account-balance-movement block;
the accounting data and atomic ledger/balance writes are unchanged. Ledger
summary labels inherit the report locale's text direction; amounts remain
explicitly LTR. Embedded-font/image and A5-page regressions are structural
tests, not substitutes for rendered browser/device acceptance.

## Financial Document Language Pair

Workspace invoice-header settings select English-Arabic by default or
English-Urdu for financial PDFs. The pair is serialized in the canonical
workspace settings and copied into each new invoice header snapshot, so
historical invoice and receipt documents retain their original branding and
language choice. The preference applies to invoice and cash-receipt PDFs,
account statements, seller and multi-shop reports, and flat financial-report
PDFs. Ledger summary/table labels render English and RTL text in separate
directionally explicit lines; numeric amounts retain LTR formatting. Seller
invoice Rules require the provider's selected language pair to match the
workspace configuration without relaxing tenant, route, stock, or balance
validation.

The shared workspace brand header places English business information on the
left and the configured Arabic or Urdu information on the right, independent
of app locale. Current settings logo bytes take priority; invoice and receipt
snapshots supply a fallback only when those bytes are unavailable, and the
configured logo visibility remains authoritative. PDF tests cover embedded
font/image resources and page geometry; these structural checks are distinct
from visual inspection in an actual viewer.

The page can inherit RTL direction from the selected report locale, so shared
bilingual header rows must wrap `pw.Row` in explicit LTR
`pw.Directionality`; child English and Arabic/Urdu text widgets retain their
own directions. `pw.Row` in the pinned `pdf` 3.12.0 package does not expose a
`textDirection` parameter. The current output was visually inspected for both
Arabic and Urdu pairs in Chrome, with English on the left and the selected RTL
language on the right. Urdu remains Naskh-style. A separate Nastaliq proof of
concept is not integrated because it has not established logo embedding,
selectable text, pagination, or report parity across Web and Android.

## Workspace Owner and Seat Overview

The tenant-management screen combines the selected workspace's owner profile
with a live, tenant-scoped member roster. Owner contact and email-verification
status appear with live role counts and the free-tier limit of 10 active
non-platform-super-admin members. User activation and deactivation must update
the tenant seat counter atomically with the corresponding profile transition;
Firestore Rules reject profile-only or counter-only seat changes.

Tenant admins may create or assign supervisor and seller roles only to
eligible non-owner accounts; they cannot promote users to admin or
tenant-admin. Legacy admins may manage seller profiles only. The permanent
owner, tenant-admin peers, and platform roles are protected, and workspace
admins cannot deactivate peer administrators. Profile/seat changes remain
atomic. A selected platform super-admin can reconcile a stored seat counter
against the fully paged active roster; a revision check prevents the
reconciliation from overwriting a concurrent membership change. Role counts
are shown from live profile data only when the viewer has authorized roster
access. Without that context, the screen uses stored metadata and offers an
explicit workspace-access action instead of showing an endless loading bar.

## Workspace Logo Processing

Logo processing is local to the client and uses deterministic PNG decoding,
orientation correction, proportional resizing, and lossless re-encoding. It
retains transparent pixels and opaque colored backgrounds, and reduces
dimensions until the Base64 value is within the Firestore field limit. It does
not remove or substitute a background. The operation has no network dependency
and does not use an AI model; an image that still cannot meet the limit fails
with a localized size error rather than reaching Firestore as a failed upload.

The settings backup serializes the tenant settings document without rewriting
the `logo_base64` string; restore writes that value back unchanged. Invoice
creation copies the same value into its branding snapshot. Financial PDFs use
the shared logo bytes/header policy and respect `visible_fields`; PNG, print,
and share rasterize or pass through those same PDF bytes. XLSX currently has
no logo-embedding path. Before feature implementation, engineers first review
the current todos and Git delta, load the applicable skills and path
instructions, and read the affected runtime docs and source paths as required
by `AGENTS.md` §8.

## Cash Receipt Presentation

Receipt detail uses a bilingual, bordered metadata table. Its PDF uses the
shared compact workspace brand header, emphasizes the received amount, and
places paired-language labels in a compact table with receiver/signature
fields. The receipt PDF is built as a single page and bounds long user-provided
values; it omits the account-balance-movement block. This is presentation-only:
receipt sequencing, the cash-in ledger row, and the shop-balance reduction
remain one atomic operation.

## Release Configuration Note

The v3.10.1+1112 web and Android release was built without Google Drive OAuth
client IDs. Drive upload is therefore unavailable in these release artifacts;
encrypted phone archives and local restore remain available. Configure the
approved OAuth client IDs and rebuild both surfaces before enabling Drive.

Release evidence: the full Flutter suite reported `01:20 +623: All tests
passed!`; `flutter analyze lib --no-pub` reported `No issues found! (ran in
98.8s)`; and `dart analyze test/` reported `No issues found!`. The Rules
Emulator reported `140 passing (31s)`. The web build exited 0, Hosting and
Firestore Rules/indexes deployments reported `Deploy complete!`, and split
APK artifacts were built at 30.6/32.1/33.6 MB. The ARM64 APK installed on
`R5GL22RGT9V` (`Success`, versionName `3.10.1`, versionCode `3103212`).

## v3.10.2 Workspace and Receipt Correction

Release version `3.10.2+1113` includes the workspace role, seat reconciliation,
logo resizing, and bilingual receipt corrections described above. Verification
reported `01:26 +623: All tests passed!`, `No issues found! (ran in 103.6s)`
for Flutter analysis, `No issues found!` for test analysis, and `145 passing
(31s)` in the Rules Emulator. The web build exited 0; Hosting and Rules/indexes
deployment each reported `Deploy complete!`. Split APKs were built at 30.7 MB,
32.2 MB, and 33.6 MB. The ARM64 APK was installed on `R5GL22RGT9V` with
`Success`; the device reports versionName `3.10.2` and versionCode `3103313`.

## v3.10.3 Legacy Workspace Roster Correction

Firestore `orderBy(display_name)` excludes documents where the optional field
does not exist. Workspace active/inactive member streams now retrieve their
tenant-scoped role-filtered roster without that ordering and sort models
client-side by display name, email, and ID. Seat reconciliation uses the same
complete active-user query, so a legacy profile cannot be silently omitted
from the saved total. The Firestore emulator regression demonstrates that the
ordered query omits the seeded legacy document while the complete query
returns it. This provider-only hotfix changes neither Rules nor indexes; those
were deployed with v3.10.2.

Version `3.10.3+1114` verification: full Flutter suite `01:21 +623: All tests
passed!`; `flutter analyze lib --no-pub`: `No issues found! (ran in 15.3s)`;
`dart analyze test/`: `No issues found!`; Rules Emulator: `146 passing (37s)`.
The web build exited 0 and Hosting deployment reported `Deploy complete!`.
Split APKs were built at 30.7 MB, 32.2 MB, and 33.6 MB. ARM64 installed on
`R5GL22RGT9V` (`Success`, versionName `3.10.3`, versionCode `3103414`).

## v3.10.4+1115 Release Verification

Super-admin workspace support-access start, switch, and end feedback now
reflects the active audited context. Bilingual PDF rows use an explicit LTR
`pw.Directionality` parent because the page inherits locale direction and
`pw.Row` in `pdf` 3.12.0 has no direction parameter. Actual Arabic and Urdu
account-statement samples were inspected in Chrome; English is left and the
configured RTL language is right.

Urdu remains readable Naskh-style output. A separate `payv` proof displayed
Nastaliq shaping but is not integrated because logo embedding, text extraction,
pagination, and full report parity across Web and Android remain unverified.
Release verification: full Flutter suite `01:16 +628: All tests passed!`;
Flutter analysis `No issues found! (ran in 132.4s)`; test analysis
`No issues found!`; Rules Emulator `147 passing (29s)`. Web `EXIT: 0`;
Hosting and Rules/indexes reported `Deploy complete!`; split APKs were
30.7/32.2/33.6 MB. No Android device was connected for installation.

## v3.10.5+1116 Supervisor and Android Bundle Verification

The tenant-scoped `supervisor` role is operationally limited to routes, shops,
products, inventory, invoices, reports, and tenant notifications. User
administration, settings, backup, financial corrections/approval, invoice
voids, route seller assignment, and shop route reassignment remain outside
this role. Tenant admins may assign supervisor or seller roles only to
eligible non-owner profiles.
Legacy workspace admins can load the tenant user list and restore workspace
archives in merge-only mode. Notification shop subscriptions now use a stable,
sorted set of feed shop IDs, avoiding restarts caused solely by read-state
updates.

The first Play Console AAB build exposed a Gradle configuration collision:
release ABI APK splits also generated multiple shrunk-resource outputs during
`bundleRelease`. `app/android/app/build.gradle.kts` now enables ABI splits for
APK tasks and disables them for bundle tasks. The release version-code
encoding is bounded and monotonic; Flutter adds an ABI-specific offset to split
APK codes.

Verification: full Flutter suite `01:59 +633: All tests passed!`; focused
role/backup/notification/users suite `00:22 +55: All tests passed!`;
`flutter analyze lib --no-pub`: `No issues found! (ran in 15.0s)`;
`dart analyze test/`: `No issues found!`; Firestore Rules Emulator:
`152 passing (33s)`. Markdown lint and `git diff --check` exited 0. Split APK
build: ARMv7 30.7 MB, ARM64 32.2 MB, x86_64 33.6 MB. Signed AAB:
54.8 MB. APK v2 signature and AAB JAR signature checks succeeded; APK
metadata reports versionName `3.10.5`, versionCode `310053116`. The Android
SDK license checker still reports unaccepted licenses, although release APK
and AAB builds succeeded. No ADB device was connected. Production Rules/indexes
deployment, Hosting, installation, commit, and push were not performed.

## v3.10.6+1117 Bilingual Statement Header and Combined Release

Account-statement headers now place the English account title, report date,
and generated-by value on the left; the shop name and localized statement
duration in the center; and selected Arabic or Urdu details on the right.
`pw.Directionality(textDirection: pw.TextDirection.ltr)` fixes physical
column order regardless of document locale, while each text cell preserves
its language direction. The shop-detail and report statement exports both
use `buildPdfLedger()`. No balance calculation or ledger write behavior
changed.

Updated statement PDFs were generated with Arabic and Urdu language pairs and
visually inspected in Chrome. Focused PDF suite: `00:01 +12: All tests
passed!`; full Flutter suite: `01:14 +633: All tests passed!`;
`flutter analyze lib --no-pub`: `No issues found! (ran in 6.3s)`;
`dart analyze test/`: `No issues found!`; Firestore Rules Emulator:
`152 passing (30s)`.

Web build `EXIT: 0`; Firebase Hosting and Firestore Rules/indexes each
reported `Deploy complete!`. Live `/`, `index.html`, `version.json`, and
`main.dart.js` returned HTTP 200 with `no-store, must-revalidate, no-cache`;
`version.json` reports version `3.10.6`, build `1117`. The 23 remote indexes
and 2 field overrides absent locally were preserved without `--force`. Split APKs: ARMv7
30.7 MB, ARM64 32.2 MB, x86_64 33.7 MB; signed AAB: 54.8 MB. APK v2 and
AAB JAR verification passed. ARM64 metadata is versionName `3.10.6`,
versionCode `310063117`; installation on `R5GL22RGT9V` returned `Success`.

## 2026-10-27 Support-Context Audit Linkage and Localized Amount Input

Super-admin workspace starts now use a same-batch profile/log contract. The
profile stores the exact `active_workspace_access_log_id`; Firestore Rules
verify that the post-batch event has the authenticated actor, selected
workspace, identical support reason, and request-time server timestamp. The
start-event rule independently verifies the post-batch profile points back to
that event. Clearing or switching a selected workspace now also requires a
same-batch `workspace_access_ended` event. The end event is validated against
the prior profile's actor, workspace, reason, and optional start-event ID; the
updated profile retains its exact end-event ID in
`last_workspace_access_end_log_id`. A workspace switch ends the previous
context and starts the next context in the same batch. A pre-fix Rules
regression allowed an unlogged exit; the final local Rules suite reports
`181 passing (37s)`. This changes the client write schema; production Rules
must be deployed before the updated client is used for workspace support
access.

The shared monetary input formatter now retains Western, Arabic-Indic, and
Eastern-Arabic digits plus ASCII and Arabic decimal/grouping separators. The
existing canonical amount parser normalizes these inputs; the formatter/parser
regression exercises both stages. This does not imply Arabic/Urdu PDF font or
visual-rendering defects are resolved.

## 2026-10-27 Tenant Permission and User-List Recovery

The app-side role/capability map is centralized in `RoleCapabilities` and
`PermissionPolicy`; router access now treats the dashboard as a business
capability and schedules a refresh when selected super-admin context expires.
This is not a replacement for the independent tenant/role/support-context
checks in Firestore Rules. Write-side tenant scoping rejects missing and
global-sentinel tenant IDs while retaining explicitly scoped legacy reads.

The Users screen's `authUserProvider.value` access hid Firestore profile-stream
errors: while Firebase Auth still had a signed-in user, a null profile value
was rendered as shimmer indefinitely. A missing profile followed the same
loading-shaped UI. The screen now renders loading only while its auth/profile
streams are actually loading, maps stream errors to retry UI, and surfaces
missing-profile access denial. The widget regression reproduced a timeout
before the change and passed afterward (`00:04 +4: All tests passed!`).

Local-only status: complete Rules parity review, all finding-by-finding audit
dispositions, analyzer/full-suite verification, fresh APK/AAB builds, and
device delivery remain pending. No production deployment, Play publication,
commit, or push is implied.

## 2026-10-28 Non-Stock Setting and Workspace Access Follow-up

The invoice-header setting previously changed only local widget state until
the form's bottom Save action ran. The switch now persists its single
`allow_non_stock_invoices` field immediately through the tenant-scoped
`SettingsNotifier`, while leaving unrelated dirty header edits untouched.
Write failures restore the prior value and surface mapped feedback. A widget
regression covers enable → leave → reopen, plus failure rollback.

The app shell safely handles a null profile for the tenant-keyed notification
badge and renders the selected-workspace exit control only inside a verified
super-admin support context. The workspace maintenance route is viewable by
authorized workspace admins, but every client-side reset remains disabled.
Notification feed roles are admin/manager, tenant_admin, and supervisor;
seller and platform super-admin access is denied.

Focused affected tests: `00:00 +54: All tests passed!`; full Flutter suite:
`01:26 +684: All tests passed!`; `flutter analyze lib --no-pub`:
`No issues found! (ran in 9.1s)`; `dart analyze test/`: `No issues found!`.
This follow-up remains unreleased at `3.10.12+1123`; no new web/APK/AAB
artifacts, production deployment, phone install, commit, or push are claimed.

## 2026-10-28 Seller Notification Cooldown Fix

Seller notifications are written best-effort after their financial source
commits. The former five-second per-user cooldown could reject a notification
without reversing the successful transaction or invoice. Notification IDs
are now deterministic from the source type and ID, and Firestore Rules require
the notification tenant, seller, shop, route, amount, and transaction type to
match the persisted invoice or standalone transaction. This keeps notification
availability outside the financial atomic-write boundary.

Local regressions verify consecutive seller transaction notifications,
matching invoice notifications, and denial of detached or mismatched sources.
The full Rules Emulator reports `190 passing (48s)`; focused Flutter tests
report `00:03 +20: All tests passed!`. Rules/indexes are not deployed. The
separate production notification-feed permission/flicker report remains open.

## 2026-10-28 Dashboard Cache Tenant Isolation

Dashboard fallback metrics are kept in a scope-tagged cache entry keyed by
user identity, role, active state, effective tenant/workspace context,
support-session identity, and assigned routes. A cached result is eligible
only for the matching scope. During a profile refresh, the cached profile ID
must also match the settled Firebase Auth UID. A missing profile or
permission/auth error cannot display cached business metrics.

The regression reproduced workspace A's cached metrics rendering under
workspace B while B's data providers were loading. After the fix, B remains
in loading until its own data is ready, and same-workspace refresh retains its
own fallback. Dashboard tests: `00:09 +5: All tests passed!`;
`flutter analyze lib --no-pub`: `No issues found! (ran in 8.1s)`;
`dart analyze test/`: `No issues found!`. No Rules/query changes or release
operations occurred.

## 2026-10-29 Invoice Rules Deployment Status

The shared invoice/receipt high-water sequence Rules and composite indexes
were deployed to `shoeserp-clean-20260327` after the local Rules Emulator
reported `207 passing (56s)`. Firebase reported `Deploy complete!` and
preserved 23 remote indexes and 2 field overrides absent from the local
manifest. This is a Rules/indexes deployment only; it does not include
Hosting, an app release, device delivery, commit, or push.

The user confirmed active JBM Impex devices use v3.10.17+1128 and reports
that invoice creation, non-stock sales, and cash receipts succeeded for
admin, supervisor, and seller on the designated `Testing` route / `owerty`
test shop after deployment. This supports the shared-sequence Rules mismatch
as the likely blocker, but the original Firebase error code and live counter
values were not captured, so the exact rejected rule remains unproven.

The live log capture showed background Firestore `UNAVAILABLE` errors caused
by DNS lookup failures for `firestore.googleapis.com` and App Check token
API 403/too-many-attempts warnings. The capture did not show
`PERMISSION_DENIED`. These are separate connectivity/configuration signals;
they do not contradict the user's report that the test writes succeeded.
The agent did not directly read or write production business data.
