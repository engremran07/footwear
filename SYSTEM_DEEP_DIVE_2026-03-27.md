# ShoesERP System Deep Dive

Last updated: 2026-10-25

## Backup and Restore

The backup screen delegates persistence and authorization to `DatabaseBackupNotifier`. It creates encrypted archives, saves them through the system file picker for phone storage, and supports later import from the selected file. A saved archive can be explicitly uploaded to Google Drive when online and Drive OAuth is configured; this action is user-triggered and is not background synchronization. The app also maintains its private local archive. Destination-specific timestamps are shown.

Backups are scoped to the signed-in user's workspace and role. Tenant administrators merge records into their own workspace; only a platform administrator with an active support workspace may choose replacement and prune records in that selected workspace. Seller archives contain currently assigned-route data. Seller restore accepts only the seller's own eligible, unlinked cash-in/cash-out rows; each transaction and matching same-route shop-balance delta are written in one Firestore transaction. It never restores seller invoice, inventory, or another seller's ledger records. Restore previews and confirmation copy must describe the operation the selected role can actually perform.

Workspace settings are fetched by `settings/{tenantId}` document ID rather than a tenant-field collection query, because Rules authorize the known tenant document path but cannot prove the broader query. Backup selection categories (such as `inventory`) are distinct from archive collection keys (`seller_inventory`, `inventory_transactions`, and `product_variants`); restore validates the concrete keys and each role's allowed scope before writing. Selected super-admins must have an active support workspace. Seller inventory records in an imported archive must belong to the signed-in seller.

The restore preview shows one warning selected by the effective restore mode: merge keeps records absent from the archive, while replacement may prune within the selected support workspace. Restore re-authentication is owned by `AuthNotifier` and shared with destructive flush confirmation; backup restore uses backup-specific localized prompt text.

App-private encrypted archives are listed through the shared restore picker and can be deleted after confirmation. Phone files use the system picker for save/import. Passphrases are required for encrypted backup creation and restore; creation asks for confirmation to catch entry mistakes. Archive checksum, workspace, creator, and current seller-route scope are validated before restore or Drive upload. Errors from preference, file-list, export, Drive, and restore operations are surfaced through the shared error mapper.

## Workspace Archival

Workspace archival and restoration are selected-super-admin provider operations. The tenant lifecycle update does not change member profiles; Firestore Rules require both an active profile and active tenant, so business reads and writes stop while the tenant is archived and resume only after restoration. A super-admin may select an existing inactive tenant with a reason of at least 10 characters; selection is logged in `platform_access_logs`, and the selected context remains subject to the eight-hour Rules limit. The workspace screen requires explicit confirmation before archive or restore. Emulator tests cover inactive selection, restoration, and denial of member business access before restoration.

## Database Flush and Reset

The client flush/reset screen and its provider fail closed. Deleting multiple
collections in sequential client batches can partially complete, leave
references dangling, or violate the requirement that ledger rows and
`shop.balance` changes are linked atomically. The legacy plaintext project
export, destructive whole-collection restore, and direct-balance reset scripts
also fail closed. The supported recovery path is the encrypted,
workspace-scoped app backup; tenant administrators merge without pruning, and
selected super-admins may replace only the active support workspace.

Tenant roots cannot be hard-deleted by Firestore Rules. Archive/restore is the
workspace lifecycle path and preserves the tenant anchor for its business
records. A general-purpose destructive maintenance workflow requires separate
transactional design and operational authorization; it is not provided by the
client.

## Authentication and Workspace Access

Firebase Authentication is the app's only sign-in mechanism. After Firebase Auth succeeds, the app loads the matching user profile and validates that it is active, has a supported role, and belongs to a concrete tenant unless it is a platform super-admin. The router and role-scoped providers wait for profile state and preserve mapped errors; no device registration, pairing approval, custom access slot, renewal timer, or app-managed session gate participates in sign-in.

Firestore Rules enforce active-profile status, active-tenant status, role permissions, and tenant ownership on business documents. A platform super-admin may see workspace metadata globally, but business data requires a selected workspace and a support reason; selection and exit are recorded in append-only `platform_access_logs`, and Rules enforce the eight-hour support-context limit. This audited workspace context is distinct from the removed app-managed access controls.

An inactive workspace can be selected to establish audited support context for
its lifecycle restoration path. The client permits selection when the tenant
document exists; Rules continue to deny ordinary business reads and writes
until the tenant is restored. The tenant-management screen offers confirmed
archive/restore actions only for the currently selected workspace and never
changes member profile activity.

## Invoice Modes and Workspace Headers

Invoice entry separates stock-backed sales, non-stock catalog sales, and cash receipt invoices. Non-stock sales retain product and variant detail while leaving seller inventory unchanged; Firestore rules enforce the workspace enablement setting and reject a stock sale without deduction metadata. Shop detail opens the shared invoice form with the current shop selected.

Cash receipt creation increments the tenant's receipt sequence in the same Firestore transaction that creates the receipt invoice and `cash_in` ledger entry and reduces `shop.balance`. Rules bind the invoice, transaction, amount, and resulting balance so none of those writes can succeed alone. Ledger-only `cash_in` remains a separate operation when no receipt document is required.

Sale invoices link to their `cash_out` ledger row and, when money is received, to the matching `cash_in` row. The shop-balance delta must be written atomically with those records. These links are enforced for admins and sellers; seller rules additionally verify the exact outstanding-balance delta. Non-stock invoicing defaults to disabled when a workspace setting is absent and must be explicitly enabled. Transaction descriptions use a multiline field for notes.

Sale and credit-note invoice numbers are allocated from `settings/{tenantId}.last_invoice_number` inside the same Firestore transaction as the business writes. Deterministic tenant-scoped invoice IDs make retries idempotent without a query-before-write race. Credit-note transactions also update the original invoice's cumulative credit amount and shop balance atomically. A credit-note void reverses both the stock restoration and that cumulative amount; sale voids restore sale stock and apply the selected refund mode.

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

Tenant administrators may create, read, and update business records inside their own workspace, subject to collection-specific financial and role-management safeguards. Sellers remain constrained to assigned routes and may not write administrator-only records. Provider guards validate the authenticated profile and tenant before writes; Firestore Rules independently enforce the same scope.

Route, shop, and transaction lists preserve their existing sort modes and query ordering. Shop creation and route-count reconciliation commit atomically, and administrator route reassignment adjusts both affected route counts in the same transaction. Referenced routes and shops use their existing deactivation workflow; invoice-linked ledger records remain immutable outside invoice correction flows. Standalone cash-in/cash-out removal retains the audited soft-delete and exact shop-balance reversal required by the financial-integrity contract.

Standalone `cash_in` and `cash_out` transactions can be soft-deleted only by a tenant admin-equivalent actor. The provider re-reads the transaction and shop, verifies the active tenant, actor, amount/type, and absence of `invoice_id`, then commits the delete marker, actor/timestamps, exact shop-balance reversal, and `last_balance_correction_transaction_id` in one batch. If the deleted row is the shop's latest transaction, the cached last-transaction fields are cleared in that batch. Rules enforce the reciprocal transaction/shop link and deny hard deletes. Sellers cannot delete transactions; invoice-linked financial records stay in the void/credit-note workflows.

## Invoice Integrity and PDF Behavior

Cash receipts carry a `cash_receipt_sequence` that must equal the `settings/{tenantId}.last_cash_receipt_number` increment in the same atomic write. Invoice voiding reads and updates the invoice, shop balance, stock documents, and reversal transactions in one Firestore transaction. Cash refunds reverse the full sale in the ledger, add the cash-out refund row, and reduce the receivable only by the outstanding amount. Non-stock invoice voids do not restore inventory.

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

Receipt PDFs use the configured workspace header and a prominent amount
received panel with payment method/reference, before/after balance, receiver,
and signature fields. Ledger summary labels now inherit the report locale's
text direction; amounts remain explicitly LTR. Settings and PDF regressions
are documented in `docs/frontend/screen-register.md`. The full Flutter suite
reports `01:08 +599: All tests passed!`; the focused invoice-void suite reports
`00:00 +22: All tests passed!`. Rendered APK/browser acceptance remains
separate from these source and widget checks.

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

## Workspace Owner and Seat Overview

The tenant-management screen combines the selected workspace's owner profile
with a live, tenant-scoped member roster. Owner contact and email-verification
status appear with live role counts and the free-tier limit of 10 active
non-platform-super-admin members. User activation and deactivation must update
the tenant seat counter atomically with the corresponding profile transition;
Firestore Rules reject profile-only or counter-only seat changes.

Workspace administrators may create canonical admin and seller accounts and
promote or demote eligible same-workspace admin/seller accounts. The permanent
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
retains transparency and reduces dimensions until the Base64 value is within
the Firestore field limit. The operation has no network dependency and does
not use an AI model; an image that still cannot meet the limit fails with a
localized size error rather than reaching Firestore as a failed upload.

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
