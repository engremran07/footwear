---
name: shoeserp-master-audit-verification
description: "Run an evidence-led ShoesERP audit, verify a change, or do both. Use for feature, security-boundary, CRUD, financial-flow, Rules, test, index, workflow, or release-surface reviews."
argument-hint: "Describe the audit or change scope, relevant roles, desired output, and which operations are authorized."
disable-model-invocation: true
---

# ShoesERP Master Audit and Change Verification

Use this workflow for an audit, change verification, or a combined audit and
verification. Do not assume a fixed roster of agents, an unavailable
`runSubagent` tool, or prior audit results. Inspect current source before
stating runtime behavior; historical releases and prior audit reports do not
prove current behavior.

## Choose the Requested Mode

- **Audit:** inspect and report. Do not implement fixes unless the user asks.
- **Change verification:** validate the actual changed files and requested
  scope. Do not expand into an unrelated repository-wide audit.
- **Combined:** audit the requested behavior, then validate the relevant
  existing changes and regression coverage.

Use the scope and output format supplied by the user. If either is unclear and
would materially change the work, ask before proceeding.

## Runtime Context

- The application is a Flutter Android/Web ERP using Firebase Authentication
  and Firestore.
- Roles include `admin`, `manager` (admin-equivalent), `tenant_admin`,
  `super_admin`, and `seller`.
- Platform super-admin business access requires an explicitly selected
  workspace and audited support context.
- Firebase Auth is the sole sign-in mechanism. Current runtime behavior does
  not use app-managed device pairing, device registration, custom session
  slots, or session-renewal gates.
- Shops use the Firestore `customers` collection; application code uses
  `Collections.shops`.
- Financial integrity depends on atomic invoice, transaction, and shop-balance
  writes, plus exact seller-inventory deductions.

Treat these as context to check against live code, not as a substitute for
source inspection.

## Audit and Trace Procedure

1. Read `AGENTS.md`, `CLAUDE.md`, and all applicable
   `.github/instructions/` files.
2. Inspect `git status --short` and preserve pre-existing local changes.
3. Trace the requested behavior through the relevant screens, providers,
   models, Firestore Rules, tests, indexes, and workflows.
4. For authorization or financial paths, check both denied attacks and valid
   CRUD/batch paths. Run Rules tests locally in the Firestore Emulator; never
   use production as a test target.
5. Separate confirmed findings, hypotheses, and unreviewed scope. Cite exact
   file and line evidence, preconditions, impact, and a confidence score.
6. Recommend the smallest safe fix and relevant regression test. Implement
   only when the user requested implementation.

## Change Verification

Verify the exact change and requested scope. Choose the smallest adequate
checks, expanding only when results indicate a shared regression:

- Dart source changes: targeted tests and `flutter analyze lib --no-pub`.
- Dart test changes: targeted Flutter tests and `dart analyze test/`.
- Firestore Rules or authorization changes: run
  `firebase emulators:exec --only firestore "npm test"` from
  `tests/firestore-rules/`.
- Query changes: inspect Rules authorization and
  `firestore.indexes.json`.
- Markdown changes: run the repository Markdown lint command.
- Workflow or configuration changes: validate syntax and inspect triggers,
  secrets, permissions, and deployment effects.

Report exact tool output. Do not claim a test count that the tool did not
emit. A passing local test does not establish production deployment state.

## Safety and Authorization

- Do not deploy, mutate production data, build or release artifacts, commit,
  push, tag, or create a GitHub release unless the user explicitly authorizes
  that operation.
- Treat version bumps, release builds, Hosting/Rules deployment, production
  data changes, APK installation, commits, pushes, and tags as separate
  opt-in actions.
- A push to `main` can trigger `.github/workflows/deploy-web.yml`, which
  deploys Hosting and Firestore Rules/indexes. A version tag or selected
  manual dispatch can trigger `.github/workflows/release.yml`. Do not push
  or dispatch workflows as an implicit way to obtain deployment permission.
- Preserve pre-existing worktree changes. Do not fabricate sessions,
  commits, test evidence, deployment state, or agent findings.
- Do not claim full coverage when context, files, tests, or runtime access
  were partial. State what was not inspected or run.

## Report

For an **audit**, provide:

1. Scope and evidence sources.
2. Severity-ranked findings with location, preconditions, impact, confidence,
   and status.
3. Confirmed-safe paths and tests run, with exact results.
4. Explicit limitations, including production status and unreviewed areas.

For **change verification**, provide:

1. Changed files and requested verification scope.
2. Exact local checks and their outputs.
3. What was not run and why.
4. A clear distinction between source changes, emulator verification,
   production deployment, release artifacts, and Git publication.

For **combined work**, include both sections and avoid duplicating evidence.
