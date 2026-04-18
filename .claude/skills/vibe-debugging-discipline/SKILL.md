---
name: vibe-debugging-discipline
description: "Use when: fixing any bug, especially export/PDF/async bugs. This skill prevents the 5 vibe-coding anti-patterns: Whack-a-Mole Debugging, Symptom Chasing, Regression Spiral, Vibe Debt, and Confidence Theater. Load BEFORE writing any fix code."
applyTo: "app/lib/**/*.dart"
---

# Skill: Vibe Debugging Discipline

## Purpose

Prevent the 5 anti-patterns that cause 20-commit debugging spirals
for 5-line fixes. This skill is BLOCKING — load and follow it before
writing any fix code.

---

## The 5 Anti-Patterns

| Anti-Pattern | Definition | Detection Signal |
|---|---|---|
| Whack-a-Mole Debugging | Each "fix" makes a new problem pop up elsewhere | 3+ commits for the same symptom |
| Symptom Chasing | AI fixes what it sees (error message) not what causes it | Fix targets error text, not the code that produced it |
| Regression Spiral | Increasing complexity across many commits for a small fix | Diff grows > 50 lines for a bug that needs < 10 |
| Vibe Debt | Accumulated complexity from AI-generated code nobody understands | Copy-pasted patterns without tracing execution |
| Confidence Theater | "Fixed!" with evidence (tests pass, analyze clean) but bug untouched | Claims without user-verifiable reproduction |

---

## Mandatory Pre-Fix Protocol

### Step 1 — STOP. Read before writing

Before writing ANY fix code, read the FULL execution path:

1. The file containing the symptom (screen/widget) — FULL FILE
2. Every provider the symptomatic code touches — FULL FILE
3. Every model used in the data path — relevant fields
4. The error mapper if the bug surfaces as a user-facing error — FULL
5. Any utility/builder called from the code path — FULL

**NEVER grep for an error message and fix the first match.**

### Step 2 — Trace the exact call stack

Write out the execution path as a numbered list:

```text
1. User taps [button] on [screen]
2. Calls [method] which reads [provider]
3. Provider calls [Firestore query / other provider]
4. Result flows through [transformer / builder]
5. Output rendered by [widget / shared via package]
```

Identify EVERY point where data could be null, empty, or wrong.

### Step 3 — Identify ALL instances of the bug pattern

When you find a bug pattern (e.g., `.value` instead of `.future`),
**grep the entire codebase** for the same pattern before fixing:

```powershell
# Example: find ALL .value reads that should be .future
grep -rn "ref\.read(authUserProvider)\.value" app/lib/
```

Fix ALL instances in one commit, not one at a time across sessions.

### Step 4 — Verify the fix matches the symptom

Before claiming "fixed", ask:

- Does this change affect the EXACT code path the user described?
- If I revert just this change, would the bug return?
- Is there any other code path that could produce the same symptom?

---

## Anti-Pattern Prevention Rules

### Rule 1: No Symptom Chasing

**Wrong:** "The error says 'pdf export failed' → add try/catch around PDF"

**Right:** "The error says 'pdf export failed' → trace WHY the PDF failed →
find the null user → find WHY the user is null → fix the provider that
reads .value instead of .future"

### Rule 2: No Whack-a-Mole

When fixing a bug pattern, use grep to find ALL instances:

```powershell
# Before fixing one .value, find ALL of them
grep -rn "ref\.read(authUserProvider)\.value" app/lib/
# Fix ALL in one commit
```

If the same pattern exists in 5 files but you only fix 3, the remaining
2 will break in the next session. This is the #1 cause of multi-session
debugging spirals.

### Rule 3: No Regression Spiral

Track your fix size. If the diff exceeds 50 lines for a single bug:

1. STOP
2. Re-read the symptom description
3. Check if you're adding complexity instead of removing the root cause
4. Consider: "Am I adding workarounds around the real bug?"

### Rule 4: No Vibe Debt

Never copy-paste a pattern from another file without understanding it.
For every line you write, you must be able to answer:

- What does this line do?
- What happens if I remove it?
- What input would make this line fail?

### Rule 5: No Confidence Theater

Every fix claim requires reproduction evidence:

- **Invalid:** "Tests pass and analyze is clean" (tests might not cover the bug)
- **Valid:** "I traced the exact code path the user described. The bug was
  at line X where `.value` returns null during stream loading. Changed to
  `.future` which awaits the first emission. The fix is in the exact code
  path: screen → provider → Firestore query."

---

## The `.value` vs `.future` Canonical Rule

This is the #1 recurring bug in this codebase. Memorize it:

| Context | Correct Pattern | Why |
|---|---|---|
| `ref.watch(streamProvider).value` in `build()` | `.value` is OK | Widget rebuilds on new emission |
| `ref.read(streamProvider).value` in async method | **USE `.future`** | `.value` is null during loading |
| `ref.read(streamProvider).value` inside `FutureProvider` build | **USE `.future`** | Provider may start before stream emits |

```dart
// ❌ WRONG — null if stream hasn't emitted yet
final user = ref.read(authUserProvider).value;

// ✅ CORRECT — awaits first emission
final user = await ref.read(authUserProvider.future);
```

**Grep gate (run before every export-related commit):**

```powershell
# Must return zero results in export providers and export screen methods
grep -rn "ref\.read(authUserProvider)\.value" app/lib/providers/ app/lib/screens/ | grep -i "export\|pdf\|ledger\|report"
```

---

## Post-Fix Checklist

1. All instances of the bug pattern fixed (not just the reported one)
2. `debugPrint` added to catch blocks for future diagnosis
3. `dart analyze` clean
4. Tests pass
5. Exact reproduction path verified (not just "tests pass")

---

## ShoesERP-Specific Patterns

| Bug Pattern | Where to Grep | What to Fix |
|---|---|---|
| `.value` on autoDispose StreamProvider | `grep -rn "authUserProvider).value" app/lib/` | Change to `await .future` in async contexts |
| Missing `tableDirection` in PDF tables | `grep -rn "TableHelper.fromTextArray" app/lib/` | Ensure both `headerDirection` AND `tableDirection` are set |
| Missing `pdfBytesBuilder` in ExportSheet | `grep -rn "ExportSheet.show" app/lib/` | Ledger/report exports MUST pass custom builder |
| Missing `companyName` in PDF builders | `grep -rn "buildPdf" app/lib/screens/` | Every builder call must pass `settings.companyName` |
| Missing provider in invalidation list | `grep -rn "invalidateRoleScopedProviders" app/lib/` | Every admin-data provider must be listed |
