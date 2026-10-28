---
description: "Authoritative Flutter UI standards for ShoesERP themes, tokens, shared components, accessibility, RTL, adaptive layout, interaction, and visual validation."
applyTo: "app/lib/core/design/**/*.dart,app/lib/core/theme/**/*.dart,app/lib/widgets/**/*.dart,app/lib/screens/**/*.dart"
---

# ShoesERP Flutter Frontend Standards

This is the authoritative UI implementation contract for Flutter code. Use it
with `AGENTS.md` and `CLAUDE.md`; it does not supersede runtime, tenant,
financial, provider, or release-safety requirements.

## Source ownership

Extend the existing design system. Do not introduce a parallel token or theme
layer.

| Concern | Authoritative implementation |
| --- | --- |
| Brand and semantic palette | `app/lib/core/constants/app_brand.dart` and `app/lib/core/theme/app_theme.dart` |
| Spacing, shape, sizes, breakpoints, motion constants | `app/lib/core/design/app_tokens.dart` |
| Locale-aware UI and PDF fonts | `app/lib/core/theme/app_fonts.dart` and the export-specific contract in `analytics-reporting` |
| Animation helpers | `app/lib/core/design/app_animations.dart` |
| Shared controls and empty/loading/error states | Existing widgets under `app/lib/widgets/` |
| Routes, redirects, and shell navigation | `app/lib/core/router/app_router.dart` and `app/lib/widgets/app_shell.dart` |
| Locale direction and translations | `app/lib/core/l10n/app_locale.dart` |

Use semantic theme values such as `colorScheme`, `AppTheme`, and named tokens
instead of introducing screen-local colors, spacing scales, radii, or type
families. A literal color is acceptable only when its contrast and purpose are
explicitly tied to a surface or status; `Colors.white` is not inherently a
theme defect.

## Product visual direction

ShoesERP is a route-based footwear distribution ERP, not a generic analytics
dashboard. Optimize operational clarity, legible quantities and currency,
compact scanning, clear status, and low-friction actions. Preserve the existing
Arctic blue/navy brand and supported light, dark, and high-contrast modes unless
research and rendered checks justify a coordinated change.

Use cards, badges, shadows, charts, and animation only when they improve
grouping, state recognition, or task completion. Do not force every workflow
into identical metric cards or add decorative data, gradients, or motion.

## Layout and interaction

- Base layout decisions on available constraints, not device-name checks.
  Prefer `LayoutBuilder` for local content constraints and `MediaQuery.sizeOf`
  for window-level decisions; verify APIs against Flutter 3.41.6.
- Preserve current routes and role-aware entry points. Read the actual router
  and `AppShell` before changing navigation; do not add a drawer package or
  fixed destination counts by convention.
- Keep list, detail, form, and destructive actions recognizable. Every action
  must remain connected to its existing notifier/provider and preserve the
  current data contract.
- Provide visible loading, empty, error/retry, disabled, saving, and success
  feedback appropriate to each async operation. Do not disguise a failed
  provider as an empty result.
- Use `AppTokens.minTouchTarget` for shared interactive controls unless a
  documented platform constraint requires a different hit-area implementation.
- Use `AppMotion.isEnabled(context)` / `AppMotion.duration(...)` for optional
  shared-component transitions so system reduced-motion preferences are honored.
- Keep the primary operation reachable at narrow widths, large text scales,
  keyboard-open layouts, and RTL locales. Use directional padding/alignment
  when direction is semantic.
- Respect `MediaQuery.disableAnimations` for newly introduced motion. Motion
  must communicate a state change and must not delay a business action.

## Accessibility, localization, and RTL

- Preserve English, Arabic, and Urdu. Do not hardcode user-visible text.
- Give icon-only actions tooltips and meaningful semantics. Ensure controls have
  clear focus, enabled, disabled, pending, and selected states.
- Check contrast for actual foreground/background pairs in light, dark, and
  high-contrast modes. WCAG 2.2 AA uses 4.5:1 for ordinary text and 3:1 for
  large text. Flutter's 48x48 touch-target guidance is not the same measurement
  as WCAG 2.2 SC 2.5.8's 24x24 CSS-pixel minimum for web content.
- Verify text scaling, focus order, labels, error identification, and targets
  with Flutter accessibility guidelines where available, then manually inspect
  assistive-technology behavior when the target environment permits.
- Test both Arabic and Urdu directionality, mixed Latin identifiers, digits,
  phone numbers, dates, and amounts. UI Urdu uses the bundled Nastaliq family;
  PDF font selection, shaping flags, print/share, and spreadsheet limitations
  are governed by the analytics-reporting skill and must not be inferred from
  UI font behavior.
- Firestore-backed text can contain Arabic or Urdu even when the app locale is
  English. Preserve the locale's primary UI family and provide ordered bundled
  Noto fallbacks through `AppFonts`; test Arabic-script names and currency
  symbols in English, Arabic, and Urdu styles. This UI fallback does not change
  the independent PDF font/shaping policy.

## Performance and state

- Profile before making or claiming a performance optimization.
- Keep expensive work out of `build()`, scope provider watches, and use lazy
  builders for long or paged collections. Choose pagination and query limits
  from product behavior; do not impose arbitrary limits that truncate exports.
- Do not add listeners, Firestore reads, or dependencies for visual polish
  without a measured need and a verified benefit.
- Preserve role-scoped provider invalidation and loading/error semantics.
  Business authorization remains in providers and Firestore Rules, never in
  widget visibility alone.

## Required implementation workflow

1. Identify the screen, route, role, primary task, and neighboring workflows.
2. Read the complete affected widget and trace its provider/notifier path before
   changing behavior. Inspect shared components and current theme usage.
3. Reuse or improve the existing shared component before adding another one.
4. Implement the smallest coherent UI change without altering auth, tenant,
   financial, stock, or authorization behavior.
5. Add widget tests for observable behavior and all materially changed states.
   Include RTL and accessibility checks when the affected surface supports them.
6. Run focused tests, Dart analysis, and Markdown lint when applicable.
7. Inspect actual rendered output for the changed viewport/locale/theme when
   tooling and data access permit. Record unavailable visual checks explicitly.

## Boundaries

This instruction owns UI composition and visual consistency only. Use the
navigation-routing, ui-mobile-forms, accessibility/RTL, performance, testing,
and analytics-reporting skills for their respective procedures. It does not
authorize role changes, Rules changes, new backend behavior, version bumps,
release builds, deployments, commits, or pushes.
