# ShoesERP System Deep Dive

Last updated: 2026-10-03

## Backup and Restore

The backup screen delegates persistence and authorization to `DatabaseBackupNotifier`. It exposes encrypted file export separately from Google Drive upload, shows destination-specific timestamps, and keeps automatic backups limited to configured Android Drive access. A Drive upload uses the generated encrypted bytes directly and does not create a second local archive.

Backups are scoped to the signed-in user's workspace and role. Tenant administrators merge records into their own workspace; only a platform administrator with an active support workspace may choose replacement and prune records in that selected workspace. Sellers are restricted to their assigned-route data and cannot start workspace backups. Restore previews and confirmation copy must describe the operation the selected role can actually perform.

The restore preview shows one warning selected by the effective restore mode: merge keeps records absent from the archive, while replacement may prune within the selected support workspace. Restore re-authentication is owned by `AuthNotifier` and shared with destructive flush confirmation; backup restore uses backup-specific localized prompt text.

Local encrypted archives are listed through the shared restore picker and can be deleted after confirmation. Passphrases are required for encrypted backup creation and restore; creation asks for confirmation to catch entry mistakes. Errors from preference, file-list, export, Drive, and restore operations are surfaced through the shared error mapper.

## Workspace Archival

Workspace archival is an ordered provider operation. It disables member profiles and revokes their device registrations and active sessions before recording the workspace's archived state. Firestore access checks use the member's active profile gate so ordinary business reads and writes are denied after archival without adding repeated tenant reads to high-volume transaction rules. An archived workspace must not be reactivated or edited through an ordinary client update.

Device session creation is bound to an active device registration in the same authenticated user's workspace. Slot identifiers, configured limits, and device/session identity must agree. Pairing-required workspaces create pending device registrations and require administrator approval before session creation. Device removal and related session revocation are atomic; blocking cannot be reversed by the device owner. Registrations inactive for 30 days may be reclaimed. Rules tests cover valid access, invalid slots, unregistered devices, tenant-scoped registry queries, pairing, block/recovery, and inactive workspace access.

## Release Surfaces

Web and Android builds use the same version from `app/pubspec.yaml` and `AppBrand`. Google Drive OAuth client IDs are deployment configuration, not source defaults; without them, file export remains available while Drive operations stay unavailable. Firebase Hosting must preserve no-cache headers for Flutter shell files and permit the Google static hosts required by Flutter web.

## Access Registration and Workspace UX

Tenant and seller sign-in requires an application device registration and session before `AuthNotifier.signIn()` completes. The router keeps users on `/login` while registration runs, and mapped failures remain visible. The client reads only records matching the signed-in `tenant_id` and `user_id`, including direct reads of missing own slots; workspace registry collection-group queries are separately authorized and indexed. Existing records are re-read transactionally and each session records the selected `device_slot_id`. Server-sourced checks drive session expiry, foreground renewal, clock-skew feedback, and stale-slot recovery. Super-admin platform sessions are stored separately under `users/{uid}/platform_sessions` and do not grant tenant business access.

Session/device records remain client-enforced under the current Spark architecture. Firestore Rules cannot match ordinary authenticated business requests to a client session ID. Session termination prevents the supported app client from continuing, but alone does not block a modified client with a valid Firebase Auth token. Do not claim otherwise; server enforcement requires trusted claims or an equivalent authenticated backend.

Registration errors are passed to the existing localized login error mapper after cleanup; they are not all reported as a session-capacity failure. Workspace-management rendering tolerates an unavailable profile while auth settles. Create/edit notifier failures are rethrown after preserving AsyncValue state so the screen can keep the dialog open and show the mapped error.

## Frontend Audit Evidence

The 2026-10-03 frontend review is recorded in `AUDIT_REPORT_FOOTWEAR_ERP.md`. It is source-led and includes a live Android login capture, but authenticated role flows, theme/locale matrix screenshots, expanded-size visual QA, and profile-mode performance measurements remain pending because the required account password was not entered into the tooling session.
