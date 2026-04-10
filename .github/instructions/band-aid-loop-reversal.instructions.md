---
description: "Use when: multiple temporary fixes were applied, root cause is uncertain, and QA/user confirms the exact fix that actually resolved the bug."
applyTo: "app/lib/**/*.dart,firestore.rules,firestore.indexes.json,.github/workflows/**/*.yml"
---

# Band-Aid Loop Reversal Instruction

Enforce a closed-loop cleanup after root-cause confirmation.

## Trigger Conditions

Run this protocol when all are true:

1. Two or more candidate fixes were applied for one symptom.
2. It is ambiguous which change solved the issue.
3. QA/user confirms the issue is fixed and identifies the last action after which it stopped reproducing.

## Required Workflow

1. Create an Evidence Table (in PR description or task notes):
- Symptom signature
- Candidate change
- Why it was added
- Expected effect
- Observed effect
- Keep/rollback decision

2. Classify every candidate change:
- Root-cause fix: keep
- Safety guard required by policy/rules: keep
- Temporary mitigation (band-aid loop): rollback

3. Roll back non-culprit mitigations first:
- Prefer minimal targeted rollback (single method/block), not broad file reverts.
- Never remove mandatory security, role, or data-integrity guards.

4. Re-verify after each rollback:
- `flutter analyze lib --no-pub`
- Targeted tests for affected path
- Reproduction scenario from QA/user

5. Stop rollback when:
- Symptom remains fixed
- No regression is introduced
- Only root-cause + mandatory guards remain

## Non-Negotiable Rules

1. Do not keep a band-aid if it does not provide mandatory defense-in-depth.
2. Do not claim root-cause closure without a reproducible before/after scenario.
3. Do not ship ambiguity: final PR must state exactly which change fixed the bug.

## Required Final Summary

Every ambiguity cleanup must end with:

1. Confirmed real culprit fix
2. Temporary fixes rolled back
3. Mandatory guards retained and why
4. Tests/reproduction evidence proving closure
