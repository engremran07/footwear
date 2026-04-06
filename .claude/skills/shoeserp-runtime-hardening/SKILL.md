---
name: shoeserp-runtime-hardening
description: "Use when: fixing permission-denied, resource-exhausted, route/inventory write failures, role/rules mismatches, Firestore index gaps, or aligning AGENTS/CLAUDE/README docs to live runtime architecture."
---

# ShoesERP Runtime Hardening Skill

## Purpose

Prevent regressions caused by architecture drift between code, rules, and agent instructions.

## Mandatory Checks

1. Role alignment

- Verify app role helpers in app/lib/models/user_model.dart
- Verify Firestore role helpers in firestore.rules
- Verify Storage role helpers in storage.rules
- Verify create/update user flows normalize role values before writing

1. Collection alignment

- Use only names from app/lib/core/constants/collections.dart

1. Query/index alignment

- For every where(A)+orderBy(B) where A != B, ensure index exists in firestore.indexes.json

1. Dashboard resilience

- Avoid all-or-nothing aggregate pipelines
- Catch FirebaseException/timeout on each aggregate query and degrade gracefully
- Maintain last-good dashboard cache fallback
- Never surface transient permission-denied / unauthenticated errors to users
  during auth/profile stream warm-up; keep startup in loading or cached state

1. Post-edit access verification

- After edits touching auth, router, dashboard, inventory, or Firestore rules,
  verify admin and seller flows for `/`, `/inventory`, and login startup
- Guard admin-only list/stream providers with `authUserProvider` before
  subscribing so seller credentials never trigger denied reads in the UI
- Prefer loading, empty, or cached fallback states over raw permission text
  while role-scoped providers settle

1. Error messaging

- Map Firebase exceptions through AppErrorMapper
- Use styled SnackBar helpers from `snack_helper.dart`:
  - `errorSnackBar(msg)` — light pink bg + dark red text + red accent bar
  - `successSnackBar(msg)` — light green bg + dark green text + green accent bar
  - `warningSnackBar(msg)` — light amber bg + dark orange text + amber accent bar
  - `infoSnackBar(msg)` — light blue bg + dark blue text + blue accent bar
- NEVER use raw `SnackBar(content: Text(...))` or hardcoded `Colors.red`
- For screens using `AppMessage` (requires WidgetRef): same card-style is applied automatically
- Container color constants live in `AppBrand` (errorBg/errorFg/errorAccent etc.)

1. Defense in depth on admin writes

- Admin-only screens must enforce admin checks inside submit/write methods.
- Do not rely only on router guards for sensitive writes.

1. Security-relevant write field validation

- Provider methods writing created_by/route_id/shop_id must reject empty values.
- Validate identifiers before creating/committing Firestore batched writes.

## Standard Failure Playbooks

### permission-denied on writes

- Confirm user doc role and active status
- Confirm app role interpretation
- Confirm rules role interpretation
- If mismatch exists (manager/casing/legacy), align app writes and rules checks

### resource-exhausted on dashboard

- Identify expensive aggregate queries
- Avoid failing all metrics when one query errors
- Use cached fallback values and per-query timeout
- Consider materialized KPI doc for very high scale

### data not visible on lists

- Validate composite index coverage
- Validate collection names against constants
- Validate provider query matches deployed indexes

## MCP/Copilot Modernization Deploy Startup Checks

If "MCP server GitHub Copilot modernization Deploy was unable to start":

- Validate extension/tooling installation state in VS Code
- Reload window and re-open workspace
- Verify no malformed agent/skill YAML frontmatter in workspace docs
- Confirm AGENTS.md and CLAUDE.md are valid markdown and not referencing unsupported tools
- If startup still fails, capture extension logs and isolate by disabling unrelated custom agents

## Required Documentation Updates

When runtime behavior changes, update in same change set:

- AGENTS.md
- CLAUDE.md
- README.md
- app/README.md
- SYSTEM_DEEP_DIVE_2026-03-27.md

## Example Remediation Patterns

1. Admin submit guard

- In screen _save(), read authUserProvider and abort with permission_denied snackbar if not admin.

1. Provider identity guard

- In notifier create/update methods, trim and validate created_by/route_id/shop_id; throw ArgumentError if empty.
