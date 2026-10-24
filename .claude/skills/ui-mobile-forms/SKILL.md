---
name: ui-mobile-forms
description: "Use when: building or fixing mobile form screens, TextEditingController patterns, RTL text inputs, ListTile overflow, readOnly vs enabled fields, cursor positioning."
---

# ShoesERP Mobile Forms Skill

## Purpose and invocation

Use this skill when creating, reviewing, or fixing a ShoesERP form, text input,
controller lifecycle, validation flow, dialog, or mobile overflow issue.

## Required inputs and workflow

Read the complete affected screen, its providers, current localization/font
setup, and relevant widget tests. Trace create/edit loading and save behavior
before changing the form. Reuse existing validators, formatters, error
mapping, and shared widgets.

## Output

Record the affected form states, lifecycle and validation changes, tests, and
any viewport/locale behavior that remains unverified.

## Dependencies and boundaries

Follow `.github/instructions/frontend-design-system.instructions.md` and the
runtime/provider rules in `AGENTS.md`. This skill owns form presentation and
input lifecycle only; authorization, business validation, and Firestore writes
remain in their existing layers.

## Validation

Run the targeted form/widget tests and `flutter analyze lib --no-pub`. Include
the supported RTL locale and text-scale cases when the change affects them.

## TextEditingController — Cursor Positioning

**Problem:** `_controller.text = value` in `_loadExisting()` resets the cursor to position 0 on first user interaction.

**Fix:** Use `TextEditingValue` to place cursor at text end:

```dart

_controller.value = TextEditingValue(
  text: value,
  selection: TextSelection.collapsed(offset: value.length),
);

```

Apply to all `_loadExisting()` methods in form screens.

## readOnly vs enabled

- `readOnly: true` → field is visible but not editable; cursor still moves, tap selects all → confusing UX

- `enabled: false` → field is greyed out and unresponsive → clear affordance for non-editable state

- **Use `enabled: false` when a field should not be edited** (e.g., admin-only email field shown to seller)

## ListTile Subtitle Overflow

Avoid long single-line subtitles. Use `Column` with:

```dart

subtitle: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  mainAxisSize: MainAxisSize.min,
  children: [
    Text(primaryLine, maxLines: 1, overflow: TextOverflow.ellipsis),
    Row(children: [chip, Flexible(child: Text(secondaryLine, maxLines: 1, overflow: TextOverflow.ellipsis))]),
  ],
),

```

## Form Load Pattern

Edit forms must not allow partial defaults to be saved before the existing
record has loaded. Do not treat loading or provider failure as an empty record.
Keep the editable form gated until data arrives, and show a retryable mapped
error if it fails.

Watch the edit provider's `AsyncValue` and handle loading, error/retry, and data
states explicitly using the existing shared loading and error widgets.
Initialize controllers once after data arrives. If fields can be edited before
the first provider value, guard against overwriting user input. Disable submit
until a required record is loaded and validate that the edit ID still matches
the current route.

## RTL Text

- Use the app locale's `Directionality` and test Arabic and Urdu separately.
  Text fields, cursors, selections, validation messages, and mixed Latin
  identifiers must remain usable.
- UI Urdu uses the bundled Noto Nastaliq family and Arabic uses Noto Sans
  Arabic. This is separate from report rendering: PDFs embed Noto Sans Arabic
  for Arabic and Urdu and require `--dart-define=use_arabic=true`; the PDF
  renderer does not provide full Nastaliq shaping. Follow
  `.claude/skills/analytics-reporting/SKILL.md` for PDF, image, print, share,
  and XLSX behavior.
- Use `EdgeInsetsDirectional`, `AlignmentDirectional`, and directional icons
  when the meaning is start/end rather than physical left/right. Do not wrap
  the whole form in an additional `Directionality` unless the screen's actual
  locale behavior requires it.

## Dialog Close — Context Safety

After an async operation, check that the owning context is still mounted and
close the route that opened the dialog. Do not always force the root navigator;
nested navigators and sheets can have a different owner.

```dart

if (!dialogContext.mounted) return;
Navigator.of(dialogContext).pop();

```

Use the exact dialog or sheet context when it remains mounted. Keep provider
write errors mapped and visible; do not catch navigation failures as if the
write itself failed.

## SnackBar Styling — Card-Style Design Pattern

**Problem:** `SnackBar(content: Text(...))` or dark red backgrounds have poor visibility on mobile screens.

**Solution:** Material 3 container-color card-style SnackBars with high-contrast scheme:

| Type | Background | Text/Icon | Accent Bar |

|---------|-----------|-----------|------------|

| Error | `#FDECEC` | `#C62828` | `#E53935` |

| Success | `#E8F5E9` | `#2E7D32` | `#43A047` |

| Warning | `#FFF8E1` | `#E65100` | `#FFA000` |

| Info | `#E3F2FD` | `#1565C0` | `#1E88E5` |

**Usage — standalone (no WidgetRef needed):**

```dart

import '../core/utils/snack_helper.dart';

// Build SnackBar for ScaffoldMessenger
ScaffoldMessenger.of(context).showSnackBar(errorSnackBar('Something failed'));
ScaffoldMessenger.of(context).showSnackBar(successSnackBar('Saved!'));
ScaffoldMessenger.of(context).showSnackBar(warningSnackBar('Check inputs'));

// Or use show* shortcuts (require BuildContext)
SnackHelper.showError(context, 'Error message');
SnackHelper.showSuccess(context, 'Success message');

```

**Usage — with AppMessage (requires WidgetRef for i18n):**

```dart

AppMessage.error(context, ref, 'err_permission_denied');
AppMessage.success(context, ref, 'success_saved');

```

**Rules:**

- NEVER use raw `SnackBar(content: Text(...))` — always use `errorSnackBar()` / `successSnackBar()` / `warningSnackBar()` / `infoSnackBar()`

- NEVER use `Colors.red` or hardcoded color in SnackBars

- Container color constants are in `AppBrand` (errorBg, errorFg, errorAccent, etc.)

- `SnackBarThemeData` in `AppTheme` provides baseline floating behavior for any unconverted SnackBars
