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
