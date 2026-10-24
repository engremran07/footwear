---
description: "Use for ShoesERP go_router, app-shell navigation, form entry, save feedback, and return behavior."
applyTo: "app/lib/core/router/**/*.dart,app/lib/widgets/app_shell.dart,app/lib/screens/**/*.dart"
---

# go_router Navigation and Form Rules

The registered route and redirect source is
`app/lib/core/router/app_router.dart`; shell navigation is in
`app/lib/widgets/app_shell.dart`. Read both before changing route behavior.
Follow `.github/instructions/frontend-design-system.instructions.md` for shared
visual and accessibility standards.

## Navigation history

Choose `context.go()`, `context.push()`, or `context.pop()` from the intended
route history and entrypoint:

| Intent | Typical choice |
| --- | --- |
| Switch a top-level shell destination | `context.go()` |
| Open a detail/form flow that should return to its caller | `context.push()` |
| Return to the expected parent after success/cancel | `context.pop()` when the route is on the stack |
| Open a screen from a direct link or replace an obsolete location | Follow the actual router and preserve any required return context |

These are not blanket rules. Quick actions, deep links, and nested routes can
have different history. Never remove back-context or change a destination
without checking every caller.

## Save and navigation feedback

Keep the provider write and route transition separate. A navigation exception
must not be reported as a failed Firestore write or show a false error after a
successful save.

```dart
Future<void> _save() async {
  if (!_formKey.currentState!.validate()) return;
  setState(() => _saving = true);
  var saved = false;
  try {
    await ref.read(itemNotifierProvider.notifier).save(item);
    saved = true;
  } catch (error) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        errorSnackBar(tr(AppErrorMapper.key(error), ref)),
      );
    }
  } finally {
    if (mounted) setState(() => _saving = false);
  }

  if (!saved || !mounted) return;
  _isDirty = false;
  ScaffoldMessenger.of(context).showSnackBar(
    successSnackBar(tr('saved_successfully', ref)),
  );
  if (context.canPop()) {
    context.pop();
  }
}
```

Use an existing project helper if available. For a direct-entry form with no
caller route, choose an explicit fallback that matches that entrypoint; do not
silently send every form to the dashboard.

## Edit form loading

- Keep edit fields and submit disabled until the requested record has loaded.
- Show a mapped loading/error/retry state; do not let a failed query look like
  an empty record or a valid set of defaults.
- Do not overwrite user input if the record arrives after interaction begins.
- Preserve route/role validation in the screen and notifier.

## Quick actions and tests

For `AppShell` quick actions, confirm whether the action should push or replace
the current location and test its back behavior. Check that save/cancel,
unsaved-change confirmation, deep links, and role redirects still behave as
intended. Do not use a grep-only `go`/`push` rule as proof of correct navigation.
