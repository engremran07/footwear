---
name: frontend-ui-audit
description: "Use when: mapping ShoesERP screens, routes, workflows, interaction states, shared components, or conducting a cross-application UI/UX audit."
---

# ShoesERP Frontend UI/UX Audit

## Purpose

Create an evidence-based map of the real Flutter interface and identify
actionable defects without changing unrelated business behavior.

## Invocation

Use before an application-wide redesign, when UI coverage is uncertain, or
when auditing route reachability, role-specific surfaces, loading/error states,
or cross-screen consistency.

## Required inputs

- `app/lib/core/router/app_router.dart` and `app/lib/widgets/app_shell.dart`.
- Screen/widget source, role helpers, providers, and relevant tests.
- A baseline Git status so existing work is not mistaken for audit output.

## Workflow

1. Enumerate registered routes, redirect/role conditions, shell destinations,
   menus, FAB actions, and secondary entry points.
2. Cross-check route targets against all screen files and test references.
   Separate registered, reachable, role-limited, unlinked, and unverified
   surfaces.
3. For each screen, record route, role, task, actions, data dependencies,
   shared components, and loading/empty/error/retry/denied/success states.
4. Trace meaningful actions to their provider/notifier and report missing,
   contradictory, or misleading feedback. Never infer data access from UI
   visibility alone.
5. Record defects with source evidence, impact, and a stable ID. Distinguish
   verified defects from hypotheses and unreviewed scope.
6. Use the prioritized findings to guide implementation; re-check affected
   screens and update status rather than claiming whole-app completion from a
   sample.

## Required register fields

`Screen/route | Role | Purpose | Main actions | Data dependencies | Existing
defects | Shared components | Implementation status | Verification status`

Include secondary screens and materially different states. Group route aliases
only when they render the same screen and the alias is explicit in the router.

## Output

Return the complete discovered register, ranked evidence-based findings,
unreviewed scope, and any data/credential/device access that prevents
verification.

## Boundaries

This is a read-first audit workflow. Do not change auth, Rules, business logic,
tenant scope, financial calculations, or provider contracts to resolve a
presentation finding. Use `flutter-frontend-modernization` to coordinate fixes.

## Validation

Cross-check route coverage against `app_router.dart`, navigation entry points,
screen source, and tests. Verify fixes with targeted tests and actual rendered
output where available. Explicitly mark screenshot, role, and locale checks that
could not be performed.
