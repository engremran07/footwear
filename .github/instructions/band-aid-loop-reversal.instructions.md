---
description: "Use when: multiple temporary fixes were applied, root cause is uncertain, and QA/user confirms the exact fix that actually resolved the bug."
applyTo: "app/lib/**/*.dart,firestore.rules,firestore.indexes.json,.github/workflows/**/*.yml"
---

# Band-Aid Loop Reversal Instruction

Enforce a closed-loop cleanup after root-cause confirmation.

## Trigger Conditions

Run this protocol when all are true:

1. Two or more candidate fixes were applied for one symptom.

1. It is ambiguous which change solved the issue.

1. QA/user confirms the issue is fixed and identifies the last action after which it stopped reproducing.

## Required Workflow

1. Create an Evidence Table (in PR description or task notes):

- Symptom signature

- Candidate change

- Why it was added

- Expected effect

- Observed effect

- Keep/rollback decision

1. Classify every candidate change:

- Root-cause fix: keep

- Safety guard required by policy/rules: keep

- Temporary mitigation (band-aid loop): rollback

1. Roll back non-culprit mitigations first:

- Prefer minimal targeted rollback (single method/block), not broad file reverts.

- Never remove mandatory security, role, or data-integrity guards.

1. Re-verify after each rollback:

- `flutter analyze lib --no-pub`

- Targeted tests for affected path

- Reproduction scenario from QA/user

1. Stop rollback when:

- Symptom remains fixed

- No regression is introduced

- Only root-cause + mandatory guards remain

1. For recurring PDF/font/layout symptoms, preserve a deterministic input
fixture and record the generated PDF, shaping flag, and target renderer.
Compare actual rendered output when available; track font/shaping, text
direction, header composition, and logo source as separate candidate fixes.
Embedded-font metadata or text-input tests alone do not prove correct glyph
rendering or column placement. Do not add another font, dependency, fallback
layout, or retry until the reported failure is reproduced and assigned to
its actual owner.

For `pdf` 3.12.0 layouts, set physical row order through
`pw.Directionality`; `pw.Row` does not expose a `textDirection` parameter.
Treat a standalone shaping demo as feasibility evidence only. A renderer
replacement is not a culprit fix until it preserves logo images, selectable
text, page flow, and every production report on both Web and Android.

## Non-Negotiable Rules

1. Do not keep a band-aid if it does not provide mandatory defense-in-depth.

1. Do not claim root-cause closure without a reproducible before/after scenario.

1. Do not ship ambiguity: final PR must state exactly which change fixed the bug.

## Required Final Summary

Every ambiguity cleanup must end with:

1. Confirmed real culprit fix

1. Temporary fixes rolled back

1. Mandatory guards retained and why

1. Tests/reproduction evidence proving closure

1. For rendering bugs, generated page count/format, font-resource evidence,
   visual evidence when available, and any unverified viewer/platform scope
