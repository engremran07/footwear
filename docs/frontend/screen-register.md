# Frontend Screen and State Register

## Scope and evidence

This register maps all 32 route patterns registered in
`app/lib/core/router/app_router.dart` to their screens and workflow families.
Role names describe the current router guard categories, not a substitute for
provider and Firestore authorization. Status below distinguishes source
inspection, regression-test coverage, and rendered visual acceptance.

All shell routes retain the existing authenticated-profile and tenant checks.
The router explicitly blocks seller access to route management, reports, and
settings; protects selected create/edit and administrator surfaces; and
applies separate workspace-management, backup-capability, and super-admin
flush checks. No guard or business behavior was changed for this UI pass.

Route registration and the principal shell/contextual entry points have been
cross-referenced. This is not yet a complete interaction inventory: every
dialog, sheet, menu, and role-specific state has not been exercised.

## Shared Workspace Logo and Export Path

Workspace logos are selected and processed locally as PNG, with orientation
correction and proportional resizing to the Firestore size limit. Processing
does not remove transparency or replace an opaque colored background.
Settings serialization, backup/restore, and invoice snapshots retain the
stored Base64 value. Shared financial PDF builders prefer current workspace
bytes, use the saved invoice logo when current bytes are unavailable, and
respect `visibleFields`. PDF, print, share, and PNG use the shared generated
PDF bytes; PNG output rasterizes the full page, so transparent pixels display
the page background. XLSX does not currently embed logos.

Focused tests verify stored alpha/RGB, opaque colors after resizing, PDF image
and alpha-mask resources, invoice-snapshot fallback, and logo visibility
filtering. Pixel-level rasterized PDF/PNG inspection and authenticated
browser/device visual acceptance remain unverified.

## Registered routes

| Screen / route | Role / guard context | Purpose and main actions | Data scope | Shared UI / states | Findings and implementation | Verification |
| --- | --- | --- | --- | --- | --- | --- |
| `/login` | Signed-out entry | Sign in and recover account access | Firebase Auth and profile bootstrap | Form controls, progress, mapped error | Fixed: narrow content is capped by the available viewport and the 420-logical-pixel design maximum, avoiding invalid constraints at intermediate widths | Regression covers six widths in EN/AR/UR; public page rendered at the failing width after hot reload with no runtime errors. Auth flow was not submitted |
| `/bootstrap-profile` | Signed in without a usable profile | Recover or complete profile setup | Auth identity and user profile | Loading, actionable recovery/error | No change in this pass | Source audit only |
| `/` | Active signed-in roles | Review dashboard metrics and navigate to work | Role-scoped aggregates, routes, shops, inventory | `StatCard`, loading, cached/error/empty | Stat-card value and entrance motion honor reduced-motion settings; pending-edit rows hide navigation affordance when no shop destination exists | Shared-widget tests; live role data unavailable |
| `/routes` | Administrator; seller blocked by router | Browse and manage routes | Tenant routes, sellers, shops | Search/filter, list, empty/error | No route-level change; route form concerns remain reported | Source audit only |
| `/routes/new` | Administrator create guard | Create a route | Routes and user assignments | Form, saving, validation/error | No change in this pass | Source audit only |
| `/routes/:id` | Active roles within existing scope | Inspect route and its shops | Route, shops, transactions | Summary, list, empty/error | No change in this pass | Source audit only |
| `/routes/:id/edit` | Administrator edit guard | Edit route assignment/details | Route and seller assignment | Edit loading/error, form/save | Fixed: waits for the active profile and route record, maps load failures with retry, and preloads the saved seller assignments and currency before enabling edit/save | Focused loading/error/retry/missing/data widget tests |
| `/shops` | Admin and assigned sellers, tenant/route scoped | Search, filter, create, open shops, and export | Shops, routes, transaction summaries | `AppFilterChipBar`, search, empty/error | Route-scoped metrics stay separate by currency and display full values in a horizontally scrollable strip; route metadata gates aggregates; shop list supports pull-to-refresh; multi-shop statement PDF opens the per-export Arabic/Urdu selector and applies the selected pair to its PDF labels/header | Currency-scope and multi-shop selector widget regressions; no rendered device review |
| `/shops/new` | Admin and assigned sellers with route constraints | Create a shop | Routes, tenant, shop form | Loading, validation, save/error | Route lookup failures show mapped feedback and retry; route selection/save remains gated until route data is usable | Focused route-query error/retry widget test |
| `/shops/:id` | Admin and assigned sellers within scope | Review balance, ledger, invoices, and actions | Shop, transactions, invoices | Balance badge, ledger, loading/error | Contextual actions share the phone/WhatsApp row above Total In/Total Out; location and overdue age share a compact row; ledger supports pull-to-refresh; statement exports offer Arabic/Urdu per-export choice; voided invoice rows and reversals are excluded from customer-facing ledger calculations | Role-placement and export-language widget regressions; authenticated live ledger and rendered-device acceptance remain open |
| `/shops/:id/edit` | Admin and assigned sellers within route constraints | Edit an existing shop | Shop, routes, tenant | Record loading, form/save/error | Fixed: profile and shop must load before fields; saved route and contact details are prefilled; load failure and missing data are explicit | Focused widget tests |
| `/products` | Active roles with read access | Search and browse products | Products and variants | Search/filter, status, empty/error | No change in this pass | Source audit only |
| `/products/new` | Administrator create guard | Create a product | Products, variants/settings | Form, validation, save/error | No change in this pass | Source audit only |
| `/products/:id` | Active roles with read access | Inspect product and variants | Product, variants, inventory | Summary, stock/status, loading/error | No change in this pass | Source audit only |
| `/products/:id/edit` | Administrator edit guard | Edit product details | Product and settings | Record loading, form/save/error | Fixed: profile and product must load before fields; failures and missing data are explicit | Focused widget tests |
| `/products/:id/variants/new` | Administrator create guard | Add a variant | Product and variants | Form, validation, save/error | No change in this pass | Source audit only |
| `/products/:id/variants/:vid/edit` | Administrator edit guard | Edit a variant | Product, variant, inventory | Record loading, form/save/error | Fixed: profile and matching variant must load before fields; retry and missing-data states are explicit | Focused widget tests |
| `/inventory` | Admin and assigned sellers, role scoped | Review stock and permitted stock actions | Warehouse or seller inventory and audit rows | Loading, list, empty/error, dialogs | Fixed: add/transfer dialogs show localized loading, empty, and mapped error/retry states for product, variant, and seller choices; quantity actions wait for settings instead of assuming 12 pairs per carton | Inventory widget tests cover settings failure, selection loading/error/retry, and successful provider recovery |
| `/invoices` | Active roles within tenant scope | Search and browse invoices | Tenant invoices, shops, users | Search/filter, status, empty/error | Summary totals are grouped by invoice currency; Pending shows outstanding sale invoices only; pull-to-refresh works with both populated and empty filtered results | Mixed-currency/void-summary and Pending filter widget regressions |
| `/invoices/new` | Active roles subject to stock, route, and workspace policy | Create stock/non-stock sale or cash receipt | Shop, product/variant, inventory, settings | Form, mode, validation, saving/error | Profile loading remains visible; profile errors show mapped retry and a missing profile no longer spins indefinitely | Focused auth-profile failure widget test; normal authorized workflow not exercised |
| `/invoices/:id` | Active roles within tenant scope | Inspect invoice and permitted actions | Invoice, shop, ledger, stock | Detail, loading/error | No change in this pass | Source audit only |
| `/users` | Administrator account-management guard | Manage permitted user profiles | Tenant users and routes | List, edit, loading/error | Seller route choices distinguish loading, empty, and retryable route-query errors; create/edit/reactivate validates selections against loaded routes and refreshes names from canonical route data | Focused route-option retry widget test; analyzer-clean async context guard |
| `/tenants` | Workspace-management role guard | Browse/manage permitted workspaces | Workspace metadata and scoped owners | List, selection, empty/error | Tenant admins see workspace metadata but not platform create/edit/support-access actions; no authorization semantics changed | Tenant-admin role-branch widget test; source review |
| `/history` | Admin and seller | Review recent activity and open linked records | Role-scoped recent transactions/activity | Feed, empty/error, row navigation | Rows without a shop destination no longer show a navigation chevron | Source review; no dedicated row-interaction widget test |
| `/notifications` | Administrator guard | Review and mark notifications | Tenant notifications | List, empty/error, bulk action | Mark-all action disables during commit, shows progress, and maps write failures; tiles without a shop destination hide the chevron | Focused delayed-failure widget test |
| `/reports` | Administrator; seller blocked by router | View and export financial/operational reports | Tenant-scoped routes, shops, invoices, transactions | Filters, charts, exports, progress/error | Summary totals stay currency-separated; monetary export rows carry route currency. Export cards disable duplicate taps, expose progress, and map failures; account-statement and seller-report actions also expose generation state and mapped errors | Focused delayed-provider test verifies busy/disabled and mapped-failure states; source review of remaining export cards |
| `/profile` | All active roles | Edit personal profile, theme, language, password | Current user's profile and Auth-owned flows | Form, preferences, save/error | Dirty-state guard compares the sanitized edited name with the saved value, so restoring the original does not trigger an unsaved-change prompt | Focused widget test |
| `/about` | All signed-in roles | View app information and changelog | Local app metadata | Static content and links | No change in this pass | Source audit only |
| `/settings` | Administrator settings guard | Configure workspace business preferences | Active workspace settings | Settings controls and save/error | Settings follow remote snapshots while clean and preserve local edits; pull-to-refresh added; separate legacy business-name input removed | Focused live-settings hydration widget test |
| `/settings/invoice-header` | Nested settings route; screen/provider checks remain authoritative | Configure invoice header | Workspace settings | Form, preview, save/error | Canonical workspace branding with title scale and reprint policy; clean forms hydrate remote changes without overwriting dirty edits; pull-to-refresh added | Focused live-header hydration/model/PDF tests |
| `/settings/flush` | Super-admin-only router guard | Run authorized workspace data flush | Explicitly selected workspace and destructive confirmation | Loading, confirmation, error | Auth/workspace loading and mapped retry states are explicit; destructive actions remain disabled until the selected workspace is available; per-user loading, empty, and error/retry states are visible | Focused workspace/user query retry widget test |
| `/settings/backup` | Backup-capability router guard | Export or restore authorized workspace backup | Role- and workspace-scoped archive data | Progress, preview, confirmation, error | Selected workspace loading/error feedback is explicit; backup and restore actions remain disabled until workspace metadata is available | Focused selected-workspace error/retry and action-gating widget test |

## Cross-screen state and component baseline

The shared component foundation changed in this pass:

- `AppTokens.minTouchTarget` is 48 logical pixels; `AppFilterChipBar` now uses
  it, including in RTL direction.
- `AppMotion` reads `MediaQuery.disableAnimations`. Empty/error illustrations,
  stat-card transitions, status-chip transitions, and every shared
  `AppAnimations` preset suppress optional motion when requested.
  Custom router fade/scale and form slide transitions also bypass their
  effects when reduced motion is enabled.
  `PressableWidget` remains actionable without scale feedback.
- `AppBalanceBadge` exposes the localized balance label and amount as one
  semantic value.
- Focused tests cover EN/AR/UR semantics, reduced-motion states, RTL target
  sizing, and success/error semantic color contrast.

For each affected screen family, production UI still needs visual review at
compact and expanded widths, both RTL locales, all supported themes, and a
large text scale. The source register does not claim these checks are complete.

## Shell and contextual entry points

- Compact navigation and the wide navigation rail derive from `AppShell`'s
  role-filtered destination list. Destinations include dashboard, routes,
  shops, products, inventory, invoices, reports, workspaces, users, settings,
  and about; sellers and root platform super-admins receive narrower lists.
- Long-press quick actions open new shops, routes, products, and invoices.
  Profile is available from shell actions.
- Dashboard shortcuts link to routes, shops, products, inventory, workspaces,
  currency-filtered shops, and shop details. Route details link to route edit,
  shops, and route-prefilled shop creation. Product details link to product
  edit and variant creation. Invoice lists link to invoice creation and detail.
- Settings links to workspace selection, profile, about, invoice-header
  settings, backup, and super-admin flush. Notification and history rows link
  to shop detail only when a shop ID is present.

## Finding disposition and remaining review

The following items were reported by the preceding source audits. They are
tracked, not yet claimed fixed; reproduce the exact route/state and read the
complete screen-to-provider path before implementing each change:

| ID | Affected screens | Reported issue | Priority | Status |
| --- | --- | --- | --- | --- |
| UI-01 | Dashboard, history, notifications | A row may show a navigation chevron when its shop link is empty and the row has no destination | Medium | Fixed in the three row builders; history/notification widget checks remain a coverage gap |
| UI-02 | Notifications | Mark-all action may lack visible busy and failure feedback | Medium | Fixed; delayed provider failure test verifies progress and mapped error feedback |
| UI-03 | Profile | Dirty state may stay set after values are restored to their original state | Medium | Fixed; focused widget test verifies the pop guard resets |
| UI-04 | Route, shop, product, variant edit forms | Interaction/save may be enabled before the record loads; some load errors may lack retry | High | All four edit forms now gate on profile and record loading, expose retry/missing-data states, and have focused regression tests |
| UI-05 | Shops list and shop form | Currency/route loading may briefly leave filters unscoped; no-route sellers may remain loading; route lookup errors may lack retry | High | Currency-filtered shop list waits for route scope and exposes retry; shop-form route-query failures now show mapped retry feedback and gate route-dependent submission |
| UI-06 | Inventory dialogs | Product, variant, or seller streams could appear as empty choices while loading or failed; missing settings could silently assume 12 pairs per carton | High | Fixed: explicit localized selection states and retry controls; settings failures block quantity entry/actions, and dialogs receive the loaded workspace carton size |
| UI-07 | Invoice list and reports | Multi-currency totals or exports may use a mismatched currency | High | Fixed: account-statement spreadsheet and PDF output use the selected shop's resolved route currency; seller-report rows use each transaction's route currency, current balances use each shop's current route currency, and PDF totals are grouped by currency. Admin export route metadata includes inactive routes for historical records. Focused mixed-currency PDF/helper tests pass; authenticated viewer acceptance remains open |
| UI-08 | Reports | Export actions may lack local progress/error feedback | Medium | Fixed: export cards show progress, block duplicate taps, and map failures; account-statement and seller-report actions show their own generating state and mapped errors |
| UI-09 | Invoice creation | Auth/profile provider failure may leave the form in indefinite progress | High | Fixed; auth loading, mapped error/retry, and absent-profile states are distinct; failure widget test added |
| UI-10 | Users, flush, backup | Route/workspace data errors may render like empty or unavailable data | Medium | Fixed: user route choices and backup/flush workspace and user queries expose retryable failures; backup/flush actions wait for required workspace state |
| UI-11 | Tenant management | A route/role branch was reported as inconsistent; authorization semantics need separate review | High | Source-reviewed and covered by a tenant-admin widget regression: tenant admins see workspace metadata only, while platform actions remain hidden; authorization semantics unchanged |
| UI-12 | Settings | A prior audit mentioned Firebase Storage, conflicting with the no-Storage runtime contract | High | `app/lib` source scan found no Firebase Storage references; no Storage dependency or behavior was added |
| UI-13 | Dashboard stat cards | Entrance animation did not consult the system reduced-motion preference | Medium | Fixed; entrance animation is omitted when reduced motion is enabled |
| UI-14 | Shared animation presets | `screenEntry`, `listEntry`, and other `AppAnimations` effects did not consult the inherited reduced-motion preference | Medium | Fixed centrally in `app_animations.dart`; all presets bypass nonessential effects while preserving their children, and `PressableWidget` keeps tap/semantic actions without scale feedback. Focused widget regression passes |
| UI-15 | Login | At widths below the 720-pixel wide-layout breakpoint, the computed minimum form width could exceed its fixed 420-pixel maximum and crash layout | High | Fixed by capping maximum width to the lesser of 420 pixels and available width. A pre-fix regression reproduced the exact `620<=w<=420` failure at 668 pixels; post-fix tests cover six widths in EN/AR/UR, and the local public login page rendered without runtime errors |
| UI-16 | GoRouter page transitions | Custom fade/scale and form slide transitions did not consult `MediaQuery.disableAnimations` | Medium | Fixed in both page builders using `AppMotion.isEnabled(context)`; tests confirm these transitions are absent when motion is disabled and retained when enabled |

The named source-review findings UI-01 through UI-16 are now dispositioned.
Full dialog/sheet interaction coverage and rendered acceptance remain open.
The public `/login` page was available and rendered in a local browser after
the fix; authenticated role accounts were not available, so role/theme
appearance on business screens remains unverified rather than inferred from
source or widget tests.

## v3.10.15+1126 Contextual-Action Register

The shared contextual presenter is integrated on these record surfaces:

| Surface | Available contextual actions | Eligibility source | Status |
|---|---|---|---|
| Routes list and dashboard route rows | Open route details; copy route reference | `viewRoutes` | Implemented |
| Shop list, route-detail shops, dashboard shop shortcuts, report outstanding shops | Open details; edit where permitted; create invoice; copy phone when present | `viewShops`, `manageShops`, `createInvoice` | Implemented; existing route/provider guards remain |
| Product list and product details | Open details; edit where permitted; copy product reference | `viewProducts`, `manageProducts` | Implemented |
| Product-variant rows | Edit where permitted; copy variant reference | `manageProducts`, `viewProducts` | Implemented |
| Inventory variant rows | Copy product/variant reference | `viewInventory` | Implemented |
| Invoice list | Open invoice details; copy invoice reference | `viewInvoices` | Implemented |
| History transaction rows and dashboard pending-edit rows | Open linked invoice/shop where available; copy invoice or transaction reference | `viewHistory` | Implemented |
| Notification rows | Open the referenced shop when available; mark the notification read | `viewNotifications` | Implemented; existing notifier and Rules contract unchanged |
| Shop-detail ledger rows | Existing transaction edit, approval, rejection, and soft-delete flows; copy reference | `viewHistory`, `editLedger` plus existing row-state guards | Implemented; visible menu button retained |

The shared wrapper supports touch long-press, web secondary click,
Context-menu/Shift+F10 keyboard entry, and custom screen-reader actions.
Ordinary row taps and nested controls remain available. Actions are scoped by
entity, active profile, concrete tenant, enabled state, and
`PermissionPolicy`; selection reads the current profile again and invokes the
current eligible callback. This is presentation filtering only, not a
replacement for route, provider, or Firestore authorization.

User/workspace administration, settings, and form-level destructive controls
remain explicit rather than receiving generic record gestures. Their actions
have distinct confirmation and security flows, or are not record-level list
targets. This avoids duplicating sensitive operations in an opaque menu.

Automated coverage verifies role/entity filtering, inactive and global-scope
denial, long-press invocation, primary and nested taps, keyboard context-menu
entry, and a narrow RTL layout with large text. The focused release suite
reported `00:11 +33: All tests passed!`; the full serial Flutter suite
reported `02:40 +716: All tests passed!`. Screen-reader interaction,
secondary-click behavior, rendered theme contrast, and authenticated device
acceptance are not yet manually verified.

## 2026-10-24 Operational Refresh and Financial Presentation

Workspace settings continue to update through Firestore listeners; form
controllers now hydrate from later snapshots only while unchanged by the user.
The general settings and invoice-header forms expose pull-to-refresh without
discarding local edits. Shop lists, invoice lists, and shop-detail ledgers
also expose refresh gestures, including empty list states.

Shop `I got`, `I gave`, and `I will get` summaries group by route currency and
show full numeric values instead of mixing SAR/PKR or abbreviating large
amounts. Invoice Pending filters issued/partially paid sales with a positive
outstanding amount and excludes paid, void, receipt, and credit-note documents.
Shop detail combines location and overdue age into one row.

Invoice voiding marks linked ledger rows and compensating reversals in the
same Firestore transaction. Customer-facing shop streams and complete report
exports exclude those rows; the admin-wide transaction provider keeps audit
records visible. Credit-balance voids preserve the original collected payment
as customer credit. Receipt PDFs emphasize the received amount, payment
metadata, before/after balances, and signature lines. Statement summary labels
inherit Arabic/Urdu direction, and PDF reports use the workspace invoice
header. No rules/deployment or release operation was performed. Source and
widget verification does not replace authenticated browser/device review.
