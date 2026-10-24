---
name: frontend-design-system
description: "Use when: changing ShoesERP design tokens, themes, typography, shared Flutter components, responsive conventions, or visual consistency."
---

# ShoesERP Frontend Design System

## Purpose

Maintain one coherent, testable Flutter visual language for the footwear
distribution workflows. The canonical rules are
`.github/instructions/frontend-design-system.instructions.md`; this skill
explains how to apply them.

## Invocation

Use when modifying `AppTokens`, `AppTheme`, `AppFonts`, `AppAnimations`, shared
widgets, or a screen family whose visual behavior needs a coordinated pattern.

## Required inputs

- The actual screen/widget and its route, user role, and primary task.
- Existing light, dark, high-contrast, and locale variants.
- Current widget/theme tests and representative viewport constraints.

## Workflow

1. Inspect the existing brand, token owners, component library, and call sites.
2. Identify the smallest shared abstraction that solves the repeated need.
3. Define semantic component states and theme-derived colors before styling.
4. Check long text, large text scale, narrow constraints, RTL, and dark/light
   surfaces. Avoid assumptions from a single screenshot or locale.
5. Use `AppTokens.minTouchTarget` for interactive targets and honor
   `MediaQuery.disableAnimations` through `AppMotion` for optional motion.
   Every `AppAnimations` preset must suppress its effect when motion is
   disabled; verify the shared preset test rather than relying on each caller
   to remember a local guard.
6. Implement the shared primitive and migrate only relevant call sites.
7. Add tests for its state, semantics, theme values, and responsive behavior.
8. Review actual rendered output when the environment permits.

## Output

Document the changed token/component contract, migrated surfaces, tests, and
any unsupported or unverified theme/locale/viewport combinations.

## Dependencies and boundaries

Depends on the UI standards in `.github/instructions/frontend-design-system.instructions.md`
and runtime constraints in `AGENTS.md`. It does not own navigation guards,
data providers, financial calculations, or authorization. Do not add a design
package or duplicate token system without measured need and compatibility
evidence.

## Validation

Run focused widget tests and `flutter analyze lib --no-pub`. For visual changes,
capture/inspect representative light, dark, and supported RTL output when
available; a source review or passing unit test alone is not visual evidence.
