---
name: ui-mobile-forms
description: "Use when: building or fixing mobile form screens, TextEditingController patterns, RTL text inputs, ListTile overflow, readOnly vs enabled fields, cursor positioning."
---

# ShoesERP Mobile Forms Skill

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

Standard `_loadExisting()` guard:
```dart
void _loadExisting() {
  if (_loaded || !isEdit) return;
  final detail = ref.read(someProvider(widget.itemId)).valueOrNull;
  if (detail == null) return;
  _nameC.value = TextEditingValue(text: detail.name, selection: TextSelection.collapsed(offset: detail.name.length));
  _loaded = true;
}
```
Call from `build()` under `ref.watch(someProvider).whenData((_) => _loadExisting())`.

## RTL Text

- Standard TextField handles RTL automatically when `textDirection` is set by locale
- For Urdu/Arabic PDF: use NotoNastaliqUrdu.ttf / NotoSansArabic.ttf (already in assets)
- For persistent RTL: wrap fields in `Directionality(textDirection: TextDirection.rtl, child: ...)`

## Dialog Close — Context Safety

When closing a dialog after an async operation:
```dart
// WRONG — ctx may be stale after setState/rebuild during async
if (ctx.mounted) Navigator.pop(ctx);

// CORRECT — use outer screen context with rootNavigator
if (mounted) Navigator.of(context, rootNavigator: true).pop();
```
The `rootNavigator: true` flag closes the topmost dialog regardless of nested Scaffolds.

## SnackBar Styling — Card-Style Design Pattern

**Problem:** Raw `SnackBar(content: Text(...))` or dark red backgrounds have poor visibility on mobile screens.

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
