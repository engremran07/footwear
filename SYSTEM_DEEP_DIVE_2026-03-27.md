# ShoesERP System Deep Dive

Last updated: 2026-10-22

## Backup and Restore

The backup screen delegates persistence and authorization to `DatabaseBackupNotifier`. It exposes encrypted file export separately from Google Drive upload, shows destination-specific timestamps, and keeps automatic backups limited to configured Android Drive access. A Drive upload uses the generated encrypted bytes directly and does not create a second local archive.

Backups are scoped to the signed-in user's workspace and role. Tenant administrators merge records into their own workspace; only a platform administrator with an active support workspace may choose replacement and prune records in that selected workspace. Sellers are restricted to their assigned-route data and cannot start workspace backups. Restore previews and confirmation copy must describe the operation the selected role can actually perform.

The restore preview shows one warning selected by the effective restore mode: merge keeps records absent from the archive, while replacement may prune within the selected support workspace. Restore re-authentication is owned by `AuthNotifier` and shared with destructive flush confirmation; backup restore uses backup-specific localized prompt text.

Local encrypted archives are listed through the shared restore picker and can be deleted after confirmation. Passphrases are required for encrypted backup creation and restore; creation asks for confirmation to catch entry mistakes. Errors from preference, file-list, export, Drive, and restore operations are surfaced through the shared error mapper.

## Workspace Archival

Workspace archival is an ordered provider operation. It deactivates member profiles before recording the workspace's archived state. Business Rules require both an active profile and an active tenant document, so ordinary reads and writes are denied if either is inactive. A selected super-admin can reactivate an inactive workspace only through the explicit restoration path; ordinary business access stays denied until restoration completes. The emulator suite covers an inactive tenant while member profiles remain active.

## Authentication and Workspace Access

Firebase Authentication is the app's only sign-in mechanism. After Firebase Auth succeeds, the app loads the matching user profile and validates that it is active, has a supported role, and belongs to a concrete tenant unless it is a platform super-admin. The router and role-scoped providers wait for profile state and preserve mapped errors; no device registration, pairing approval, custom access slot, renewal timer, or app-managed session gate participates in sign-in.

Firestore Rules enforce active-profile status, active-tenant status, role permissions, and tenant ownership on business documents. A platform super-admin may see workspace metadata globally, but business data requires a selected workspace and a support reason; selection and exit are recorded in append-only `platform_access_logs`, and Rules enforce the eight-hour support-context limit. This audited workspace context is distinct from the removed app-managed access controls.

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

Workspace administrators configure English, Arabic, and Urdu invoice names, subtitles, addresses, contact and registration details, template, accent color, and visible fields. New invoices store a header snapshot, and seller-created snapshots are checked against the workspace settings. PDF generation uses the invoice snapshot so later branding edits do not alter existing documents. Voiding a non-stock sale does not restore inventory.

## Release Surfaces

Web and Android builds use the same version from `app/pubspec.yaml` and `AppBrand`. Google Drive OAuth client IDs are deployment configuration, not source defaults; without them, file export remains available while Drive operations stay unavailable. Firebase Hosting must preserve no-cache headers for Flutter shell files and permit the Google static hosts required by Flutter web.

## Workspace Management UX

Workspace creation does not subscribe to a global user list. Editing an existing workspace loads active owner choices through a tenant-scoped user query. Full workspace edits are offered only to a platform super-admin with active access to that workspace; tenant admins retain their workspace-scoped business settings and CRUD. Validation and provider failures always release the save state, keep the dialog open, and use the shared mapper's specific error rather than treating generic state errors as PDF failures. Android and web launcher icons are generated from the same source image, with no additional Android adaptive foreground inset.

New workspace setup creates a tenant-scoped owner account after the workspace exists, then assigns that active `tenant_admin` as owner. Workspace user deactivation updates the active profile status; it does not manage custom device or session records. Route and shop updates remain guarded and tenant-scoped, and linked shop/route counts are reconciled atomically. Route, shop, and transaction sorting remains in the existing providers and screens.

## Frontend Audit Evidence

The 2026-10-03 frontend review is recorded in `AUDIT_REPORT_FOOTWEAR_ERP.md`. It is source-led and includes a live Android login capture, but authenticated role flows, theme/locale matrix screenshots, expanded-size visual QA, and profile-mode performance measurements remain pending because the required account password was not entered into the tooling session.

## CRUD and Sorting Guarantees

Tenant administrators may create, read, and update business records inside their own workspace, subject to collection-specific financial and role-management safeguards. Sellers remain constrained to assigned routes and may not write administrator-only records. Provider guards validate the authenticated profile and tenant before writes; Firestore Rules independently enforce the same scope.

Route, shop, and transaction lists preserve their existing sort modes and query ordering. Shop creation and route-count reconciliation commit atomically, and administrator route reassignment adjusts both affected route counts in the same transaction. Referenced routes and shops use their existing deactivation workflow; invoice-linked ledger records remain immutable outside invoice correction flows. Standalone cash-in/cash-out removal retains the audited soft-delete and exact shop-balance reversal required by the financial-integrity contract.

Standalone `cash_in` and `cash_out` transactions can be soft-deleted only by a tenant admin-equivalent actor. The provider re-reads the transaction and shop, verifies the active tenant, actor, amount/type, and absence of `invoice_id`, then commits the delete marker, actor/timestamps, exact shop-balance reversal, and `last_balance_correction_transaction_id` in one batch. If the deleted row is the shop's latest transaction, the cached last-transaction fields are cleared in that batch. Rules enforce the reciprocal transaction/shop link and deny hard deletes. Sellers cannot delete transactions; invoice-linked financial records stay in the void/credit-note workflows.

## Invoice Integrity and PDF Behavior

Cash receipts carry a `cash_receipt_sequence` that must equal the `settings/{tenantId}.last_cash_receipt_number` increment in the same atomic write. Invoice voiding reads and updates the invoice, shop balance, stock documents, and reversal transactions in one Firestore transaction. Cash refunds reverse the full sale in the ledger, add the cash-out refund row, and reduce the receivable only by the outstanding amount. Non-stock invoice voids do not restore inventory.

Invoice PDFs use the captured workspace branding snapshot, localized payment method labels, mode-specific line tables, and `pw.MultiPage` with localized current/total page numbering. Long catalog invoices are covered by a page-count regression.
