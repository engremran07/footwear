# ShoesERP Local Claude Override

Use this workspace-specific file as a local mirror of root guidance.

Last updated: 2026-10-22

## Runtime First Rule

If this file and root CLAUDE.md ever differ, follow runtime blocks in CLAUDE.md and AGENTS.md.

## Runtime Document Hierarchy

1. AGENTS.md

2. CLAUDE.md

3. .claude/CLAUDE.md

4. .claude/skills/*/SKILL.md

## Inline Audit (Mandatory)

Every fix is also an audit pass. Load `.claude/skills/inline-audit/SKILL.md`
whenever fixing any issue. Catch and fix culprits found while reading touched files.

## Build Standard

1. Role + permission alignment

- app/lib/models/user_model.dart

- firestore.rules

1. Collection alignment

- app/lib/core/constants/collections.dart

1. Dashboard resilience

- app/lib/providers/dashboard_provider.dart

1. Index coverage

- firestore.indexes.json

1. Provider-only writes

- no direct Firestore writes in screens/widgets

## Current Guidance

- `StateProvider` is banned in Riverpod 3; use `NotifierProvider` or another
  supported provider type.
- Keep Markdown lint and Flutter analysis clean for the files and checks
  relevant to the requested change.
- Load `.claude/skills/markdown-governance/SKILL.md` before creating or editing
  Markdown governance files.
- Firebase Auth is the only sign-in mechanism. Preserve visible mapped login
  errors, active-profile checks, tenant routing, and super-admin workspace
  auditing; do not restore app-managed device or session gates.
- Workspace admins and sellers retain their scoped CRUD capabilities. Firestore
  Rules enforce active-tenant access, tenant ownership, and linked financial
  writes; use the emulator suite when changing Rules.
- A Rules Emulator result is not production deployment evidence.
- Run only the tests, builds, and operational steps relevant to the task.
  Production deploys, production data changes, release builds, device installs,
  commits, and pushes require explicit user authorization.
- A push to `main` triggers the live Hosting and Firestore deployment workflow;
  release tags/manual release dispatches also have production side effects.
- For an authorized Android release, use the split-per-ABI command and check
  available memory before Gradle. Install only when Android delivery is in
  scope and authorized.
- Verify Hosting CSP and web shell cache headers when the Hosting configuration
  or web surface is part of the authorized change.

## Canonical Audit Doc

See AGENTS.md §10 for latest audit findings.

## Verification Reference

Select commands based on the requested scope. For Firestore Rules changes, run
the emulator suite from `tests/firestore-rules/`:

```powershell
Push-Location tests/firestore-rules
firebase emulators:exec --only firestore "npm test"
Pop-Location
```

For an explicitly authorized release, consult the current version/build,
analysis, test, build, deployment, and install instructions in root
`AGENTS.md`. Quote actual tool output; do not imply a deployment or publication
that was not performed.
