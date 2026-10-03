# ShoesERP System Deep Dive

Last updated: 2026-10-03

## Backup and Restore

The backup screen delegates persistence and authorization to `DatabaseBackupNotifier`. It exposes encrypted file export separately from Google Drive upload, shows destination-specific timestamps, and keeps automatic backups limited to configured Android Drive access. A Drive upload uses the generated encrypted bytes directly and does not create a second local archive.

Backups are scoped to the signed-in user's workspace and role. Tenant administrators merge records into their own workspace; only a platform administrator with an active support workspace may choose replacement and prune records in that selected workspace. Sellers are restricted to their assigned-route data and cannot start workspace backups. Restore previews and confirmation copy must describe the operation the selected role can actually perform.

The restore preview shows one warning selected by the effective restore mode: merge keeps records absent from the archive, while replacement may prune within the selected support workspace. Restore re-authentication is owned by `AuthNotifier` and shared with destructive flush confirmation; backup restore uses backup-specific localized prompt text.

Local encrypted archives are listed through the shared restore picker and can be deleted after confirmation. Passphrases are required for encrypted backup creation and restore; creation asks for confirmation to catch entry mistakes. Errors from preference, file-list, export, Drive, and restore operations are surfaced through the shared error mapper.

## Workspace Archival

Workspace archival is an ordered provider operation. It disables member profiles and revokes their device registrations and active sessions before recording the workspace's archived state. Firestore access checks use the member's active profile gate so ordinary business reads and writes are denied after archival without adding repeated tenant reads to high-volume transaction rules. An archived workspace must not be reactivated or edited through an ordinary client update.

Device session creation is bound to an active device registration in the same authenticated user's workspace. Slot identifiers, configured limits, and the device/session identity must agree. Rules tests cover valid access, invalid slots, unregistered devices, and inactive workspace access.

## Release Surfaces

Web and Android builds use the same version from `app/pubspec.yaml` and `AppBrand`. Google Drive OAuth client IDs are deployment configuration, not source defaults; without them, file export remains available while Drive operations stay unavailable. Firebase Hosting must preserve no-cache headers for Flutter shell files and permit the Google static hosts required by Flutter web.
