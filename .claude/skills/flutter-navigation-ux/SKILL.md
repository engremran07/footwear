---
name: flutter-navigation-ux
description: "Use when: improving ShoesERP Flutter navigation, responsive shell layout, destination visibility, app bars, tabs, drawers, or transitions."
---

# ShoesERP Flutter Navigation UX

## Purpose

Make navigation predictable and adaptive while preserving the routes, role
scope, and shell behavior already implemented by ShoesERP.

## Invocation

Use for changes to `AppShell`, top-level navigation, app bars, responsive
navigation layout, tabs, drawers, navigation transitions, or navigation
entrypoints shared across screen families.

## Required inputs

- Current `app_router.dart`, `app_shell.dart`, and role-filtering helpers.
- Supported app surfaces and available window constraints.
- Relevant route, shell, localization, and widget tests.

## Workflow

1. Inspect the live navigation structure and all current destinations before
   proposing a new pattern. Confirm which routes are top-level, secondary,
   role-filtered, or reached from contextual actions.
2. Choose a layout from available space and task frequency. Validate with
   `LayoutBuilder` or `MediaQuery.sizeOf` as appropriate, not assumptions about
   a device category.
3. Keep primary actions and frequently used destinations discoverable without
   overflowing narrow layouts. Use the current rail, navigation bar, drawer,
   app bar, or tabs when they already fit the task.
4. Preserve route semantics: section navigation replaces the current section
   when expected; detail/form entry retains a useful return path; sign-out and
   role changes follow the router's current redirects.
5. Keep labels localized, tooltips available for icon-only actions, focus order
   logical, and directional placement correct in Arabic and Urdu.
6. Add motion only when it communicates a transition. Respect reduced-motion
   settings and keep navigation responsive.
7. Test narrow and expanded constraints, RTL, role-filtered destinations, deep
   links, and back behavior for the changed shell path.

## Output

Describe the current navigation evidence, changed entrypoints, role/viewport
coverage, and actual navigation tests or rendered checks.

## Avoid

- Do not require `flutter_zoom_drawer` or any package for a visual effect.
- Do not prescribe a fixed bottom-navigation item count or destination list
  without product and viewport evidence.
- Do not copy web/React navigation patterns into Flutter without checking
  platform behavior.
- Do not hide an important destination merely to make a screenshot simpler.
- Do not use animation to mask loading or missing state.

## Boundaries

This skill owns navigation presentation and interaction. Route registration and
redirect behavior belong to `navigation-routing`; shared visual tokens belong
to `frontend-design-system`; keyboard, semantics, and RTL acceptance belong to
`flutter-accessibility-rtl`. Authorization remains in the router, providers,
and Firestore Rules as currently defined.

## Validation

Run the smallest relevant widget/router tests and `flutter analyze lib
--no-pub`. Inspect actual rendered output at representative constraints when
possible; state explicitly if browser/device access or role credentials are
unavailable.
