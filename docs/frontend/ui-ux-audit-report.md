# Frontend UI/UX Modernization Report

## Summary

Phase A modernized the repository's frontend skills and implementation
instructions. Phase B established a tested shared-component accessibility
foundation, created a route/state register and design-system architecture
reference, and fixed edit-state data-loss paths across route, shop, product,
and variant forms. The remaining named source-audit findings for report export
feedback, user route choices, workspace backup/flush states, tenant role
presentation, shop-form route lookup, and an intermediate-width login crash
were reviewed and dispositioned. Broader dialog/sheet coverage and rendered
role/theme acceptance remain open; no application-wide visual redesign or
authorization change is claimed.

The existing Arctic blue/navy design system was retained. The changes use
existing `AppTokens`, `AppAnimations`, localization, and shared widgets rather
than introducing a second theme, navigation package, or component dependency.

The 2026-10-24 operational UX follow-up addresses stale settings forms,
currency-mixed shop summaries, missing invoice Pending filtering, shop-detail
space use, and receipt/statement presentation. It keeps Firestore snapshot
listeners as the real-time mechanism and adds explicit pull refresh to the
data-backed shop, invoice, ledger, and settings surfaces. Invoice voiding also
captures tenant-scoped linked settlement rows—including legacy rows absent
from invoice references—so customer statements omit all voided invoice
activity without losing valid credit-balance payments.

## Implementation

- Added `AppTokens.minTouchTarget` (48 logical pixels) and applied it to the
  horizontal shared filter-chip bar.
- Added `AppMotion` as the shared access point for
  `MediaQuery.disableAnimations` and reduced durations to zero when motion is
  disabled.
- Updated empty and error illustrations, stat-card value transitions, and
  status-chip transitions to respect reduced motion. Stat-card entrance motion
  is also suppressed when requested.
- All `AppAnimations` presets now check the inherited motion preference at
  their shared wrapper, including screen/list entries, shimmer, shake, slide,
  fade, bounce, stagger, pop, and tab effects. `PressableWidget` keeps tap and
  semantic actions when press-scale feedback is disabled.
- The custom GoRouter fade/scale and form slide transition builders now return
  their page child directly when `MediaQuery.disableAnimations` is enabled.
  Normal transitions remain unchanged when the preference is disabled.
- Changed `AppBalanceBadge` to expose the localized balance label and amount as
  one semantic value for English, Arabic, and Urdu.
- Added regression tests for RTL filter target size, all three localized
  semantic labels, success/error text contrast, and reduced-motion behavior.
- Route, shop, product, and variant edit forms now wait for the active profile
  and their source record before presenting editable fields. Mapped retry and
  not-found states replace editable defaults on failure or missing data.
  Existing route seller assignments, route/currency values, and form values
  are loaded before save is enabled. Submit guards reinforce the UI gate. The
  existing provider role/tenant checks and transactional writes remain
  unchanged.
- Inventory add/transfer dialogs now distinguish product, variant, and seller
  selection loading, empty, and mapped error/retry states. The inventory
  screen waits for workspace settings before rendering quantity actions, so a
  missing settings emission cannot silently use the 12-pairs-per-carton
  fallback; dialogs receive the loaded carton size without changing provider
  writes or stock calculations.
- Invoice-list summary amounts are grouped by invoice currency rather than
  adding SAR and PKR values together. Currency-filtered shops do not render
  until route scope is available; initial route errors expose retry feedback.
- Invoice creation now distinguishes profile loading, profile failure with a
  mapped retry action, and a missing profile instead of rendering an endless
  spinner for every null/error state.
- Profile unsaved-change protection follows the sanitized name's difference
  from the saved profile value, so restoring the original name clears the dirty
  state.
- Mark-all-read disables during its write, shows progress, and reports mapped
  failures. Dashboard, history, and notification rows hide the shop-navigation
  chevron when their shop link is absent.
- Stat-card entrance motion is omitted when reduced motion is requested.
- Report export cards disable duplicate taps, show generation progress, and
  map provider failures. Account-statement and seller-report cards retain their
  own generating indicators and mapped error feedback. Account statements
  resolve the selected shop's route before formatting spreadsheet and PDF
  amounts. Seller-report rows retain transaction route currency, current
  outstanding balances use each shop's current route currency, and PDF grand
  totals are grouped by currency. Admin export route metadata includes inactive
  routes so historical transactions retain their route currency context.
- User-management seller route selectors show loading, empty, and retryable
  error states. Create, edit, and reactivation validate selected routes against
  loaded route data and refresh saved route names from that source. The
  edit-dialog async callback now checks both owning-state and dialog-context
  lifetime before using either after awaiting the active profile.
- Backup and flush distinguish auth/workspace loading and lookup failures,
  offer retry where a lookup can recover, and keep workspace operations
  disabled until the selected tenant record is available. Flush also exposes
  per-user loading, empty, and retryable error states.
- Tenant-management role presentation was source-reviewed and regression
  tested: tenant admins see workspace metadata without platform actions.
  Existing router, provider, and Firestore authorization contracts are
  unchanged.
- Shop creation now exposes mapped route-query failure and retry feedback;
  route-dependent actions remain gated until the required route data is ready.
- The narrow login layout now caps its content width to the available viewport
  and 420-logical-pixel maximum. At 668 logical pixels the old minimum width
  was 620 while the maximum remained 420, causing a Flutter layout exception.
  The fix changes sizing only; sign-in, password reset, role, and provider
  behavior are unchanged.
- Added `design-system-architecture.md` to document the existing brand,
  token, theme, typography, motion, shared-widget, and adaptive-navigation
  ownership without introducing a parallel design system.

No route, provider, data, tenant, financial, inventory, or Firestore Rules
authorization contract changed. The user-visible changes were built at
synchronized version `3.9.83+709`; the web build was deployed and Android
release APKs were produced.

## Screen audit status

See `screen-register.md` for the route map, guard context, purpose, data scope,
shared states, reported findings, and verification status. The register
separates source-audit observations from reproduced defects and visual checks.

The register enumerates all 32 registered route patterns and principal shell
and contextual entry points. The previously named screen-state findings now
have source dispositions and targeted regression coverage, including report
export progress/errors, user route-option retry, backup/flush workspace and
user-query retry, tenant-admin role presentation, and shop-form route-query
retry. The follow-up UI-07 review reproduced and fixed account-statement
currency mismatch and seller reports that used the seller's first route
currency for every shop. Currency-grouped PDF totals and route-specific
spreadsheet/PDF rows now keep unlike amounts separate. This remains a route
and workflow-family inventory, not an exhaustive interaction inventory: many
dialogs and sheets have not been exercised.

The additional motion review inspected every shared `AppAnimations` preset
and confirmed the disabled-motion regression before implementation. All
presets now return their original content without applying optional effects
when `MediaQuery.disableAnimations` is enabled. Focused tests cover disabled
and enabled paths, child visibility, press activation, and semantic tap
availability.

## Validation

The focused widget sets passed after first confirming the expected failures:

- Reduced-motion behavior was initially absent from empty/error/status
  components, stat-card transitions and entrances, and the shared animation
  presets.
- The filter bar had a fixed 44-logical-pixel height instead of the shared
  48-logical-pixel target token.
- The balance badge's screen-reader label was hardcoded in English.

After implementation, the shared-component focused command
`flutter test test/widget/empty_state_test.dart test/widget/error_state_test.dart test/widget/stat_card_test.dart test/widget/status_chip_test.dart test/widget/app_filter_chip_bar_test.dart test/widget/app_balance_badge_test.dart --dart-define=use_arabic=true -r expanded`
reported `00:05 +15: All tests passed!`.

The combined CRUD edit-form command
`flutter test test/widget/edit_form_loading_test.dart test/widget/route_form_seller_load_test.dart test/widget/product_form_screen_test.dart test/widget/auth_submit_feedback_test.dart --dart-define=use_arabic=true -r expanded`
reported `00:08 +17: All tests passed!`. Coverage includes profile and record
loading, route/product/shop/variant load failures and retry, missing records,
route currency and seller assignment prefill, and preserved seller-list
feedback.

The new screen-state regressions were first run against the pre-fix behavior
and failed for the expected conditions: missing mixed-currency summary labels,
missing mark-all progress, sticky profile dirty state, and an unscoped
currency-filtered shop row. After implementation, the focused command
`flutter test test/widget/create_invoice_auth_state_test.dart test/widget/invoice_list_summary_test.dart test/widget/notification_center_feedback_test.dart test/widget/profile_dirty_state_test.dart test/widget/shops_currency_filter_test.dart test/widget/stat_card_test.dart --dart-define=use_arabic=true -r expanded`
reported `00:08 +9: All tests passed!`.

Focused remaining-state regressions passed individually with
`--concurrency=1 --dart-define=use_arabic=true`: report export busy/error
(`00:01 +1: All tests passed!`), selected-workspace backup retry/action gating
(`00:02 +1: All tests passed!`), flush workspace/user-query retry
(`00:01 +1: All tests passed!`), tenant-admin role branch
(`00:00 +1: All tests passed!`), seller route-option retry
(`00:03 +1: All tests passed!`), and shop-form route-query retry
(`00:00 +1: All tests passed!`). `flutter analyze lib --no-pub` reported
`No issues found! (ran in 21.7s)` and `dart analyze test/` reported
`No issues found!`.

The currency/PDF/export regression command
`flutter test test/unit/core/seller_report_currency_test.dart test/unit/core/pdf_export_test.dart test/widget/reports_export_feedback_test.dart --concurrency=1 --dart-define=use_arabic=true -r expanded`
reported `00:07 +12: All tests passed!`. Its coverage checks SAR and PKR
aggregation separately and builds a seller PDF containing both currencies.
Final `flutter analyze lib --no-pub` reported
`No issues found! (ran in 10.7s)`; `dart analyze test/` reported
`No issues found!`.

The login responsive regression first failed before the fix with
`BoxConstraints(620.0<=w<=420.0, 0.0<=h<=Infinity; NOT NORMALIZED)` at 668
logical pixels. After the fix, the focused login feedback file reported
`00:03 +3: All tests passed!`; its responsive case covers 320, 360, 420, 668,
719, and 720 logical pixels in EN/AR/UR with locale directionality. The current
full Flutter suite then reported `01:09 +585: All tests passed!`.
`flutter analyze lib --no-pub` reported
`No issues found! (ran in 65.8s)`; `dart analyze test/` reported
`No issues found!`.

The route-transition regression first reproduced an active `ScaleTransition`
around the backup page while reduced motion was enabled. After adding the
shared preference check to both route builders, the focused router suite
reported `00:05 +6: All tests passed!`. The complete current Flutter suite
reported `01:01 +589: All tests passed!`; `flutter analyze lib --no-pub`
reported `No issues found! (ran in 102.3s)` and `dart analyze test/` reported
`No issues found!`.

An earlier serial run of the full backup-screen test file exhausted the Dart
VM after two cases in an environment with 1.71 GB free memory; its new
workspace retry regression passed in isolation. This limitation predates the
current successful full-suite run. Theme checks cover only the actual
success/error foreground/background pairs used by the badge; they do not
certify the full app or all component/theme combinations.

## Release verification (2026-10-24)

- Full Flutter suite: `01:32 +589: All tests passed!`.
- `flutter analyze lib --no-pub`: `No issues found! (ran in 10.6s)`;
  `dart analyze test/`: `No issues found!`.
- Firestore Rules Emulator: `129 passing (23s)`. Rules/indexes were deployed
  successfully. Existing remote indexes and field overrides absent from the
  local index file were preserved.
- Web build: `EXIT: 0`; Firebase Hosting reported `Deploy complete!` for
  `shoeserp-clean-20260327.web.app`.
- Split APKs: ARMv7 30.4 MB, ARM64 31.9 MB, x86_64 33.4 MB.
- Google Drive OAuth IDs were not available in the local build environment.
  Encrypted phone backup and restricted route restore are available; Drive
  upload remains unavailable in these artifacts until OAuth is configured
  and the web/APK artifacts are rebuilt.

## Visual and platform limitations

- The signed-out `/login` page was rendered in the local browser at the
  previously failing intermediate width after hot reload; the page displayed
  without the prior constraints exception and the Dart runtime-error query was
  empty. This was a public login-screen smoke check, not a sign-in test or
  route-by-route authenticated visual review.
- No authenticated role accounts were available for visual inspection of
  business screens.
- No Android device was connected for touch, screen-reader, font, or large-text
  checks.
- No screenshots were captured for light/dark/high-contrast × EN/AR/UR.
- No PDF/image rendering review was performed as part of this frontend phase;
  RTL export behavior is documented separately in the export governance.
- Performance was not profiled; no performance improvement is claimed.
- Android debug APK validation was attempted, but Gradle failed at
  `:app:mergeDebugJavaResource` with
  `java.io.IOException: Insufficient system resources exist to complete the
  requested service`; a later release build nevertheless succeeded.
- No Android device installation, touch, screen-reader, font, or large-text
  acceptance was performed.

The remaining dialog/sheet interaction inventory and visual acceptance are
listed in the register rather than being inferred from source or widget tests.

## Operations not performed

No production-data operation, device install, authenticated business-screen
visual review, or profile-mode performance review was performed.

## Unreleased operational refresh and void-integrity verification

The invoice-void regression covers retained customer credit, cash-refund
exclusion, sale-debit rejection, and cross-invoice link rejection. The focused
suite reported `00:00 +22: All tests passed!`; the full Flutter suite reported
`01:08 +599: All tests passed!`. `flutter analyze lib --no-pub` reported
`No issues found! (ran in 7.1s)` and `dart analyze test/` reported
`No issues found!`.

Rules and indexes were unchanged. No rules deployment, release build, Hosting
deployment, APK install, commit, or push was performed. Authenticated web/APK
cross-device data freshness, device rendering, and role-based visual
acceptance remain unverified.

## v3.9.84+710 backup and release verification (2026-10-24)

The backup permission regression was traced to the settings list query: Rules
authorize a workspace's known settings document ID, not a `tenant_id` query.
The provider now reads that path directly. Role-specific archive validation
uses the serialized collection names, and seller archives reject inventory
records attributed to another seller. No Rules or index source changes were
needed; tenant and selected-workspace boundaries remain unchanged.

- Backup role tests: `00:07 +16: All tests passed!`.
- Full Flutter suite: `01:15 +603: All tests passed!`.
- `flutter analyze lib --no-pub`: `No issues found! (ran in 83.9s)`;
  `dart analyze test/`: `No issues found!`.
- Firestore Rules Emulator: `132 passing (48s)`.
- Firestore Rules/index deployment to `shoeserp-clean-20260327`:
  `Deploy complete!`; existing remote indexes and field overrides absent
  locally were preserved.
- Synchronized version: `3.9.84+710`. Split APKs built: ARMv7 30.4 MB,
  ARM64 32.0 MB, x86_64 33.4 MB. The ARM64 APK was copied to the connected
  phone and installed with `Success`; device reports versionName `3.9.84`,
  versionCode `3101110`.
- No web build or Hosting deployment was performed. Git publication is
  pending because a push to `main` automatically triggers Hosting; no
  authenticated cross-device business-data verification was performed.
