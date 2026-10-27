---
name: shoeserp-audit
description: "Run an evidence-led ShoesERP audit of a requested feature, file set, security boundary, CRUD flow, or release surface."
argument-hint: "State the audit scope, roles, and requested output format."
user-invocable: true
disable-model-invocation: true
---

# ShoesERP Evidence-Led Audit

Audit the scope supplied by the user. Do not assume a fixed roster of agents,
an unavailable `runSubagent` tool, or prior audit results.

## Runtime Context

- Flutter Android/Web application using Firebase Authentication and Firestore.
- Roles include `admin`, `manager` (admin-equivalent), `tenant_admin`,
  `super_admin`, `supervisor`, and `seller`.
- Platform super-admin business access is restricted to an explicitly selected
  workspace and audited support context.
- Firebase Auth is the sole sign-in mechanism. The current source does not use
  app-managed device pairing, device registration, custom session slots, or
  session renewal gates.
- Shops use Firestore `customers`; application code uses `Collections.shops`.
- Financial integrity depends on atomic invoice/transaction/shop-balance writes
  and exact seller inventory deductions.
- App permissions use `RoleCapabilities` and `PermissionPolicy`; this central
  policy is not a substitute for Rules enforcement. Reconcile all affected
  screens, providers, and Rules by operation and tenant context.
- Distinguish the platform super-admin settings hub from tenant business
  settings. The hub may expose platform metadata without a selected workspace;
  settings descendants and business reads still require the audited active
  workspace context.
- For tenant-sensitive Riverpod streams, review cache keys as well as Firestore
  query filters. A singleton provider may retain prior-tenant data during an
  auth/profile switch; use a concrete tenant key and test the transition.
- Inspect current source before stating runtime behavior; historical releases
  and prior audit reports do not prove current behavior.

## Audit Procedure

1. Read `AGENTS.md`, `CLAUDE.md`, and any matching `.github/instructions/`.
2. Inspect `git status --short` and preserve pre-existing local changes.
3. Trace the requested behavior through screen, provider, model, Rules, tests,
   indexes, and workflow only as applicable.
4. Check both denied attacks and valid CRUD/batch paths. Rules tests must run
   locally in the Firestore Emulator; never use production as a test target.
5. For tenant-aware paths, verify active profile, active tenant, concrete
   tenant ID, role/target-role eligibility, seller route scope, and super-admin
   selected-workspace reason plus TTL. Test cross-tenant and expired-context
   denial explicitly.
6. For multi-workspace readiness, reconcile capability decisions across
    `UserModel`, `RoleCapabilities`, `PermissionPolicy`, router, screen,
    provider, and Rules. Test operation-specific grants (for example invoice
    creation versus settlement/void) across at least 15 distinct tenant IDs.
    Treat that test as boundary coverage only, not as quota/load evidence.
7. Classify any Rules change as a verified defect or an authorization contract
   change. Presentation and internal state changes are not Rules-change
   triggers.
8. Separate confirmed findings, hypotheses, and unreviewed scope. Cite exact
   file and line evidence with a confidence score.
9. Recommend the smallest safe fix and relevant regression test. Implement only
   if the user requested implementation.

## Safety

- Do not deploy, mutate production data, build/release, commit, or push unless
  the user explicitly authorizes the operation.
- A passing local test does not establish production deployment state.
- Do not claim full coverage when the available scope or context was partial.
- Do not fabricate chat sessions, commits, test evidence, or agent findings.

## Output

Use the format requested by the user. Otherwise provide:

1. Scope and evidence sources.
2. Severity-ranked findings with location, preconditions, impact, confidence,
   and status.
3. Confirmed-safe paths and tests run with exact results.
4. Explicit limitations, including production status and unreviewed areas.
