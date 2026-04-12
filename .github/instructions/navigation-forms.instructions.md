---
applyTo: "app/lib/**/*.dart"
---

# go_router Navigation Rules: Shell vs Form Screens

## Rule: `context.push()` for all form/detail destinations

Form and detail screens (create, edit) MUST be opened with `context.push()`.
**Never** use `context.go()` to navigate to a form screen.

### Why

`context.go()` **replaces** the entire GoRouter navigation stack.
After `context.go('/routes/new')`, `GoRouter.canPop()` returns `false`.
In go_router 14+, calling `context.pop()` with an empty stack throws
`GoException: "pop called with no routes on stack"`.
This exception is NOT a `FirebaseException`, so `AppErrorMapper.key()`
returns `err_unknown` → l10n: **"Something went wrong. Please try again."**
The user sees an error SnackBar even though the Firestore write succeeded.

### Correct pattern

```dart
// ✅ CORRECT — form screens (create / edit)
context.push('/routes/new');
context.push('/routes/$id/edit');
context.push('/shops/new');
context.push('/shops/$id/edit');
context.push('/products/new');
context.push('/products/$id/edit');
context.push('/products/$id/variants/new');
context.push('/products/$id/variants/$vid/edit');

// ✅ CORRECT — shell-level tab/section navigation
context.go('/');
context.go('/routes');
context.go('/shops');
context.go('/products');
context.go('/inventory');
context.go('/profile');
```

### Rule of thumb

| Destination type | Method |
|---|---|
| Top-level shell tab (bottom nav / drawer) | `context.go()` |
| Form screen (create / edit) | `context.push()` |
| Detail screen reached from a list | `context.push()` |

## Rule: `context.pop()` OUTSIDE the try-catch in form `_save()` methods

All form `_save()` methods must use the `saved` flag pattern so that a
navigation exception cannot produce a false error SnackBar:

```dart
Future<void> _save() async {
  // ...validate...
  setState(() => _saving = true);
  bool saved = false;
  try {
    await providerNotifier.create(data); // or update
    saved = true;
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(errorSnackBar(tr(AppErrorMapper.key(e), ref)));
    }
  } finally {
    if (mounted) setState(() => _saving = false);
  }
  // SUCCESS PATH — outside try-catch
  // A navigation exception here will NOT show "Something went wrong".
  if (saved && mounted) {
    HapticFeedback.mediumImpact();
    _isDirty = false;
    ScaffoldMessenger.of(context)
        .showSnackBar(successSnackBar(tr('saved_successfully', ref)));
    context.pop();
  }
}
```

**Anti-pattern** — DO NOT put `context.pop()` inside `try`:

```dart
// ❌ WRONG — pop inside try-catch
try {
  await provider.save();
  if (mounted) {
    showSnackBar(success);
    context.pop(); // GoException caught here → shows error SnackBar
  }
} catch (e) {
  showSnackBar(error); // fires even after successful save!
}
```

## Callers: app_shell.dart FAB

The FAB bottom sheet in `app_shell.dart` uses `action.route` from the
`_fabActions()` map. **This action tap MUST use `context.push()`**, not
`context.go()`, because all FAB routes are form screens:

```dart
onTap: () {
  Navigator.pop(ctx);
  context.push(action.route); // ← push, not go
},
```

## Enforcement

Add to the inline audit pass whenever touching any screen that opens a form:

```bash
# No context.go() for form routes
grep -rn "context\.go.*/(new|edit)" app/lib/ | grep -v "// ok"
```

Expected output: zero matches.
