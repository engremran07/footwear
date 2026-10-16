# ShoesERP System Deep Dive

Last updated: 2026-10-17

## Backup and Restore

The backup screen delegates persistence and authorization to `DatabaseBackupNotifier`. It exposes encrypted file export separately from Google Drive upload, shows destination-specific timestamps, and keeps automatic backups limited to configured Android Drive access. A Drive upload uses the generated encrypted bytes directly and does not create a second local archive.

Backups are scoped to the signed-in user's workspace and role. Tenant administrators merge records into their own workspace; only a platform administrator with an active support workspace may choose replacement and prune records in that selected workspace. Sellers are restricted to their assigned-route data and cannot start workspace backups. Restore previews and confirmation copy must describe the operation the selected role can actually perform.

The restore preview shows one warning selected by the effective restore mode: merge keeps records absent from the archive, while replacement may prune within the selected support workspace. Restore re-authentication is owned by `AuthNotifier` and shared with destructive flush confirmation; backup restore uses backup-specific localized prompt text.

Local encrypted archives are listed through the shared restore picker and can be deleted after confirmation. Passphrases are required for encrypted backup creation and restore; creation asks for confirmation to catch entry mistakes. Errors from preference, file-list, export, Drive, and restore operations are surfaced through the shared error mapper.

## Workspace Archival

Workspace archival is an ordered provider operation. It disables member profiles and revokes their device registrations and active sessions before recording the workspace's archived state. Firestore access checks use the member's active profile gate so ordinary business reads and writes are denied after archival without adding repeated tenant reads to high-volume transaction rules. An archived workspace must not be reactivated or edited through an ordinary client update.

Device session creation is bound to an active device registration in the same authenticated user's workspace. Slot identifiers, configured limits, and device/session identity must agree. Pairing-required workspaces create pending device registrations and require administrator approval before session creation. Device removal and related session revocation are atomic; blocking cannot be reversed by the device owner. Registrations inactive for 30 days may be reclaimed. Rules tests cover valid access, invalid slots, unregistered devices, tenant-scoped registry queries, pairing, block/recovery, and inactive workspace access.

## Invoice Modes and Workspace Headers

Invoice entry separates stock-backed sales, non-stock catalog sales, and cash receipt invoices. Non-stock sales retain product and variant detail while leaving seller inventory unchanged; Firestore rules enforce the workspace enablement setting and reject a stock sale without deduction metadata. Shop detail opens the shared invoice form with the current shop selected.

Cash receipt creation increments the tenant's receipt sequence in the same Firestore transaction that creates the receipt invoice and `cash_in` ledger entry and reduces `shop.balance`. Rules bind the invoice, transaction, amount, and resulting balance so none of those writes can succeed alone. Ledger-only `cash_in` remains a separate operation when no receipt document is required.

Sale invoices link to their `cash_out` ledger row and, when money is received, to the matching `cash_in` row. The shop-balance delta must be written atomically with those records. These links are enforced for admins and sellers; seller rules additionally verify the exact outstanding-balance delta. Non-stock invoicing defaults to disabled when a workspace setting is absent and must be explicitly enabled. Transaction descriptions use a multiline field for notes.

Sale and credit-note invoice numbers are allocated from `settings/{tenantId}.last_invoice_number` inside the same Firestore transaction as the business writes. Deterministic tenant-scoped invoice IDs make retries idempotent without a query-before-write race. Credit-note transactions also update the original invoice's cumulative credit amount and shop balance atomically. A credit-note void reverses both the stock restoration and that cumulative amount; sale voids restore sale stock and apply the selected refund mode.

Workspace administrators configure English, Arabic, and Urdu invoice names, subtitles, addresses, contact and registration details, template, accent color, and visible fields. New invoices store a header snapshot, and seller-created snapshots are checked against the workspace settings. PDF generation uses the invoice snapshot so later branding edits do not alter existing documents. Voiding a non-stock sale does not restore inventory.

## Release Surfaces

Web and Android builds use the same version from `app/pubspec.yaml` and `AppBrand`. Google Drive OAuth client IDs are deployment configuration, not source defaults; without them, file export remains available while Drive operations stay unavailable. Firebase Hosting must preserve no-cache headers for Flutter shell files and permit the Google static hosts required by Flutter web.

## Workspace Management UX

Workspace creation does not subscribe to a global user list. Editing an existing workspace loads active owner choices through a tenant-scoped user query. Full workspace edits are offered only to a platform super-admin with active access to that workspace; workspace admins retain only their seller-cap controls. Validation and provider failures always release the save state, keep the dialog open, and use the shared mapper's specific error rather than treating generic state errors as PDF failures. Android and web launcher icons are generated from the same source image, with no additional Android adaptive foreground inset.

New workspace setup creates a tenant-scoped owner account after the workspace exists, then assigns that active `tenant_admin` as owner. Workspace user deactivation updates the account and revokes every active bounded session slot in one transaction. Administrators can separately revoke or block selected device registrations and terminate selected sessions from the workspace security registry. Access slots are per user; the same installation on another account does not consume that account's slots. Device/session enforcement remains client-side under the Spark architecture.

## Access Registration and Workspace UX

Tenant and seller sign-in requires an application device registration and session before `AuthNotifier.signIn()` completes. The router keeps users on `/login` while registration runs, and mapped failures remain visible. The client reads only records matching the signed-in `tenant_id` and `user_id`, including direct reads of missing own slots; workspace registry collection-group queries are separately authorized and indexed. Existing records are re-read transactionally and each session records the selected `device_slot_id`. Server-sourced checks drive session expiry, foreground renewal, clock-skew feedback, and stale-slot recovery. Super-admin platform sessions are stored separately under `users/{uid}/platform_sessions` and do not grant tenant business access.

Session/device records remain client-enforced under the current Spark architecture. Firestore Rules cannot match ordinary authenticated business requests to a client session ID. Session termination prevents the supported app client from continuing, but alone does not block a modified client with a valid Firebase Auth token. Do not claim otherwise; server enforcement requires trusted claims or an equivalent authenticated backend.

Registration errors are passed to the existing localized login error mapper after cleanup; they are not all reported as a session-capacity failure. Workspace-management rendering tolerates an unavailable profile while auth settles. Create/edit notifier failures are rethrown after preserving AsyncValue state so the screen can keep the dialog open and show the mapped error.

## Frontend Audit Evidence

The 2026-10-03 frontend review is recorded in `AUDIT_REPORT_FOOTWEAR_ERP.md`. It is source-led and includes a live Android login capture, but authenticated role flows, theme/locale matrix screenshots, expanded-size visual QA, and profile-mode performance measurements remain pending because the required account password was not entered into the tooling session.

## Authentication, Session, and Access-Limit Policy

Tenant access registration reads the selected device slot from `session.device_slot_id`, verifies that its stored installation ID matches the current installation, and builds local `SessionModel` values with concrete timestamps rather than unresolved `FieldValue.serverTimestamp()` sentinels. `SessionGuard` defers missing-session enforcement during the 15-second registration grace, queues an authoritative recheck, rearms renewal after resume, resets timers when role or tenant changes, and passes the checked UID to every automatic sign-out. Revoked sessions are rejected during renewal. These records remain client-enforced under the Spark architecture.

Access limits have three scopes. Sellers use configurable `max_devices_allowed` and `max_active_sessions_allowed` values on their own workspace; the workspace's tenant admin can edit only those caps. Workspace admins (legacy admin/manager and tenant_admin) share the separate `settings/platform_access_policy` caps across workspaces; only a platform super-admin can change them. Super-admins use `users/{uid}/platform_sessions`, with a fixed two-device and one-active-session limit, independently of tenant pairing and approval.

The workspace pairing switch gates seller devices only. Workspace admins register active devices against the shared platform cap and can resume a matching pending device slot left by an older client only when that slot is still within the current cap; they do not approve their own devices. If `settings/platform_access_policy` is absent, Rules use the defaults of three devices and two active sessions. Platform-session re-registration may remove prior `revoked_at` and `terminated_by` markers only through the owner super-admin reactivation branch. Renewal rejects revoked-only access while tolerating unrelated revoked history beside a live record for the same installation. These session records still do not authorize or deny ordinary Firestore business requests.

## Invoice Integrity and PDF Behavior

Cash receipts carry a `cash_receipt_sequence` that must equal the `settings/{tenantId}.last_cash_receipt_number` increment in the same atomic write. Invoice voiding reads and updates the invoice, shop balance, stock documents, and reversal transactions in one Firestore transaction. Cash refunds reverse the full sale in the ledger, add the cash-out refund row, and reduce the receivable only by the outstanding amount. Non-stock invoice voids do not restore inventory.

Invoice PDFs use the captured workspace branding snapshot, localized payment method labels, mode-specific line tables, and `pw.MultiPage` with localized current/total page numbering. Long catalog invoices are covered by a page-count regression.
