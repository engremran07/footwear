---
name: navigation-routing
description: "Use when: adding or changing Flutter routes, redirects, deep links, nested navigation, role-aware destinations, or back behavior."
---

# ShoesERP Navigation and Routing

## Purpose

Apply the existing go_router architecture without creating a second route
catalog or weakening role and tenant boundaries.

## Invocation

Use before changing `app_router.dart`, route names, shell navigation, redirects,
back behavior, or navigation links in a screen.

## Sources of truth

- Registered routes and redirect logic:
  `app/lib/core/router/app_router.dart`
- Shell navigation and role-filtered entry points:
  `app/lib/widgets/app_shell.dart`
- Role semantics: `app/lib/models/user_model.dart`,
  `app/lib/core/utils/role_utils.dart`, and the applicable runtime Rules.
- Route constraints and UI conventions:
  `.github/instructions/navigation-forms.instructions.md`

Do not maintain a duplicated route list here. Shops are the customer entity;
there is no separate `/customers` route or customer screen.

## Workflow

1. Read the actual route declaration, redirect conditions, shell placement, and
   the destination screen before changing a link or guard.
2. Identify authenticated, tenant, workspace-selection, and role behavior.
   UI visibility is not authorization; do not modify Rules or role contracts
   as a navigation shortcut.
3. Choose `go`, `push`, or `pop` based on the intended history and the router
   hierarchy. Preserve back-to-origin context when entering detail or form
   flows from lists, shops, or quick actions.
4. Keep route parameters and query parameters typed, validated, and consistent
   with the route builder. Do not create an unregistered destination.
5. Verify allowed and redirected destinations, shell selection, deep-link
   parsing, and back behavior for affected roles.

## Output

Report changed paths, affected destinations/roles, preserved return behavior,
and targeted navigation tests. List any route or role combination that was
not verified.

## Boundaries

This skill owns route composition and navigation UX only. Use
`flutter-frontend-modernization` for cross-screen coordination and
`flutter-accessibility-rtl` for focus and directionality. Do not alter
authentication, tenant scope, business logic, or Firestore authorization.

## Validation

Run affected router/widget tests and `flutter analyze lib --no-pub`. Use the
current SDK pinned by the repository; do not add navigation dependencies
without verified need and compatibility evidence.
