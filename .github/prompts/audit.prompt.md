---
name: ShoesERP Audit
description: "Run an evidence-led ShoesERP audit of a requested feature, file set, security boundary, CRUD flow, or release surface."
argument-hint: "State the audit scope, roles, and requested output format."
agent: agent
---

# ShoesERP Evidence-Led Audit

Audit the scope supplied by the user. Do not assume a fixed roster of agents,
an unavailable `runSubagent` tool, or prior audit results.

## Runtime Context

- Flutter Android/Web application using Firebase Authentication and Firestore.
- Roles include `admin`, `manager` (admin-equivalent), `tenant_admin`,
  `super_admin`, and `seller`.
- Platform super-admin business access is restricted to an explicitly selected
  workspace and audited support context.
- Firebase Auth is the sole sign-in mechanism. The current source does not use
  app-managed device pairing, device registration, custom session slots, or
  session renewal gates.
- Shops use Firestore `customers`; application code uses `Collections.shops`.
- Financial integrity depends on atomic invoice/transaction/shop-balance writes
  and exact seller inventory deductions.
- Inspect current source before stating runtime behavior; historical releases
  and prior audit reports do not prove current behavior.

## Audit Procedure

1. Read `AGENTS.md`, `CLAUDE.md`, and any matching `.github/instructions/`.
2. Inspect `git status --short` and preserve pre-existing local changes.
3. Trace the requested behavior through screen, provider, model, Rules, tests,
   indexes, and workflow only as applicable.
4. Check both denied attacks and valid CRUD/batch paths. Rules tests must run
   locally in the Firestore Emulator; never use production as a test target.
5. Separate confirmed findings, hypotheses, and unreviewed scope. Cite exact
   file and line evidence with a confidence score.
6. Recommend the smallest safe fix and relevant regression test. Implement only
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
