---
name: band-aid-loop-reversal
description: "Use when: several quick fixes were applied for one bug, root cause is ambiguous, and you must identify the real fix, roll back non-culprit mitigations, and keep only root-cause + mandatory guards."
---

# Skill: Band-Aid Loop Reversal

## Purpose

Provide a deterministic, closed-loop workflow for self-healing and self-learning:

1. isolate real culprit fix
2. remove temporary non-culprit fixes
3. retain only durable root-cause logic and required safeguards

## Inputs Required

1. Symptom and reproduction steps
2. Ordered list of applied fixes
3. QA/user confirmation point: "after change X, bug stopped"

## Step 1: Build a Fix Ledger

Create a table for each candidate change:

- id
- file/symbol
- hypothesis
- risk if kept
- risk if removed
- classification: `root-cause` | `mandatory-guard` | `temporary-mitigation`

## Step 2: Identify Keep Set

Keep only:

1. root-cause fix proven by reproduction
2. mandatory guards required by security/integrity/runtime contract

Everything else is rollback candidate.

## Step 3: Rollback Strategy

1. Roll back one temporary mitigation at a time.
2. Re-run scenario after each rollback.
3. If bug returns, re-apply and reclassify as root-cause or mandatory-guard.
4. If bug stays fixed, keep rollback.

## Step 4: Verification Gates

Run all:

1. `flutter analyze lib --no-pub`
2. Relevant unit/widget/provider tests
3. Exact reproduction path used by QA/user
4. Hygiene gates from AGENTS/CLAUDE

## Step 5: Closure Report

Must include:

1. Confirmed culprit fix
2. Rolled-back band-aid changes
3. Kept guards and rationale
4. Evidence that issue remains fixed

## Guardrails

1. Never remove role/rules/data-integrity controls.
2. Never delete tests to force green pipeline.
3. Never keep dead workaround code without explicit justification.

## Output Template

```text
Culprit Confirmed: <change>
Band-Aids Removed: <list>
Guards Retained: <list + reason>
Verification: analyze/tests/repro all pass
Residual Risk: <if any>
```
