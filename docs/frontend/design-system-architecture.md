# ShoesERP Frontend Design System and Architecture

## Purpose and status

This document records the current Flutter presentation architecture and names
the existing owners of visual and interaction behavior. It is a reference for
ongoing screen modernization, not a claim that every screen has been migrated
to the shared patterns or visually accepted on every device.

The product is a route-based footwear distribution ERP. Its interface should
make operational work, quantities, balances, status, and next actions easy to
scan. Preserve the established Arctic blue and navy identity and avoid
decorative elements that compete with business information.

## Ownership map

| Concern | Source of truth | Responsibility |
| --- | --- | --- |
| Brand identity and semantic brand colors | [`app_brand.dart`](../../app/lib/core/constants/app_brand.dart) | Product identity, brand palette, status and feedback colors, version identity |
| Theme construction | [`app_theme.dart`](../../app/lib/core/theme/app_theme.dart) | Material 3 color schemes, typography application, component themes, theme variants |
| Spacing, shape, size, and breakpoints | [`app_tokens.dart`](../../app/lib/core/design/app_tokens.dart) | Shared values for layout rhythm, touch targets, controls, responsive thresholds, and motion durations |
| Locale-aware UI fonts | [`app_fonts.dart`](../../app/lib/core/theme/app_fonts.dart) | English, Arabic, and Urdu UI typefaces and locale-specific text styles |
| Optional motion helpers | [`app_animations.dart`](../../app/lib/core/design/app_animations.dart) | Reusable entrance/interaction animations and reduced-motion access |
| Locale, translation, and direction | [`app_locale.dart`](../../app/lib/core/l10n/app_locale.dart) | English, Arabic, and Urdu selection, text direction, and string lookup |
| Shared interaction and state widgets | [`app/lib/widgets/`](../../app/lib/widgets/) | Shared controls, feedback states, search/filter, status, balance, charts, and export entry points |
| Route registration and guards | [`app_router.dart`](../../app/lib/core/router/app_router.dart) | Registered destinations, role redirects, and route transitions |
| Adaptive navigation shell | [`app_shell.dart`](../../app/lib/widgets/app_shell.dart) | Role-filtered destinations, compact bottom navigation, wide navigation rail, and shell back behavior |
| Screen-level state and task composition | Screen widgets under [`app/lib/screens/`](../../app/lib/screens/) | Forms, details, lists, reporting, and orchestration of providers and shared UI |

Use these owners rather than creating screen-local competing palettes,
typography scales, spacing systems, theme providers, or navigation frameworks.
The reference implementation is [`frontend-design-system.instructions.md`](../../.github/instructions/frontend-design-system.instructions.md).

## Brand, theme, and typography

`AppTheme` builds Material 3 themes for automatic, light, dark, and high-contrast
modes. The theme selection also depends on the current locale and, for
automatic mode, system brightness. Use `Theme.of(context).colorScheme` and
the existing semantic brand values for screen colors.

`AppFonts` selects bundled UI typefaces by locale:

| Locale | Headings | Body |
| --- | --- | --- |
| English | Syne | DM Sans |
| Arabic | Noto Sans Arabic | Noto Sans Arabic |
| Urdu | Noto Nastaliq Urdu | Noto Nastaliq Urdu |

Arabic and Urdu screens are right-to-left; the selected locale supplies
directionality. Use directional padding, alignment, and icon placement when
meaning depends on reading order. Test mixed-script content, including Latin
route identifiers, numerals, dates, telephone numbers, and amounts.

The UI font contract is not the PDF font contract. Arabic/Urdu report shaping,
embedded PDF fonts, export automation flags, and print/share behavior are
specified separately by the [`analytics-reporting` skill](../../.claude/skills/analytics-reporting/SKILL.md).
Do not infer PDF quality from a correctly rendered Flutter screen.

## Layout and adaptive navigation

`AppTokens` provides the 8-logical-pixel spacing family, shared radii, control
sizes, motion constants, and responsive thresholds. Its current width
thresholds include 600, 900, and 1200 logical pixels; navigation changes to a
rail at 720 and uses the extended rail at 1024. These are current project
values, not universal platform breakpoints.

`AppShell` shows role-filtered destinations. Compact layouts use bottom
navigation and shell actions; wide layouts use a scrollable navigation rail.
Screens should size their own content from available constraints and remain
usable in both shell modes. Avoid fixed-width layouts and device-name checks.

The shell and the router serve different jobs: route registration and access
redirects are defined in `app_router.dart`; the shell controls navigation
presentation, selected destinations, and back behavior. Preserve both when
modernizing a screen, and verify the actual entry point and return route before
changing navigation.

## Shared component and state patterns

Reuse the existing widgets when their responsibilities fit:

| Need | Existing component examples |
| --- | --- |
| Loading, empty, and retryable error feedback | `ShimmerLoading`, `EmptyState`, `ErrorState` |
| Search, refresh, and filtering | `AppSearchBar`, `AppPullRefresh`, `AppFilterChipBar` |
| Financial and operational summaries | `AppBalanceBadge`, `StatCard`, `AppChartCard`, `AppSectionHeader` |
| Status and role communication | `StatusChip`, `RoleGuard` |
| Data entry and confirmation | `AppAmountField`, `TransactionDescriptionField`, `ConfirmDialog` |
| Export and sharing actions | `ExportSheet` |

Each asynchronous screen should distinguish loading, usable data, empty data,
failure/retry, saving, disabled, and success states as relevant. A query error
must not be represented as an empty collection or editable default. For edit
forms, do not enable fields or save until the requested record has loaded;
initialize the form from the record once, preserve loaded values, and keep
provider-side role and tenant checks as the authorization boundary.

Use a minimum 48-logical-pixel hit target for shared interactive controls.
Keep visible labels, focus/selected/disabled semantics, and localized error
feedback. Optional motion should honor `MediaQuery.disableAnimations` through
`AppMotion`; the shared `AppAnimations` presets enforce this at their common
wrapper so callers cannot accidentally omit the preference check. Press
actions remain available when scale feedback is suppressed. Animation must
not block or delay an operation.

## Localization and accessibility

- Keep user-visible content in the EN/AR/UR translation maps.
- Preserve right-to-left layout in Arabic and Urdu and use directional
  properties for semantic start/end positions.
- Check text scaling, focus order, labels, error identification, and touch
  targets for the affected task and viewport.
- Verify contrast using the actual foreground/background pair in light, dark,
  and high-contrast themes; semantic color names alone are not proof of
  sufficient contrast.
- Test long names, long translations, mixed-direction identifiers, and narrow
  layouts where the screen contains forms, tables, or financial values.

## Data and authorization boundaries

Screens watch providers and call notifier methods; all Firestore writes remain
in providers. Router guards and visible controls improve the user experience
but do not replace provider checks or Firestore Rules. Keep tenant scope,
role-aware provider invalidation, inventory invariants, and atomic financial
operations unchanged during visual work.

## Modernization and acceptance status

The shared design foundation has tests for reduced-motion behavior, localized
balance semantics, filter hit-target sizing, and selected semantic colors.
The route edit form now has explicit profile/record loading, retry, missing
record handling, and a loaded-record save guard. The full screen inventory and
remaining source-audit findings are tracked in the
[`screen-register.md`](./screen-register.md).

The current repository does not have complete rendered acceptance evidence
for all routes, roles, themes, locales, viewport sizes, and text scales.
Widget tests and source inspection are not treated as substitutes for that
visual review. Record unavailable browser, device, authentication, or data
access explicitly rather than claiming coverage.

## Related implementation guidance

- [Frontend implementation standards](../../.github/instructions/frontend-design-system.instructions.md)
- [Flutter frontend modernization workflow](../../.claude/skills/flutter-frontend-modernization/SKILL.md)
- [Frontend UI audit workflow](../../.claude/skills/frontend-ui-audit/SKILL.md)
- [Accessibility and RTL workflow](../../.claude/skills/flutter-accessibility-rtl/SKILL.md)
