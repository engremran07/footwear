# FootWear ERP — v3.10.20+1132 (web deployed; APK installed; AAB built)

A mobile-first enterprise resource planning system for footwear distribution businesses. Built with Flutter (Android + Web) and Firebase. Designed for route-based sales operations where an admin manages products, inventory, and sellers, while field sellers record customer transactions on their assigned routes.

The Android Play package is `footwear.com.pk`; its Firebase Android app
registration is configured for the same package.

## Android Updates and Password Autofill — v3.10.20+1132

Android supports flexible Google Play updates, required immediate updates for
Play priority 4+, and an owner-configurable minimum version gate. Firebase
Remote Config parameter `minimum_supported_version_code` defaults to `0`, so
the gate stays inactive until configured after the required version is
available to the intended channels. End-to-end update behavior requires a
Play-installed app. Login advertises Android username/email and password
autofill; the autofill context is submitted only after successful Firebase
Authentication, and the app does not store passwords.

Play version codes use `310190000 + buildNumber`, anchored one above the
recorded prior Play code `310191130`; current source `3.10.20+1132` yields
`310191132`. Split APKs add ABI-specific offsets; upload the signed AAB to
Play and compare its base code with the Console's latest accepted code. The
source and Gradle calculate AAB code `310191132`; bundletool was unavailable
for independent manifest extraction.

The local Rules Emulator reports `214 passing (1m)`; the full Flutter suite
reports `01:46 +823: All tests passed!`; `flutter analyze lib --no-pub`
reports `No issues found! (ran in 26.8s)` and `dart analyze test/` reports
`No issues found!`. Firestore Rules/indexes and Hosting deployed. Web reports
`EXIT: 0`; live `version.json` is `3.10.20+1132`, and the main bundle is
`no-cache, no-store, must-revalidate`. Split APKs built at 31.7/33.3/34.8 MB.
The signed 76,447,355-byte AAB reports `jar verified.`; its signer certificate
still requires confirmation against Play App Integrity, so it was not
uploaded. The ARM64 APK was copied and installed successfully on
`R5GL22RGT9V` (code `310193132`).

## Local Supervisor History and Seller Report Fix — 2026-10-30

Supervisors now receive tenant-scoped History and can use Seller Report without
Users-list access. History remains route-scoped for sellers. Supervisor report
candidates are derived from active route assignments; the centralized
`viewReports` capability controls visibility and generation. Focused tests
report `00:03 +13: All tests passed!`; both Dart analyzers are clean. This is
local, unreleased source: no version bump, build, deployment, or Git
publication was performed.

## Local Tenant Record Archive — 2026-10-31

Workspace admins can open a tenant-scoped archive of inactive shops, routes,
products, and variants from Settings. The listing cursor-pages each collection
and fails closed for sellers, supervisors, and unscoped users. Permanent
deletion stays disabled: a client cannot prove arbitrary references are absent
without race conditions, and no trusted purge service is authorized. This
change does not include restore controls.

The archive provider, screen, router, Settings, and permission suites passed
3, 20, 6, and 14 tests respectively. The full Flutter suite reports
`02:26 +834: All tests passed!`; the Rules Emulator reports
`215 passing (1m)`. `flutter analyze lib --no-pub` reports
`No issues found! (ran in 178.5s)` and `dart analyze test/` reports
`No issues found!`. Markdown lint exited 0 with no output. Release and
production deployment are separate and have not been performed for this
change.

## Profile and Invoice-Header Regression Fixes — v3.10.20+1131

Profile owners can now change their own display name through a self-scoped
provider write, regardless of workspace role. Leaving invoice-header settings
with edits prompts to Save, Discard, or Cancel; failed saves retain the draft.
The settings screen also provides invoice, statement, and receipt previews.
Android package identity is aligned to `footwear.com.pk` across Gradle,
`MainActivity`, Firebase, ProGuard, and Fastlane.

These changes were introduced in v3.10.20+1131 and are included in the
current v3.10.20+1132 APK and AAB. Current validation and deployment evidence
is recorded above.

## Arabic and Urdu PDF Glyph Correction — v3.10.20+1131

The medial Yeh corruption was traced to the `pdf 3.13.1` TrueType subset
writer: distinct Unicode code points that share a source glyph could be
assigned the wrong embedded glyph slot. A narrow local patch preserves each
code point's subset slot; the bundled Noto font and shaping pipeline are
unchanged. The regression and full Flutter suite pass, and generated Arabic
and Urdu statement, invoice, and receipt samples were visually inspected.
This fix was introduced in v3.10.20+1131 and is included in the current
v3.10.20+1132 APK and AAB.

## All-Shops Statement Export — v3.10.20+1132

Shop reports now use complete cursor-paged shop and route data rather than
the bounded live lists used by the screen. Seller statements include only
assigned routes. Empty shops with no opening balance no longer generate blank
ledger pages, and PNG export processes rasterized pages sequentially.

The web build and Hosting deployment succeeded. The v3.10.20+1132 ARM64 APK
was installed on `R5GL22RGT9V`. The signed AAB was built and verified locally,
but has not been uploaded to Play while its signing certificate awaits
confirmation against Play App Integrity.

## Local Workspace-Management Feedback and CI Gate 14 — Unreleased

Workspace creation and support-access feedback now distinguish completed
creation/access from cleanup or seat-reconciliation failures. Password
validation preserves the exact input, workspace-administration failures map
to permission denied, and support-access start/end check a fresh authenticated
super-admin profile. CI Gate 14 checks literal form-route destinations and
ignores full-line comments.

The full Flutter suite reports `02:21 +824: All tests passed!`;
`flutter analyze lib --no-pub` reports
`No issues found! (ran in 65.1s)`; `dart analyze test/` reports
`No issues found!`; and the Rules Emulator reports `214 passing (1m)`.
The complete Gate 14 script parsed from the workflow YAML reports
`✅ No context.go() for form routes`. This work is local and unreleased. No
Rules/indexes changed, and no build, install, deployment, commit, or push was
performed. The production workspace-exit denial and P1-04 remain unresolved;
Play signer confirmation is also required before AAB upload.

## Local Financial Safeguards and Minor-Unit Compatibility — Unreleased

The current local source enforces a `999999.99` maximum for invoice, receipt,
standalone cash, and transaction-correction writes across providers and
Firestore Rules. SAR and PKR currently share this provisional maximum; no
currency-specific policy has been established. New sale, credit-note, and
receipt numbers use one tenant-wide high-water sequence with `INV-`, `CN-`,
and `REC-` prefixes and no device-clock year. Allocation continues above the
greater of the legacy invoice and receipt counters, and Firestore Rules enforce
the same sequence in linked atomic writes. Receipt counter updates carry a
same-batch `last_cash_receipt_id` link to the receipt invoice. Existing invoice
identifiers remain unchanged.

A staged integer minor-unit compatibility layer now dual-reads and dual-writes
the optional `financial_minor_units` companion map for shop, transaction, and
invoice financial fields while preserving existing legacy values. A verified,
tenant-scoped backup preview and bounded admin backfill API are available;
the backfill changes companion fields only and has not been run. Legacy doubles
remain authoritative for compatibility, Firestore Rules do not yet require
minor-unit values, and historical reconciliation plus the client rollout and
strict cutover remain unresolved. No production migration is represented by
this local work. Firestore Rules/indexes were subsequently deployed after
`207 passing (56s)` in the Rules Emulator; this deployment does not include
Hosting or an app release. The user reports that invoice creation, non-stock
sales, and cash receipts now succeed for admin, supervisor, and seller on the
designated JBM `Testing` route / `owerty` test shop. The original denied
Rules condition remains unconfirmed because its Firebase error code and live
counters were not captured. The live log capture also showed background
Firestore DNS `UNAVAILABLE` and App Check token API 403/retry warnings; these
are separate follow-up signals, not evidence that the invoice writes failed.

## v3.10.15+1126 Contextual Record Actions

Record rows across routes, shops, products, inventory, invoices, transactions,
notifications, dashboard, and reports now share a contextual-action
presentation. It supports touch long-press, web secondary click, keyboard
context-menu shortcuts, and screen-reader custom actions while retaining
existing row taps and provider-backed handlers. Actions are filtered and
rechecked through the existing capability policy; the UI is not an
authorization boundary. Full serial Flutter suite: `02:40 +716: All tests
passed!`; `flutter analyze lib --no-pub`: `No issues found! (ran in 16.2s)`;
`dart analyze test/`: `No issues found!`. Web build: `EXIT: 0`; Hosting and
Firestore Rules/indexes each reported `Deploy complete!`; live
`version.json` reports `3.10.15+1126` with `no-store, must-revalidate,
no-cache`. Split APKs built at 31.4/32.9/34.5 MB and verified with APK v2.
The ARM64 APK was copied and installed on `R5GL22RGT9V` (`1 file pushed`,
`Success`, versionCode `310153126`). The signed 72.3 MB AAB reports
`jar verified.`; its locally untrusted self-signed certificate and missing
timestamp do not establish Play Console upload-key acceptance. No Play
Console upload occurred. Authenticated visual and manual assistive-technology
acceptance remain unverified.

## v3.10.14+1125 Notification Visibility and Android Alerts

Referenced-shop visibility lookups now run in batches of five IDs so larger
workspaces stay within Firestore Rules access-call limits without relaxing
tenant or role checks. The 50-shop emulator regression covers workspace admins
and supervisors. Android notification-center alerts are opt-in and
foreground-only; they reuse the existing tenant-scoped feed and visibility
providers, create no extra Firestore listener, and do not require FCM or a
server sender. Permission is requested only after the user enables alerts.
Sellers and platform super-admins remain excluded.

The full Flutter suite reports `01:29 +708: All tests passed!`; the full
Rules Emulator reports `191 passing (56s)`; both Dart analyzers are clean.
The split APKs verify with APK v2; ARM64 was installed on `R5GL22RGT9V`
(`Success`, versionCode `310143125`). The signed AAB built at 75,804,395
bytes and reports `jar verified.`; its self-signed local certificate warning
does not establish Play Console upload-key acceptance. Web build:
`EXIT: 0`; Firestore Rules/indexes and Hosting each reported
`Deploy complete!`; live `version.json` reports `3.10.14+1125`. No Play
Console upload occurred. Emulator success is not confirmation from an
authenticated JBM Impex session.

## Archived Workspace Access Gate (v3.10.13+1124)

The app shell waits for the signed-in member's tenant record before mounting
business routes. Archived or unavailable workspace state shows localized
retry and sign-out actions instead of allowing business screens to surface
permission-denied errors. Platform super-admins remain able to use the
separately authorized workspace restoration path. Firestore Rules continue to
enforce business access independently.

The archived-workspace routing regression failed before the gate and passed
afterward. The focused routing suite reported `00:10 +16: All tests passed!`;
`flutter analyze lib --no-pub` reported
`No issues found! (ran in 4.8s)`, and `dart analyze test/` reported
`No issues found!`. This gate is included in v3.10.13+1124; Hosting and
Firestore Rules/indexes are deployed.

## 2026-10-28 Support-Context Listener Expiry (v3.10.13+1124)

The eight-hour selected-super-admin context expiry now also closes the
non-`autoDispose` workspace settings listener. The provider checks context
before selecting `settings/{tenantId}`, invalidates at expiry, cancels its
timer on disposal, and returns a no-active-workspace state rather than
re-subscribing to an expired tenant document. Firestore Rules remain the
authorization boundary. The regression failed before the fix with
`tenant-42` instead of `__no_active_workspace__`; the focused suite reported
`00:11 +60: All tests passed!`; `flutter analyze lib --no-pub` reported
`No issues found! (ran in 5.5s)`; `dart analyze test/` reported
`No issues found!`. The change is included in the v3.10.13+1124 APK, AAB, and
web build.

## v3.10.13+1124 Dependency and Android Build Release

The app's Flutter/Dart baseline is Flutter `3.47.8` / Dart `3.13.7`. Direct
Flutter packages were upgraded to their latest resolver-compatible versions;
five newer transitive releases remain blocked by parent or SDK constraints and
were not forced. Android tooling now matches the Flutter 3.47.8 template:
Gradle `9.3.1`, AGP `9.1.0`, Kotlin Gradle Plugin `2.4.0`, and Google Services
`4.5.0`. The Android app build script uses AGP's public `ApplicationExtension`
and Kotlin's typed `compilerOptions`.

The split release APK build succeeded: ARMv7 `31.2 MB` (versionCode
`310132124`), ARM64 `32.8 MB` (`310133124`), and x86_64 `34.3 MB`
(`310135124`). All three APKs verified with APK Signature Scheme v2. The
signed Play Console AAB built at `72.1 MB`; `jarsigner -verify` reported
`jar verified.` and also reported a self-signed, locally untrusted certificate
chain with no timestamp. This verifies signature integrity, not Play Console
upload-key acceptance. The ARM64 APK (`32.8 MB`, versionCode `310133124`) was
copied to the connected phone and installed successfully. Firestore
Rules/indexes and Hosting were deployed; the live `version.json` reports
`3.10.13+1124`. The 23 remote indexes and two field overrides absent from the
local definition were preserved. Flutter's KGP migration warning from the app
and Firebase plugins remains visible and is not suppressed. Git commit/push
and Play Console upload have not been performed. The reported notification
feed permission denial remains unresolved because its failing query/write has
not been identified from an authorized runtime trace.

> **v3.10.11+1122 deployment:** Backup scope feedback is visible
> to workspace members without disclosing the workspace name, and app startup
> no longer requests unrelated camera, storage, photo, or notification
> permissions. Full Flutter suite: `02:09 +669: All tests passed!`;
> `flutter analyze lib --no-pub`: `No issues found! (ran in 36.3s)`;
> `dart analyze test/`: `No issues found!`; web build: `EXIT: 0`.
> Split APKs: ARMv7 30.7 MB, ARM64 32.2 MB, x86_64 33.7 MB. The signed
> Play Console AAB is 54.8 MB; APK v2 signatures and the AAB JAR signature
> verified. ARM64 was copied and installed on `R5GL22RGT9V`
> (`1 file pushed`; `Success`, versionName `3.10.11`, versionCode
> `310113122`). Hosting and Firestore Rules/indexes were subsequently
> deployed; the live `version.json` reports `3.10.11+1122`. There was no Play
> upload, commit, or push.

## v3.10.12+1123 Mixed-Script UI Font Follow-up

Shared English text styles now fall back to bundled Arabic and Urdu fonts for
script-specific Firestore values while preserving the English brand fonts.
Arabic and Urdu locales retain their own primary font. PDF font policy is
unchanged. Focused tests: `00:01 +12: All tests passed!`; full suite:
`01:31 +671: All tests passed!`; `flutter analyze lib --no-pub`:
`No issues found! (ran in 16.1s)`; `dart analyze test/`:
`No issues found!`. Web build:
`EXIT: 0`; Hosting: `Deploy complete!`; live `version.json` reports
`3.10.12+1123`. APK/AAB builds and phone delivery remain blocked pending at
least 3.2 GB free RAM and an attached ADB device. Details are in the latest
session log.

One unauthenticated local browser reload produced nine Firebase-initialization
debug messages and no console warnings/errors, page errors, or failed
requests. A later authenticated dashboard did expose the mixed-script Noto
fallback issue fixed in v3.10.12; after deployment, the browser redirected to
login, so authenticated rendering could not be rechecked. The reported
inspector counts conflict (18 messages versus 20 across the stated
categories), and authenticated PDF rendering and the complete original
inspector inventory remain unverified.

## Local 2026-10-28 Workspace Follow-up (Unreleased)

The invoice-header non-stock switch now saves its tenant setting immediately.
It writes only `allow_non_stock_invoices`; other unsaved header edits remain
local. Failed writes restore the previous switch value and show mapped
feedback. Workspace admins can view maintenance components, but all reset
actions remain disabled and fail-closed. The Settings entry follows the same
`PermissionPolicy` route decision as `/settings/flush`; it is shown to legacy
and tenant workspace admins, not sellers, supervisors, or unscoped platform
super-admins. Notification access is limited to admin/manager, tenant_admin,
and supervisor roles; sellers and platform super-admins are excluded.

Focused affected tests: `00:00 +54: All tests passed!`; full Flutter suite:
`01:26 +684: All tests passed!`; `flutter analyze lib --no-pub`:
`No issues found! (ran in 9.1s)`; `dart analyze test/`: `No issues found!`.
These local changes have not been versioned, built, deployed, or delivered to a
phone; do not infer production behavior from local tests.

## Local Archived-Shop and Notification Integrity Follow-up — 2026-10-30

Archived shops cannot receive new sale invoices or cash-out/debt transactions.
Cash-in collection and cash-receipt invoices remain available so existing
balances can still be collected. The provider and Firestore Rules enforce this
distinction independently.

Soft-deleting a standalone cash transaction now retires its deterministic
notification in the same atomic write as the soft-delete and exact shop-balance
reversal. Delayed notification publication checks the persisted source
transaction, and retired items are omitted from notification feeds and
foreground alerts. Full Flutter suite: `01:50 +785: All tests passed!`;
Rules Emulator: `213 passing (1m)`; `flutter analyze lib --no-pub`:
`No issues found! (ran in 151.5s)`; `dart analyze test/`:
`No issues found!`. The hot-restart attempt was unavailable because no
Flutter app was connected to the Dart Tooling Daemon. The Rules changes remain
local and undeployed; no release build, Hosting deployment, phone delivery,
commit, or push was performed. P1-04 and older-client rollout blockers remain
unresolved.

## Local Statement Export and Shop-Detail Density Follow-up — 2026-10-30

The route-level multi-shop account statement now offers the same per-export
Arabic/Urdu choice as single-shop statements. The selected language pair drives
PDF labels and the shared workspace header; PDF-derived image, print, and
share outputs remain byte-identical. The invoice-header language control stays
hidden while legacy saved values remain readable.

The shop-detail contextual action button now shares the phone/WhatsApp row
above the Total In/Total Out summary. Existing role filtering and guarded
provider actions are unchanged. Focused export, receipt, settings, and
role-placement tests passed; the full Flutter suite reported
`02:00 +806: All tests passed!`, and both analyzers are clean. This is local,
unreleased source; no version, artifact, deployment, device, or Git publication
operation was performed.

## Local Notification and Ledger Integrity Follow-up

The notification feed now survives a same-user profile refresh: the cached
profile is considered only when its UID matches the settled Firebase Auth UID,
and auth loading/errors or a UID mismatch remove tenant scope. This fixes a
reproduced loading-state regression rather than weakening role or tenant
authorization. Focused widget tests: `00:03 +9: All tests passed!`;
notification visibility/provider tests: `00:00 +13: All tests passed!`;
full Flutter suite: `01:36 +689: All tests passed!`; both analyzers are clean.
The source change is local and unreleased; production behavior has not been
verified, and release/deployment/device/Git operations were not performed.

## Local Seller Notification Cooldown Fix

The seller notification cooldown that could drop a notification after a
successful financial write has been removed. Source-specific deterministic
IDs and Firestore Rules checks now tie each best-effort seller notification
to its persisted invoice or standalone transaction. This preserves
post-commit notification behavior and does not make ledger writes depend on
notification availability.

The full local Rules Emulator reports `190 passing (48s)` and focused
notification Flutter tests report `00:03 +20: All tests passed!`. Rules are
not deployed. The separately reported feed permission/flicker issue still
requires evidence identifying the denied production request.

## Local Dashboard Cache Tenant Isolation

Dashboard last-good metrics are now scoped to the authenticated user and
effective tenant/workspace context, including role, active state, support
session, and assigned routes. A stale fallback from one workspace is not shown
while another workspace's metric streams load. Same-workspace refresh still
uses its own cached metrics.

The regression reproduced workspace A's `metrics:11/22` under workspace B
before the fix. Dashboard tests report `00:09 +5: All tests passed!`;
`flutter analyze lib --no-pub` reports
`No issues found! (ran in 8.1s)`, and `dart analyze test/` reports
`No issues found!`. This source change is local and unreleased.

The notification provider now sends server timestamps for mark-one and
mark-all. Firestore Rules allow only an unread-to-read transition where both
read fields change together and the timestamp equals request time. Notification
read/update access requires an authorized operational role and a concrete
active tenant; seller, platform super-admin, global/unassigned, inactive, and
cross-tenant paths remain denied. Keyed standalone transaction creates use a
deterministic tenant-specific document ID and atomically commit the ledger
entry and shop balance. Overlapping notifier writes now surface a rejection
instead of returning success-shaped no-op.

Focused Flutter tests: `00:00 +21: All tests passed!`; application analysis:
`No issues found! (ran in 15.4s)`; Rules Emulator: `185 passing (46s)`.
The full emulator log included non-failing expression-limit diagnostics in
other Rules paths. These source changes remain local; full-suite validation,
release artifacts, phone delivery, Rules/Hosting deployment, and Git
publication are pending.

> **Local audit follow-up, not yet deployed:** super-admin workspace selection
> and exit/switch now require same-batch, linked append-only start/end records;
> monetary amount fields preserve Arabic-Indic and Eastern-Arabic numerals.
> The version and trilingual changelog are synchronized. Split APKs were built,
> and the ARM64 APK was copied to and installed on `R5GL22RGT9V`. The signed
> AAB was built at 54.8 MB and `jarsigner` reported `jar verified.`. Production
> Rules/Hosting, Play Console upload, commit, and push remain separate release
> gates.
>
> **Local v3.10.7+1118 follow-up (not deployed):** Cash-receipt PDFs now use
> a compact bilingual body based on the supplied receipt reference, preserve
> the existing shared workspace header, and support two optional receipt
> footer contact numbers. Arabic and Urdu samples were visually inspected.
> Full Flutter suite: `01:29 +639: All tests passed!`; focused PDF/settings
> suite: `00:15 +24: All tests passed!`; both analyzers clean; Rules Emulator:
> `154 passing (30s)`. Split APKs: ARMv7 30.7 MB, ARM64 32.2 MB,
> x86_64 33.7 MB; signed AAB: 54.8 MB. All APK signatures verified and the
> AAB reported `jar verified.`. ARM64 was copied to `/sdcard/Download/` and
> installed on `R5GL22RGT9V` (`Success`), versionName `3.10.7`,
> versionCode `310073118`. Firestore Rules/indexes and Hosting were not
> deployed; no commit or push was performed.
>
> **Local v3.10.8+1119 follow-up (not deployed):** Logo-enabled financial
> PDFs now use one shared header with the company logo centered between
> English and Arabic/Urdu details, at the same slightly larger size. The
> generic flat-table fallback uses the shared header too. The company-name
> line scales to fit instead of wrapping in the compact A5 receipt header.
> Supervisors can read and mark their own workspace's notifications; sellers
> remain excluded. Tenant-keyed notification feed and shop listeners prevent
> cached rows from crossing a workspace switch; missing/global scope does not
> query. Root platform settings remain available without exposing tenant
> settings descendants. Rules Emulator: `172 passing (42s)`; full Flutter
> suite: `01:20 +654: All tests passed!`; `flutter analyze lib --no-pub`:
> `No issues found! (ran in 5.6s)`; `dart analyze test/`:
> `No issues found!`; updated changelog test: `00:00 +10: All tests passed!`.
> Version `3.10.8+1119` produced split APKs (30.7/32.2/33.7 MB) and a signed
> 54.8 MB Play Console AAB. APK v2 and AAB JAR signatures verified. ARM64
> copied to and installed on `R5GL22RGT9V` (`Success`), versionName `3.10.8`,
> versionCode `310083119`. Production deployment remains unperformed.
>
> **v3.10.9+1120:** Active workspace admins,
> tenant admins, supervisors, and route-scoped sellers can create sale
> invoices and cash receipts without gaining settlement, credit-note,
> correction, or void rights. Firestore Rules reject unsupported invoice
> types, bind invoice counters to same-batch sale/credit-note records, and
> enforce seller identity on invoice creation. A 15-workspace isolation test
> covers shop and invoice reads. Rules Emulator: `180 passing`; full Flutter
> suite: `01:21 +655: All tests passed!`; both analyzers are clean. Fresh
> release artifacts use synchronized version `3.10.9+1120`: split APKs are
> ARMv7 30.7 MB, ARM64 32.2 MB, and x86_64 33.7 MB; the signed Play Console
> AAB is 54.8 MB. APK v2 signatures and the AAB JAR signature verified.
> Web build: `EXIT: 0`; Hosting and Firestore Rules/indexes each reported
> `Deploy complete!`. Live `version.json` reports `3.10.9`, build `1120`;
> shell and main bundle return `no-cache, no-store, must-revalidate`.
> ARM64 was copied to the connected phone and installed (`Success`),
> versionName `3.10.9`, versionCode `310093120`. No Play Console upload,
> commit, or push was performed. The wider 33-finding audit remains open.
>
> **v3.10.6+1117 (2026-10-25)** — Account-statement PDFs now use three columns: English report details on the left, shop name and date range in the center, and selected Arabic or Urdu details on the right. This release also includes the tenant-scoped supervisor role, legacy-admin Users/merge-backup access, notification listener stability, and the APK/AAB Gradle fix.
> Verification: full Flutter suite `01:14 +633: All tests passed!`; focused PDF suite `00:01 +12: All tests passed!`; `flutter analyze lib --no-pub`: `No issues found! (ran in 6.3s)`; `dart analyze test/`: `No issues found!`; Firestore Rules Emulator: `152 passing (30s)`; Markdown lint and `git diff --check` exited 0.
> Web build `EXIT: 0`; Firebase Hosting and Firestore Rules/indexes each reported `Deploy complete!`. Live `/`, `index.html`, `version.json`, and `main.dart.js` returned HTTP 200 with no-store/no-cache/must-revalidate headers; `version.json` reports `3.10.6+1117`. The 23 remote indexes and 2 field overrides absent locally were preserved without `--force`.
> Split APKs: ARMv7 30.7 MB, ARM64 32.2 MB, x86_64 33.7 MB; signed AAB 54.8 MB. APK v2 and AAB JAR signature verification passed. ARM64 installed on `R5GL22RGT9V` (`Success`), versionName `3.10.6`, versionCode `310063117`.
>
> **Earlier local follow-up:** Notification refreshes preserve the last
> visible shop-filtered feed while reloading and expose mapped read-state
> failures. RTL statement rows and summary columns are physically pinned;
> Arabic and Urdu samples were inspected. Full Flutter suite:
> `01:14 +638: All tests passed!`; Rules Emulator: `154 passing (54s)`;
> both analyzers and Markdown lint are clean.
> Receipt-reference matching and its release build are tracked in the
> v3.10.7+1118 local follow-up above.
> **v3.10.5+1116 (2026-10-25)** — Adds a tenant-scoped supervisor role for operational routes, shops, products, inventory, invoices, and reports without user-administration, notifications, settings, backup, financial-correction, or invoice-void privileges. Legacy admins regain workspace user-list and merge-only backup access. Notification shop-visibility subscriptions no longer restart for read-state-only changes. Android versionCode generation now preserves Play Store upgrade ordering. The local v3.10.5 artifacts were superseded by v3.10.6 before production deployment.
> **v3.10.4+1115 (2026-10-25)** — Super-admin workspace support-access feedback now distinguishes start, switch, end, and failure states. Shared financial PDF rows preserve English-left and selected Arabic/Urdu-right ordering under RTL pages. Urdu remains readable Naskh-style; a Nastaliq renderer migration is deferred until logo, selectable-text, pagination, and Web/Android report parity are proven.
> Verification: `01:16 +628: All tests passed!`; focused access/PDF suite `00:11 +65: All tests passed!`; `flutter analyze lib --no-pub`: `No issues found! (ran in 132.4s)`; `dart analyze test/`: `No issues found!`; Rules Emulator: `147 passing (29s)`.
> Web build `EXIT: 0`; Hosting and Firestore Rules/indexes each reported `Deploy complete!`; 23 remote indexes and 2 field overrides not listed locally were preserved. Split APKs: ARMv7 30.7 MB, ARM64 32.2 MB, x86_64 33.6 MB. No Android device was connected, so installation was skipped. Google Drive OAuth remains unconfigured.
> **v3.10.3+1114 (2026-10-25)** — Workspace member lists and seat reconciliation now include legacy active profiles without a display name. The release also includes on-device logo resizing, tenant-scoped admin/seller role management, accurate seat reconciliation, and compact bilingual single-page cash receipts without a balance-movement block. Google Drive backup remains disabled until OAuth client IDs are configured.
> Verification: `01:21 +623: All tests passed!`; `flutter analyze lib --no-pub`: `No issues found! (ran in 15.3s)`; `dart analyze test/`: `No issues found!`; Firestore Rules Emulator: `146 passing (37s)`.
> Web build `EXIT: 0`; Hosting reported `Deploy complete!`. Firestore Rules/indexes were deployed with the preceding v3.10.2 build and did not change in this query-only hotfix. Split APKs: ARMv7 30.7 MB, ARM64 32.2 MB, x86_64 33.6 MB. ARM64 installed on `R5GL22RGT9V` (`Success`), versionName `3.10.3`, versionCode `3103414`.
> **v3.10.2+1113 (2026-10-25)** — Workspace logos are automatically resized on-device to fit the Firestore limit; tenant admins can manage workspace admin/seller roles within safeguards; seat totals reconcile against the selected workspace’s live roster; cash receipts use a compact bilingual single-page table without a balance-movement block.
> **v3.10.1+1112 (2026-10-25)** — Workspace management now presents owner contact and verification details, live role counts, and the 10-member free-tier capacity. Cash receipt screens and PDFs provide a richer payment, balance, and recipient breakdown. Google Drive backup is disabled in this build until OAuth client IDs are securely configured; encrypted phone archives remain available.
> Verification: `01:20 +623: All tests passed!`; `flutter analyze lib --no-pub`: `No issues found! (ran in 98.8s)`; `dart analyze test/`: `No issues found!`; Rules Emulator: `140 passing (31s)`.
> Web build `EXIT: 0`; Hosting and Rules/indexes deployments reported `Deploy complete!`. Split APKs: ARMv7 30.6 MB, ARM64 32.1 MB, x86_64 33.6 MB. ARM64 installation on `R5GL22RGT9V` reported `Success`; device versionName `3.10.1`, versionCode `3103212`.
> **v3.10.0+1111 (2026-10-25)** — Release sync and operational hardening: invoice-header and workspace settings now refresh from live Firestore snapshots while preserving unsaved edits, notification visibility hides inactive/deleted shops, local workspace logo processing keeps PNG transparency and size guidance, and the app branding is attributed to Aeonis Labs. The release is validated locally with the full Flutter suite (`619` tests), Firestore Rules Emulator (`134 passing`), and clean analyzers; production release deployment, APK install, commit, and push remain explicit release actions.
> **v3.9.85+711 (2026-10-25)** — Financial PDFs use English-Arabic labels by default, with a workspace-admin option for English-Urdu, and retain the saved workspace header in invoice snapshots. Ledger summary and table labels use explicit per-line RTL direction. Seller sale/receipt Rules validate optional legacy header fields and the selected language pair against workspace settings. Local verification: full Flutter suite `609` passed; Rules Emulator `133` passed; both Dart analyzers clean. Release deployment and Git publication are pending.
> **v3.7.5+53 (2026-04-15)** — Current baseline includes the post-audit hardening pass: provider admin guards, invoice and rules validation tightening, export query caps, model `copyWith`/equality cleanup, theme-safe shimmer, and workflow normalization on Flutter 3.41.6 with expanded test reporting.
> **v3.9.50+89 (2026-08-18)** — Tenant permissions are enforced across business collections, invoice-generated ledger records carry workspace identity, and Google Drive backup configuration is shared by web and Android builds.
> **v3.9.53+92 (2026-10-03)** — Tenant admins merge encrypted backups into their own workspace; selected platform admins can prune only within their active support workspace. Unsupported roles and workspace-less accounts receive recovery guidance instead of being treated as sellers.
> **v3.9.54+93 (2026-10-03)** — Status labels are localized and high-contrast status colors are more legible.
> **v3.9.58+97 (2026-10-03)** — Encrypted file and Drive backup destinations are explicit, workspace restore matches access scope, local archives can be deleted, and workspace archival revokes member access.
> **v3.9.59+98 (2026-10-03)** — Workspace-admin and seller sign-in now use scoped device-session records; workspace setup errors remain visible, and login system-bar contrast follows the active theme.
> **v3.9.60+99 (2026-10-10)** — Sign-in waits for access registration; device pairing, renewal, stale-device recovery, and platform-operator sessions have explicit controls. Session records remain client-enforced under the Spark architecture.
> **v3.9.61+100 (2026-10-15)** — Invoice creation supports stock sales, non-stock catalog sales, and cash receipt invoices. Workspace admins configure bilingual invoice headers, and generated PDFs retain the header snapshot.
> **v3.9.75+102 (2026-10-15)** — Sign-in and session renewal are guarded against stale records and account-switch races. Sellers use workspace-specific dynamic device/session limits; workspace-admin limits are shared and controlled by the platform super-admin; platform sessions remain separate. Invoice voiding is atomic and long invoice PDFs paginate. Android updates can be installed over the device's current package without removing app data.
> **v3.9.76+702 (2026-10-16)** — Workspace-admin sign-in no longer follows seller pairing approval. Session re-registration, renewal, and logout handle revoked and pending records more reliably.
> **v3.9.77+703 (2026-10-16)** — Non-stock invoicing is disabled until explicitly enabled per workspace. Sale, receipt, return, and invoice-number updates are transactionally linked to ledger, balance, and stock changes; shop transaction descriptions accept multiple lines.
> **v3.9.78+704 (2026-10-16)** — Workspace owners are selected within the active workspace, editing requires active platform access, save errors are classified accurately, and launcher icon sizing is consistent across Android and web.
> **v3.9.79+705 (2026-10-17)** — Workspace setup provisions an owner account; workspace admins can disable sellers and revoke or block their device/session access; PWA icon URLs refresh installed artwork.
> **v3.9.81+707 (2026-10-22)** — Firebase Authentication remains the only sign-in mechanism, without app-managed device pairing or custom session approvals. Workspace admins retain tenant-scoped routes, shops, and transaction CRUD. Firestore Rules enforce active tenants, zero-balance shop creation, and atomic standalone ledger/shop balance links.
> **v3.9.83+709 (2026-10-23)** — Multi-currency account and seller reports preserve route currencies and group PDF totals without adding unlike amounts. Screen workflows include retryable route/workspace loading, export progress/error feedback, safe form loading, and reduced-motion/accessibility improvements. Full Flutter suite: 567 tests passed. Web and split APKs built; Hosting and Firestore Rules/indexes deployed; ARM64 APK installed on R5GL22RGT9V. Authenticated visual acceptance remains pending.
> **Unreleased 2026-10-24 source** — Invoice idempotency and first-allocation reads of missing documents are now explicitly tenant/role scoped in Firestore Rules; workspace creation may read a missing settings document only before its tenant exists. Seller invoice authorization was simplified to preserve Rules expression headroom. Admins without available self-allocated stock receive localized guidance. Local Rules Emulator: 128 passing; focused invoice widget tests: 2 passing. Production deployment and release operations remain pending.
> **Unreleased 2026-10-24 lifecycle recovery** — Selected platform super-admins can restore an inactive workspace using an audited support context and explicit confirmation. Archive/restore changes the tenant lifecycle record only; member profiles are preserved, and business access remains denied until restoration. Client-side bulk reset and legacy plaintext utilities remain disabled.
> **Unreleased 2026-10-24 frontend hardening** — Shared animation presets and custom router fade/slide transitions honor reduced-motion preferences; the responsive login layout caps content to the available viewport. Regression tests cover six widths in EN/AR/UR. Full Flutter suite: `01:01 +589: All tests passed!`; `flutter analyze lib --no-pub`: `No issues found! (ran in 102.3s)`; `dart analyze test/`: `No issues found!`. The signed-out local browser render was checked. A debug APK attempt failed at `:app:mergeDebugJavaResource` because of insufficient system resources; no release APK or production operation was performed.
> **Unreleased 2026-10-24 operations UX** — Workspace invoice-header and settings forms follow remote Firestore snapshots without overwriting dirty edits. Shop totals keep SAR/PKR separate and unabridged; invoice Pending filters outstanding sales; shop, invoice, ledger, and settings data surfaces support pull-to-refresh. Invoice voiding includes tenant-scoped linked settlement rows, including legacy payments, and hides voided entries from customer statements while retaining admin history; credit-balance voids preserve actual cash-in payments as customer credit. Receipt PDFs emphasize the amount received and include payment/balance/signature details. Full Flutter suite: `01:08 +599: All tests passed!`; invoice-void tests: `00:00 +22: All tests passed!`; both analyzers are clean. Cross-device acceptance and production/release operations remain unperformed.
> **v3.9.84+710 (2026-10-24)** — Workspace backup reads now use tenant-authorized settings document paths and validate concrete archive collection keys. Selected platform super-admin and seller backup controls retain their scoped access; seller restore rejects another seller's inventory records. Role tests: 16 passed; full Flutter suite: 603 passed; Rules Emulator: 132 passed. Rules/indexes deployed; split APKs built and ARM64 installed on `R5GL22RGT9V`. Hosting and Git publication are pending because pushing to `main` triggers the Hosting workflow.
> **v3.9.85+711 (2026-10-25)** — Financial PDFs use English-Arabic labels by default, with a workspace-admin option for English-Urdu, and retain the saved workspace header in invoice snapshots. Ledger summary and table labels use explicit per-line RTL direction. Seller sale/receipt Rules validate optional legacy header fields and the selected language pair against workspace settings. Local verification: full Flutter suite `609` passed; Rules Emulator `133` passed; both Dart analyzers clean. Release deployment and Git publication are pending.
>
> Prior version bullets below are historical release notes.

---

## Features

### Admin

- **Dashboard** — live stats with shimmer loading, cash flow BarChart, alerts banner, admin speed-dial FAB
- **Products & Variants** — manage SKUs with size/colour variants, carton/dozen/pair stock tracking, share button
- **Routes** — define delivery routes and assign sellers, performance strip, shops sorted by debt
- **Shops (Customers)** — full CRUD with balance ledger, balance trend LineChart, days-overdue indicator
- **Inventory** — warehouse stock allocation with low-stock warning badges
- **Transactions** — cash-in / cash-out ledger with running balance
- **Invoices** — stock and non-stock sales, cash receipt invoices, credit notes, void/paid lifecycle, and workspace-configurable bilingual PDF headers
- **Reports** — monthly cash flow BarChart, outstanding PieChart, PDF/Excel/image export
- **User Management** — create/edit permitted admin and seller accounts, disable/reactivate accounts, and send password-reset emails
- **Settings** — workspace-scoped company name, logo (base64 ≤50 KB), pairs-per-carton, and business preferences
- **Profile** — name, language, theme and password controls for all users

### Seller

- View assigned route and shops
- Record cash-in / cash-out transactions for assigned shops
- Create stock sales, workspace-enabled non-stock invoices, and cash receipt invoices from a shop
- View account statements and invoices
- Dashboard and inventory suppress transient permission errors during startup

### Multilingual

English, Arabic (RTL), Urdu (RTL) — 372+ translation keys synced across all screens and PDF exports.

---

## Tech Stack

| Layer | Technology |
| --- | --- |
| Mobile + Web | Flutter 3.47.8 — Android split-per-ABI APKs + Firebase Hosting web |
| Dart SDK | >=3.13.0 |
| State management | flutter_riverpod 3.4.3 (`NotifierProvider`, `AsyncNotifierProvider`, `StreamProvider`) |
| Navigation | go_router 18.1.1 with role-based redirect guards |
| Backend / Auth | Firebase (Firestore + Auth only) — zero Storage, zero Cloud Functions |
| Design system | AppTokens, AppAnimations, AppSanitizer, AppInputFormatters |
| Charts | fl_chart 1.3.0 (BarChart, LineChart, PieChart) |
| PDF export | Shared `pdf` builders embed Noto Sans Arabic; Arabic shaping requires `--dart-define=use_arabic=true` and otherwise fails closed |
| Excel export | Custom xlsx writer (`excel_export.dart`) using `archive ^4.0.0` |
| Print / Share | `printing` + share_plus 13.3.1 |
| Image compression | `flutter_image_compress` (base64 logo) |
| Animations | `flutter_animate` + `shimmer` |

Shared interactive controls use the design system's minimum target token.
Optional shared animation presets, empty/error/status transitions, stat-card
entrances and value changes, and custom router fade/slide transitions honor the
operating system's reduced-motion preference; balance badges expose localized
semantics.
Focused widget tests cover RTL target sizing, locale labels, motion suppression,
and semantic color contrast; these checks do not claim full WCAG conformance.

PDF, print, share, and PNG exports reuse the same shaped PDF bytes. Urdu PDFs
use a Naskh-style font because the current renderer does not implement full
Nastaliq OpenType shaping. XLSX preserves Unicode and RTL worksheet direction,
but its font is chosen by the spreadsheet application and is not embedded.
Every Flutter action that can generate PDFs must include
`--dart-define=use_arabic=true`.

Financial PDFs share a workspace brand header with English content on the
left and the selected Arabic or Urdu content on the right, regardless of app
locale. Current workspace logo bytes are preferred; invoice/receipt snapshots
provide a logo fallback only when current bytes are unavailable and the
configured `visibleFields` includes the logo. Cash receipt PDFs use an A5
page and remain single-page. Pin row order with explicit PDF
`Directionality`; the pinned `pdf` 3.13.1 `Row` API does not accept a direction
parameter. Urdu PDFs use Naskh-style shaping; a standalone Nastaliq proof is
not production support until branding, selectable text, pagination, and
Web/Android report parity are verified.

Mixed-script PDF cells now use the first cased script letter for paragraph
direction instead of switching the entire value to RTL when any Arabic/Urdu
character appears. Numeric-only date cells use LTR direction. This correction
was released in v3.10.16+1127; it does not change font shaping, date formatting,
timestamp values, or financial calculations. The reported production date
discrepancy remains unverified without its source PDF.

The local mixed-script follow-up shapes English-first Arabic/Urdu values with
`pdfTextForDirection` before LTR layout. This preserves English-first reading
order while connecting medial Arabic and Urdu letters. The fix is locally
tested but unreleased; the original production PDF was unavailable for direct
visual comparison.

Workspace-logo processing is local and lossless: transparent pixels remain
transparent, and opaque colored backgrounds are retained without background
removal or substitution. The same saved logo bytes flow through workspace
settings backups and invoice snapshots; PDF, print, share, and PNG exports use
the shared PDF header path. XLSX currently does not embed a logo. Before
implementing a feature, review the active tasks and Git delta, load applicable
skills and path instructions, and read the affected runtime docs and source;
`AGENTS.md` §8 is the canonical pre-edit gate.

---

## Project Structure

```text
shoeserp/
├── app/                    # Flutter app (Android APK + Web)
│   ├── lib/
│   │   ├── core/           # constants, l10n, router, theme, utils, design tokens
│   │   ├── models/         # Firestore data models
│   │   ├── providers/      # Riverpod notifiers — ALL Firestore writes happen here
│   │   ├── screens/        # all UI screens
│   │   └── widgets/        # shared UI components
│   └── android/            # Android-specific config + signing
├── firestore.rules         # Security rules (deny-by-default, docSizeOk, withinWriteRate)
├── firestore.indexes.json  # Composite indexes for every where+orderBy query pair
└── firebase.json           # Firebase Hosting + Firestore config
```

---

## Setup

### Prerequisites

- Flutter SDK 3.47.8
- Android Studio / Android SDK (API 21+)
- Firebase project (`firebase login`)
- Java 17+

### Install dependencies

```bash
cd app
flutter pub get
```

### Firebase config

Place your `google-services.json` in `app/android/app/` (not committed — obtain from Firebase Console).

### Run (debug)

```bash
cd app
flutter run --dart-define=use_arabic=true
```

### Build release APK (split-per-ABI for phone delivery)

```bash
cd app
flutter build apk --release --split-per-abi --dart-define=USE_PLAY_INTEGRITY=true --dart-define=use_arabic=true
# Output: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
#         build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
#         build/app/outputs/flutter-apk/app-x86_64-release.apk
#         build/app/outputs/flutter-apk/app-release.apk
```

### Install the release APK to a connected phone

```bash
cd app
adb push build/app/outputs/flutter-apk/app-arm64-v8a-release.apk /sdcard/Download/
adb install --streaming -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

### Build web

```bash
cd app
flutter build web --release --dart-define=use_arabic=true
firebase deploy --only hosting
```

Canonical release order: sync or bump the version first, then build web,
deploy Hosting, build the split-per-ABI Android APK set, deploy Firestore
rules/indexes, review the local git delta, and only then commit/push.

---

## Backend Deployment

```bash
# Deploy Firestore security rules and composite indexes
firebase deploy --only firestore:rules,firestore:indexes
```

No Cloud Functions deployment needed. User creation uses a secondary `FirebaseApp` instance. No Firebase Storage — logos are stored as base64 in Firestore; product images use external HTTP URLs.

---

## SaaS Architecture

ShoesERP is designed as a single-project SaaS app. All tenant data lives in one Firebase project and is partitioned by `tenant_id` to support multiple workspaces on the Spark free tier.

- The `tenants` collection stores workspace metadata, plan flags, and owner user.
- Every tenant-scoped business document (`users`, `routes`, `customers`/`shops`, `products`, `seller_inventory`, `transactions`, `invoices`, etc.) must carry `tenant_id`.
- `tenant_admin` is scoped to a single tenant. `super_admin` is a platform operator and sees workspace metadata globally, but sees no workspace business records by default.
- Super-admin business support requires selecting one active workspace and entering a reason; the app records access start/end in append-only `platform_access_logs`. Firestore rules enforce the selected workspace regardless of client navigation.
- Platform super-admin accounts cannot be created or promoted from the client. Arbitrary-user Firebase Auth administration is not performed with client-held service-account keys; admins send password-reset email and account owners complete credential changes themselves.
- `TenantScope` in `app/lib/core/utils/tenant_scope.dart` is the canonical helper for query and write gating.
- `__global__` is reserved for global/system documents only.

### Tenant Gating Checklist

1. Use `TenantScope.applyToQuery(..., tenantId: ...)` for every business collection query.
2. Use `TenantScope.applyToData(..., tenantId: ...)` or explicit `tenant_id` on every tenant-scoped write.
3. Keep `tenant_admin` tenant-scoped. Keep `super_admin` platform-only unless an explicit, reasoned workspace support context is active.
4. Use `Collections.tenants` for workspace documents; avoid hardcoded `tenants` collection strings.
5. Verify Firestore rules enforce tenant ownership for each tenant-scoped collection.
6. Treat shops as `Collections.shops` (`customers` collection alias) with tenant partitioning, not as a separate customer model.
7. Ensure providers select current user tenant context from `authUserProvider` and do not leak cross-tenant streams.
8. Document new tenant-scoped collections and any tenant gating rule changes in both this README and `MASTER_BLUEPRINT.md`.
9. Prefer evolving the canonical governance files already in the repo instead of creating additional markdown artifacts for each follow-up pass.

### Verified Runtime Invariants

- Mutations require a concrete tenant; missing tenant identity is an error, never a `__global__` fallback. Unassigned users contact their workspace administrator instead of self-provisioning.
- Firebase Auth sign-in is not gated by device registration, pairing approval, or custom session slots. Firestore Rules continue to enforce active profiles, role permissions, concrete tenant scope, and audited super-admin workspace context.
- Transaction corrections use soft deletion only. Workspace admins can reverse standalone cash-in/cash-out transactions only with an exact same-batch shop-balance update; seller deletes and invoice-linked deletes are denied.
- Super-admin business access expires after 8 hours and remains enforced by Firestore rules. Legacy admins manage seller profiles; workspace-admin role changes require an active super-admin support context.
- Seller stock reductions must match exact same-batch invoice deductions. Warehouse stock movements and returns append tenant-scoped inventory audit records atomically.
- Stock-sale provider validation also matches invoice quantities by variant
  (`qty` dozens plus `extra_pairs`) to pair-denominated seller inventory
  deductions using workspace `pairs_per_carton`. Credit-note restores are
  cumulatively bounded by the original sale's deductions. This item-to-map
  reconciliation is client-side only; Rules link stock deltas to deduction
  metadata but cannot iterate invoice item lists.
- Financial corrections preserve prior values, actor, and a correction reason; invoice-linked transactions are corrected through invoice void/credit-note flows.
- Exports page to exhaustion. Tenant-admin restore is upsert-only; selected super-admin restore upserts before pruning obsolete documents. Plaintext legacy archives are rejected.
- Transient token-refresh failures do not sign users out. If Firebase initialization fails, the app shows a retry state rather than opening an unusable shell.
- App-side role capabilities are defined by `RoleCapabilities` and
  `PermissionPolicy`; routing, screen actions, and provider guards reuse that
  policy. Firestore Rules remain an independent authorization boundary and
  must be emulator-tested for both allowed and denied tenant operations.

### Data Maintenance and Workspace Lifecycle

- Supported backups are created and restored through the app's encrypted, workspace-scoped workflow. Tenant administrators and legacy workspace admins merge records without pruning; selected super-admins may replace only the active support workspace. Supervisors have no backup access. Sellers may save encrypted assigned-route archives to phone storage; restore imports only their own eligible unlinked cash ledger rows with atomic shop-balance reconciliation. Saved files can be explicitly uploaded to configured Google Drive when online; this is not background synchronization.
- Bulk database flush/reset controls and the legacy plaintext export, whole-collection restore, and direct-balance reset scripts fail closed. Multi-batch client cleanup can leave financial links, balances, inventory, or references inconsistent.
- Workspace lifecycle is archive/restore only. Firestore Rules deny hard deletion of a tenant root so business records cannot be orphaned by deleting the workspace document.
- To restore an archived workspace, select it from the workspace list with a support reason of at least 10 characters, then confirm Restore. The selected context is recorded in `platform_access_logs`; active tenant status remains required by business-data Rules.
- No production cleanup or backup was run as part of this source audit. A safe general-purpose transactional maintenance workflow remains a separate operational design.

---

## Roles & Permissions

| Action | Admin | Supervisor | Seller |
| --- | --- | --- | --- |
| Manage products / variants | ✅ | ✅ | ❌ |
| Operational route access | ✅ | ✅ (no seller assignment) | Assigned routes only |
| Manage users | Authorized account roles | ❌ | ❌ |
| View shops | All in workspace | All in workspace | Assigned routes only |
| Create / update shops | ✅ | ✅ (no route reassignment) | Assigned routes only |
| Access invoices and reports | ✅ | ✅ | Assigned-route workflows |
| Create sale invoices / cash receipts | ✅ | ✅ | Assigned-route shops only |
| Adjust inventory | ✅ | ✅ | ❌ |
| Notifications | Admin-equivalent; supervisor may use the tenant feed | Tenant feed only | ❌ |
| Settings and workspace backup | Admin-equivalent only | ❌ | ❌ |
| Financial correction / invoice void | Admin-equivalent only | ❌ | ❌ |
| Profile (name/theme/language/password) | ✅ | ✅ | ✅ |

> `manager` role is treated as admin-equivalent for legacy data compatibility.
> Tenant admins may assign supervisor and seller roles to eligible members;
> supervisor is not an account-administration or financial-approval role.

`RoleCapabilities` and `PermissionPolicy` are the canonical app-side
capability matrix. Legacy `admin`/`manager` may administer seller accounts
only; tenant admins manage eligible same-workspace seller/supervisor accounts;
supervisors receive operational access and notification-feed access without
financial-correction, invoice-void, backup, settings, or user-administration
rights. Firestore Rules must independently enforce each operation and tenant
boundary; client visibility is never the security control.

---

## Firestore Collections

| Constant (`Collections.*`) | Firestore name | Purpose |
| --- | --- | --- |
| `Collections.users` | `users` | Auth user profiles, roles, route assignments |
| `Collections.products` | `products` | Product catalogue |
| `Collections.productVariants` | `product_variants` | SKU variants with `quantity_available` (stored in pairs) |
| `Collections.routes` | `routes` | Delivery routes with assigned seller |
| `Collections.shops` | `customers` | Shops/customers with running `balance` field |
| `Collections.transactions` | `transactions` | Cash ledger entries per shop |
| `Collections.invoices` | `invoices` | Sale invoices and credit notes |
| `Collections.sellerInventory` | `seller_inventory` | Seller-allocated stock per variant |
| `Collections.inventoryTransactions` | `inventory_transactions` | Stock movement audit trail |
| `Collections.settings` | `settings` | Global business settings |

> **Note:** `Collections.shops` maps to the Firestore collection named `customers` — legacy name preserved for backward compatibility.

---

## Financial Integrity Rules

1. `shop.balance` is the **sole source of truth** for all monetary displays. It is mutated **only** by `InvoiceNotifier` or `TransactionNotifier` via atomic Firestore batch writes.
2. **Stock sale:** `CreateSaleInvoiceScreen` → `InvoiceNotifier.createSaleInvoice()` — invoice, cash ledger entries, exact inventory deductions, and shop balance update.
3. **Non-stock sale:** same invoice notifier with `fulfillment_mode: non_stock` — catalog items are recorded without inventory deductions and only when the workspace setting permits it.
4. **Cash receipt:** `InvoiceNotifier.createCashReceipt()` — tenant-scoped receipt number, receipt invoice, `cash_in` ledger row, and balance reduction in one Firestore transaction.
5. **Ledger-only collection:** `ShopDetailScreen` → `TransactionNotifier.create(type: 'cash_in')` remains available when no receipt document is needed.
6. **Void/return:** `InvoiceNotifier.voidInvoice()` — admin only; stock returns only for stock-backed invoices, with one reversal transaction.
7. Never create a sale invoice for cash-only collection. Never create a standalone transaction for a new goods sale.
8. Client transaction reads of missing invoice/transaction IDs require an active profile and concrete active tenant; selected super-admins must retain valid support context. Missing seller-inventory reads are admin-equivalent only. Workspace-creation settings reads are limited to missing documents whose tenant has not yet been created. Existing-document reads remain governed by normal tenant and route rules.
9. SAR/PKR amounts accept no more than two fractional digits. Ambiguous three-decimal forms are rejected; comma-grouped thousands remain supported. Credit-note item quantities are cumulative by variant and cannot exceed the quantities on the original sale. Legacy linked-note history is reconstructed with a 50-document ceiling and fails closed when incomplete or inconsistent.

---

## Code Quality

```bash
cd app

# Must return "No issues found!"
flutter analyze lib --no-pub

# All tests must pass
flutter test -r expanded --dart-define=use_arabic=true

# No raw Firestore collection strings
grep -rn "\.collection('" app/lib/ | grep -v "Collections\."

# No StateProvider (banned — Riverpod 3 removed it)
grep -rn "StateProvider\b" app/lib/ --include="*.dart"
```

---

## Production Signoff Checklist

1. Atomic version bump or explicit version-sync verification: `app/pubspec.yaml` and `app/lib/core/constants/app_brand.dart` must match before release artifacts are built.
2. `flutter analyze lib --no-pub` → quote exact final line.
3. `dart analyze test/` → quote `No issues found!`.
4. `flutter test -r expanded --dart-define=use_arabic=true` → quote pass count.
5. `flutter build web --release --dart-define=use_arabic=true` → confirm `EXIT: $LASTEXITCODE` = 0.
6. `firebase deploy --only hosting` after the web build.
7. `flutter build apk --release --split-per-abi --dart-define=USE_PLAY_INTEGRITY=true --dart-define=use_arabic=true` → quote the generated ABI APK path(s) and size(s).
8. `firebase deploy --only firestore:rules,firestore:indexes` on every signoff, before commit/push is considered complete.
9. `git log --oneline -5`, `git status --short`, and `git diff --stat HEAD` → confirm only expected local changes remain.
10. `git add -A`, `git commit -m "type: summary — vX.Y.Z+N"`, and `git push` → quote commit hash and push output.
11. `adb push build/app/outputs/flutter-apk/app-arm64-v8a-release.apk /sdcard/Download/` followed by `adb install --streaming -r /sdcard/Download/app-arm64-v8a-release.apk` to install the phone-delivery APK to a connected device when Android delivery is part of the request.

---

## Troubleshooting

**permission-denied:**

- Verify `users/{uid}.active == true`
- Verify `users/{uid}.role` is canonical (`admin` / `seller`; `manager` is legacy admin-equivalent)
- Verify `firestore.rules` is deployed

**resource-exhausted:**

- Dashboard fallback cache is active (`_lastGoodDashboardStatsProvider`)
- Reduce aggressive refresh loops

**Empty list views:**

- Check `where + orderBy` query shape in provider
- Add composite index to `firestore.indexes.json` and deploy

---

## Canonical Docs

- [AGENTS.md](AGENTS.md) — runtime contract and permission matrix
- [CLAUDE.md](CLAUDE.md) — coding rules, financial pathways, breakage chains
- [SYSTEM_DEEP_DIVE_2026-03-27.md](SYSTEM_DEEP_DIVE_2026-03-27.md) — audit findings
- [app/README.md](app/README.md) — Flutter app architecture detail
