---
name: flutter-frontend-modernization
description: "Use when: auditing or modernizing ShoesERP Flutter screens, workflows, shared widgets, themes, navigation, accessibility, or rendered UI."
---

# ShoesERP Flutter Frontend Modernization

## Purpose

Coordinate evidence-based UI work across the existing Flutter application. This
skill discovers affected screens and shared surfaces, selects specialist
guidance, preserves business behavior, and closes with functional and visual
verification.

## Invocation

Use for application-wide UI/UX audits, redesigns spanning multiple screens,
design-system changes, and cross-screen interaction improvements. For a single
form or navigation issue, invoke the relevant specialist directly and use this
workflow at the scope of that change.

## Required inputs

- User-visible goal and explicitly excluded runtime behavior.
- The actual router/shell, affected screen files, and existing design system.
- Current Git status and validation commands.
- Target locales, roles, platforms, and available visual-testing tools.

Do not ask the user to enumerate routes that the repository can reveal.

## Workflow

1. Before source edits, review the active todo list and Git status/diff, merge
   new work without dropping unfinished tasks, then load all applicable
   project skills and `.github/instructions`. Read `AGENTS.md`, `CLAUDE.md`,
   affected architecture/design docs, and the source paths; preserve all
   pre-existing modifications. Treat this context-and-skills gate as the
   first implementation step.
2. Discover routes from `app_router.dart`, top-level navigation and secondary
   entry points from `app_shell.dart`, then cross-reference screen files and
   tests. Do not treat README route lists as authoritative.
3. Trace each requested action from widget through Riverpod state/notifier to
   its existing data source. Do not change business meaning or authorization
   to make a visual flow easier.
4. Load only the specialist skills needed:
   - `frontend-ui-audit` for screen/state inventory and defect triage.
   - `frontend-design-system` for tokens, theme, and shared component changes.
   - `navigation-routing` or `flutter-navigation-ux` for navigation.
   - `ui-mobile-forms` for form lifecycle and input behavior.
   - `flutter-accessibility-rtl` for semantics, locale, and directionality.
   - `performance-optimization` for measured performance work.
   - `testing-strategy` for widget, integration, and visual validation.
   - `analytics-reporting` for report, PDF, Excel, image, print, and sharing.
5. Implement in bounded, related screen families. Keep one source of truth in
   `frontend-design-system.instructions.md`; improve existing assets before
   introducing new abstractions or dependencies.
6. For record-level secondary actions, reuse `AppContextualActions` and its
   capability-filtered catalog. Preserve primary taps and nested controls;
   support touch, secondary-click, keyboard, and semantic entry points where
   applicable. Recheck the active profile and capability on selection, and
   reuse the existing guarded callbacks rather than adding widget writes.
7. Verify route access, actions, async states, localized text, and persisted
   results. Test role filtering, inactive/unscoped profiles, nested controls,
   RTL, and large text where applicable. Inspect rendered output at
   representative constraints and themes where the environment and test data
   permit.
8. For workspace-logo work, inspect upload/compression/storage and all
   `ExportContext`/PDF/report/image paths. Preserve transparency for alpha
   assets and retain opaque colored backgrounds; do not auto-remove, flatten,
   or tint. Verify representative transparent and opaque fixtures through
   persisted data and rendered exports.
9. Update the screen register and audit report with implementation and
   verification status. Mark unverified states and blockers explicitly.
10. Run focused tests, analysis, and documentation lint. Broaden validation only
   when shared behavior or observed regressions require it.

## Output

For broad audits, deliver a route/screen/state register, prioritized findings,
implemented changes, exact validation results, visual evidence where available,
and remaining risks. For a bounded fix, report affected surfaces and exact
tests. Never report a recommendation as an implemented or visually verified
change.

## Boundaries

This skill does not authorize changes to Firebase Auth, Firestore Rules,
tenant/role authorization, financial or inventory semantics, schemas, release
versions, production data, deployment, installation, commits, or pushes. Follow
the corresponding repository contracts and obtain explicit user authorization
for operational side effects.

## Validation references

- Authoritative UI contracts: `.github/instructions/frontend-design-system.instructions.md`
- Runtime and release boundaries: `AGENTS.md` and `CLAUDE.md`
- Markdown: `.claude/skills/markdown-governance/SKILL.md`
