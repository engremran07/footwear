# Vibe Debugging Discipline

## Scope

Applies to all Dart files in `app/lib/` when fixing bugs.

## Anti-Patterns to Prevent

| Term | Meaning |
|---|---|
| Whack-a-Mole Debugging | Each "fix" makes a new problem pop up elsewhere |
| Symptom Chasing | AI fixes what it sees (the error message) not what causes it |
| Regression Spiral | 20 commits of increasing complexity for a 5-line fix |
| Vibe Debt | Accumulated complexity from AI-generated code nobody fully understands |
| Confidence Theater | AI says "fixed!" with evidence (tests pass, analyze clean) but the actual bug is untouched |

## Mandatory Rules

1. **Read the full execution path before writing any fix code.**
   Never grep for an error message and fix the first match.

2. **Grep for ALL instances of a bug pattern before fixing any single one.**
   If `.value` is wrong in one export provider, check ALL export providers.

3. **Track fix size.** If your diff exceeds 50 lines for a single bug, stop
   and re-evaluate. You may be adding workarounds instead of fixing the root cause.

4. **Never claim "fixed" without tracing the exact code path the user described.**
   "Tests pass" is not evidence. "I traced the call from screen → provider → Firestore
   and the null was at line X because of Y" is evidence.

5. **The `.value` vs `.future` rule:**
   In async contexts (FutureProvider build, async methods), ALWAYS use
   `await ref.read(provider.future)` for autoDispose StreamProviders.
   `.value` is null during stream loading.

## Grep Gates

```powershell
# Run before any export-related commit:
grep -rn "ref\.read(authUserProvider)\.value" app/lib/providers/ | grep -iv "watch\|build()\|widget"
# Should return zero for export/one-shot provider contexts
```
