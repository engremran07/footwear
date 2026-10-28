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

## 2026-10-28 Full-Frontend Modernization Baseline

The complete 832-line modernization prompt and its companion skill snapshot
were reviewed. This is a staged modernization of the existing product, not a
greenfield rewrite. The requested scope covers repository and feature
inventory, focused external research, distinct desktop-web and Android
experiences, design-system consistency, Riverpod ownership, skills/tooling,
dependency and Gradle compatibility, footwear workflows, performance,
accessibility, Firebase consistency, regression testing, and evidence-based
reporting.

### Verified baseline

- Repository baseline: `main` at
  `2f2c09b2b522249142e428093b2ee86e24714cd7`. The only observed worktree
  entry is an unexplained, zero-byte untracked file under
  `tests/firestore-rules/`; it was preserved and not included in the work.
- Local environment: Flutter `3.41.6`, Dart `3.11.4`; app constraint is
  Dart `>=3.11.0 <4.0.0`, version `3.10.12+1123`.
- Baseline analysis: `flutter analyze lib --no-pub` reported
  `No issues found! (ran in 94.0s)`; `dart analyze test/` reported
  `No issues found!`.
- Baseline tests: `flutter test -r expanded
  --dart-define=use_arabic=true` reported
  `01:24 +685: All tests passed!`.
- Baseline web build: `flutter build web --release
  --dart-define=use_arabic=true` completed with `EXIT: 0`. The WebAssembly
  dry-run succeeded; tree-shaking and dry-run notices were informational.
- Android configuration inspected: Gradle `8.14`, AGP `8.11.1`, Kotlin
  `2.2.20`, Java `17`, compile/target SDK `36`, minimum SDK `29`. The
  dependency/Gradle review found no evidenced compatibility failure that
  warrants a blind upgrade. Existing release artifact evidence is recorded
  in SESSION-040; the Android build was not rerun for this audit.

### Initial architecture and risk observations

- The router has 32 registered route patterns. The app uses a single
  `MaterialApp.router`; the authenticated shell changes composition by
  available width, using compact navigation below 720 logical pixels, a rail
  from 720, and an extended rail from 1024. The inspected shell does not select
  a separate composition using `kIsWeb`. This is a confirmed architecture
  fact; screen-by-screen review is required before classifying it as a product
  defect.
- The project already owns centralized brand, theme, token, font, motion,
  localization, and shared-widget implementations. This baseline does not
  justify introducing a parallel design system or UI package.
- Current test evidence includes selected narrow-phone and wide-shell cases,
  but the bounded frontend review found no direct shell tests at the 720/1024
  breakpoints or a platform-specific web composition test. It did not find a
  demonstrated responsive defect.
- A bounded Riverpod review flagged transaction-write concurrency and
  idempotency, settings mutation-state visibility, notification mutation
  scope, and listener-cancellation test coverage for targeted verification.
  These are audit candidates, not confirmed authorization defects; the Rules
  contract and exact user-facing behavior must be checked before remediation.
- Research retrieved [Flutter accessibility guidance](https://docs.flutter.dev/ui/accessibility),
  which recommends functional controls, screen-reader testing, contrast
  checks, touch targets, actionable errors, and large text-scale checks.
  Apply only relevant guidance and verify APIs with the pinned Flutter 3.41.6
  SDK; the retrieved documentation currently describes a newer Flutter line.
- [WCAG 2.2](https://www.w3.org/TR/WCAG22/) provides device-independent,
  testable web accessibility criteria. It is an evaluation reference, not a
  claim of conformance.
- [Shopify Polaris references](https://shopify.dev/docs/api/polaris) describe
  a unified UI framework spanning Shopify app surfaces. This is a consistency
  pattern only: its web-component implementation is not a Flutter dependency,
  and no code or assets were adopted.
- [Odoo Inventory documentation](https://www.odoo.com/documentation/19.0/applications/inventory_and_mrp/inventory.html)
  and its [stock report](https://www.odoo.com/documentation/19.0/applications/inventory_and_mrp/inventory/warehouses_storage/reporting/stock.html)
  show role-gated stock reporting with grouping, searchable filters, on-hand
  and movement context. These patterns may inform desktop table research but
  do not justify adding purchasing or valuation features without validating
  the ShoesERP business model.
- Flutter's adaptive-responsive page could not be retrieved in this run
  because of a transport-level failure. No third-party code, assets, SDK, or
  package was adopted; license compatibility was therefore not used to justify
  an implementation. This remains preliminary research, not a completed
  commercial/open-source comparison.

### Phased execution and status

| Phase | Scope | Status |
|---|---|---|
| A | Repository, toolchain, test, and build baseline | Baseline completed; full screen inventory remains part of Phase D |
| B | Focused design, accessibility, and ERP research | Preliminary sources collected; research comparison remains open |
| C | Distinct desktop-web and Android experiences | Width-responsive shell confirmed; detailed screen assessment and implementation remain open |
| D | Evidence-based feature-gap comparison and ranked backlog | In progress; route inventory started, feature-domain verification remains open |
| E | Existing design-system and component unification | Existing owners confirmed; cross-screen consistency audit remains open |
| F | Riverpod state ownership and duplication | Bounded candidate findings recorded; direct reproduction and cross-feature audit remain open |
| G | Skills, agents, and MCP review | Existing project skills are present; targeted skill/tool decisions remain open |
| H | Dependency and Gradle modernization | Configuration reviewed; no upgrade selected without a demonstrated need |
| I | Footwear workflow enrichment | Not yet audited end-to-end |
| J | Performance, accessibility, and interaction quality | Prior dashboard lazy-list work is recorded separately; whole-app profiling and accessibility review remain open |
| K | Firebase and cross-platform consistency | Not yet verified end-to-end across representative roles and tenants |
| L | Regression, integration, and platform validation | Current baseline is green; modernization-specific scenario coverage remains open |
| M | Bounded implementation and change control | In progress; preserve existing behavior and use evidence-first tests |
| N | Audit, research, migration, test, and backlog deliverables | This baseline addendum is partial; remaining evidence must be added as phases execute |

### Continuity and boundaries

The session todo list retains all earlier unresolved multi-tenant, permission,
notification, invoice, user-management, super-admin, browser-diagnostic,
workspace-visibility, reset-safety, and seller-history tasks. Thirteen
modernization phase todos were added rather than replacing those items. Phase
A is complete; feature inventory is active. No runtime source, Rules, indexes,
release version, production data, deployment, commit, or push was changed by
this baseline audit. The unexplained untracked file remains untouched.

### 2026-10-28 Provider and notification Rules regressions

#### Notification feed disappears during profile refresh

The commit trace identified a loading-state regression: when the profile
provider emitted `AsyncLoading` with a retained value, the notification screen
showed full-screen loading and the tenant-scope provider discarded the cached
profile. The correction retains the feed only when the retained profile ID
matches the settled Firebase Auth UID. Auth loading/errors and UID mismatch
still clear tenant scope, preserving account-switch isolation.

The added widget regression failed before the fix because the notification row
disappeared during a same-user profile refresh. Focused notification-center
widget tests: `00:03 +9: All tests passed!`; visibility/provider tests:
`00:00 +13: All tests passed!`; full Flutter suite:
`01:36 +689: All tests passed!`; `flutter analyze lib --no-pub`:
`No issues found! (ran in 116.5s)`; `dart analyze test/`:
`No issues found!`. This local result does not verify a production session or
close the broader modernization audit.

The follow-up traced notification tile taps and the mark-all action through
`NotificationCenterScreen`, `NotificationNotifier`, and the notification
Rules. The provider previously supplied client-clock timestamps, while Rules
did not enforce a one-way transition. The client now uses server-timestamp
sentinels; Rules require both fields to change, `read` to transition from
false to true, and `read_at` to resolve to `request.time`. Concrete active
tenant and authorized operational-role gates remain in place. Rules emulator
tests deny resets, partial changes, client timestamps, unassigned/global
scope, inactive users/tenants, and cross-tenant access, while allowing
mark-one and mark-all for eligible readers.

The transaction audit traced the shop cash-entry dialog through
`TransactionNotifier.create()`. The concurrency guard previously allowed a
second call to complete without writing or signaling rejection. It now throws
an error that the screen maps to feedback. Optional keyed creates use a stable
tenant-scoped document ID and a Firestore transaction to atomically create the
ledger row and update `shop.balance`. The unkeyed batch path remains intact.
The regression verifies the duplicate call is not silently accepted and the
document ID is tenant-specific. It does not yet verify a concurrent persisted
race against an emulator.

Validation: focused notification and transaction tests
`00:00 +21: All tests passed!`; full Flutter suite
`01:34 +688: All tests passed!`; `flutter analyze lib --no-pub`:
`No issues found! (ran in 15.4s)`; `dart analyze test/`:
`No issues found!`; Rules Emulator: `185 passing (46s)`. The emulator log
contained non-failing expression-limit diagnostics in other Rules paths.
Rules and provider changes remain local and undeployed. Android/web release,
device install, deployment, Git publication, authenticated visual acceptance,
and the full modernization phases remain open.

## 2026-10-28 Mobile ERP Design Benchmark and Feature-Gap Candidates

The comparison below uses published product features and repository evidence
available on 2026-10-28. It is a pattern benchmark, not a universal ranking:
the projects serve different business sizes and device contexts. ShoesERP
remains the source of truth for brand, role policy, tenant scope, and footwear
distribution workflows. Do not copy proprietary layouts or assets.

| Reference | Category and documented patterns | ShoesERP comparison | Reuse decision |
|---|---|---|---|
| [Flutter Material 3](https://docs.flutter.dev/ui/design/material) | Open design-system foundation for controls, forms, surfaces, themes, and accessibility | ShoesERP already uses Flutter/Material with owned theme and token files; Material does not supply distributor workflows or tenant authorization | Keep as the foundation; improve the existing system instead of replacing it |
| [Flutter Responsive Admin Panel](https://github.com/abuanwar072/Flutter-Responsive-Admin-Panel-or-Dashboard) | Open Flutter dashboard starter; its README describes charts, tables, information cards, and web/tablet/phone layouts; repository license is MIT | ShoesERP has width-responsive shell navigation and operational screens, but no verified evidence yet that every business list adapts to a dense desktop/table layout | Borrow responsive information hierarchy only; do not import the starter wholesale or its unrelated dependencies |
| [GetWidget](https://pub.dev/packages/getwidget) | Open-source Flutter component catalog for common forms, lists, cards, and controls | ShoesERP already has shared widgets and semantic tokens; adding another kit risks duplicate visual systems and bundle weight | Use only as a pattern reference; add no package without a concrete missing component and measured benefit |
| [FlexColorScheme](https://pub.dev/packages/flex_color_scheme) | Open-source Flutter theming toolkit for coordinated Material themes | ShoesERP already owns `AppTheme`, `AppFonts`, and `AppTokens`; the current latest line may require a newer Flutter SDK | No adoption selected; compare behavior after SDK upgrade, not as a reason to create a parallel theme |
| [Odoo Inventory](https://www.odoo.com/app/inventory) | Commercial ERP reference: replenishment, GS1 workflows, offline operation, multi-warehouse lookup, counting, and batch/cluster/wave picking | The route map has no dedicated purchase, pick/pack, replenishment, or warehouse-location routes; there is no evidence that these concepts belong in ShoesERP's current seller-distribution model | Treat as discovery candidates, not committed scope; require business-owner validation and tenant/data model before implementation |
| [Zoho Inventory](https://www.zoho.com/sa/inventory/features/) | Commercial inventory reference: multi-warehouse transfers, picklists, barcode/serial/batch tracking, invoicing, returns, and analytics | ShoesERP has inventory transfers, invoices, returns, and reports; barcode, serial/batch, and picklist workflows were not found in the inspected route/source search | Prioritize only footwear-specific SKU scanning and transfer/pick workflows after feasibility and permissions review; pricing/availability are regional |
| [Sortly](https://www.sortly.com/features/) | Commercial mobile inventory reference: barcode/QR capture, custom fields/tags, picklists, low-stock alerts, offline edits, and automatic sync | ShoesERP has tenant-scoped products and stock; no scanner screen or explicit offline write queue/conflict workflow was found in the inspected routes and source search | Study capture ergonomics and low-stock presentation; offline writes need a separately designed conflict and ledger policy |

### Candidate gap register

The following are ranked by potential value and safety, not all confirmed
defects. "Not found" means absent from the inspected route map/source search;
it does not prove that no hidden or external workflow exists.

| Priority | Candidate | Current evidence | Recommended next step |
|---|---|---|---|
| P0 | Clear async and permission feedback across role-scoped screens | Existing audit has concrete notification refresh, Users loading, backup, invoice-mode, and workspace-context regressions; tests cover several, while authenticated cross-workspace visual acceptance remains open | Close known regressions with role/tenant fixtures and retain visible retry/error states before visual redesign |
| P1 | Task-oriented responsive shell and dashboards | Shell uses compact navigation below 720 logical pixels, a rail from 720, and an extended rail from 1024; different web-specific composition and all-screen responsive behavior are not verified | Audit the same route at phone, tablet, and desktop constraints, then introduce role-specific quick actions only where task traces show friction |
| P1 | Dense desktop list/table mode with stable filters and bulk-safe selection | Product lists, shops, invoices, and users exist; the screen register does not establish a common desktop data-grid interaction contract | Prototype responsive list-to-table presentation, preserve keyboard/focus/RTL behavior, and avoid bulk destructive actions |
| P1 | Cross-screen search and recent operational context | No global command/search route or command-palette source match was found in the inspected app library | Validate user tasks and Firestore query cost, then scope search to authorized tenant and role before implementation |
| P2 | Footwear SKU/barcode capture with manual fallback | No barcode/QR route or scanner flow was found; product and variant workflows exist | Validate labels/SKU uniqueness, camera permission necessity, device availability, and a manual-input fallback; no camera permission is added in this audit |
| P2 | Low-stock/replenishment work queue | Inventory exists; no dedicated purchase/replenishment route was found | Decide whether ShoesERP owns purchasing/replenishment or only seller allocation; do not add purchase orders by analogy alone |
| P3 | Offline mutation queue and conflict resolution | Network status is exposed, but a durable queued-write/conflict-resolution contract was not found in the inspected route/source search | Keep financial and stock writes online-only unless an idempotent, tenant-bound reconciliation design is approved and emulator-tested |
| P3 | Richer warehouse location, picklist, serial/batch tracking | Not found in the inspected route map; the current model uses variant-level stock and seller allocations | Validate actual warehouse operations and data requirements before introducing schema or provider changes |

### Design direction

Use the existing design tokens and components to create a calm, high-density
operational interface: role-aware primary tasks, compact status and quantity
scanning, expandable detail, clear save/refresh progress, and responsive
phone-to-desktop list composition. Preserve current brand and business
semantics; do not add decorative analytics, generic KPI cards, camera
permissions, offline financial writes, or paid UI dependencies without
measured evidence. The comparison does not visually certify current screens:
authenticated admin/supervisor/seller screenshots across EN/AR/UR, light/dark
themes, text scale, and viewport sizes remain pending.

Research references: [Flutter accessibility](https://docs.flutter.dev/ui/accessibility),
[GetWidget](https://pub.dev/packages/getwidget),
[FlexColorScheme](https://pub.dev/packages/flex_color_scheme),
[Odoo Inventory](https://www.odoo.com/app/inventory),
[Zoho Inventory](https://www.zoho.com/sa/inventory/features/),
and [Sortly](https://www.sortly.com/features/). Commercial feature pages are
vendor claims; pricing, region, licensing, availability, and offline behavior
must be rechecked before a product or architecture decision.
