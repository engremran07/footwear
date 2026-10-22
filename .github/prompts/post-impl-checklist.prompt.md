---
name: ShoesERP Change Verification
description: "Select and run verification appropriate to the changed ShoesERP files and the operations explicitly requested by the user."
argument-hint: "Describe the change and whether local validation, release, deployment, or Git operations are authorized."
agent: agent
---

# ShoesERP Change Verification

Verify the actual change and its requested scope. There is no fixed minimum
suite count and no automatic release/deployment checklist for every edit.

## 1. Inspect Scope

- Read `AGENTS.md`, `CLAUDE.md`, relevant `.github/instructions/`, and the
  changed files.
- Inspect `git status --short`; preserve changes that predate this task.
- Identify changed runtime behavior, data writes, Rules/indexes, and user-facing
  release surfaces.

## 2. Run Relevant Local Checks

Choose the smallest adequate checks, then expand if they reveal a shared
regression:

- Dart source changes: run targeted tests and `flutter analyze lib --no-pub`.
- Dart test changes: run targeted Flutter tests and `dart analyze test/`.
- Firestore Rules or authorization changes: run
  `firebase emulators:exec --only firestore "npm test"` from
  `tests/firestore-rules/`.
- Query changes: inspect Rules authorization and `firestore.indexes.json`.
- Markdown changes: run project Markdown lint.
- Workflow/configuration changes: validate syntax and inspect actual triggers,
  secrets, permissions, and deployment effects.

Report exact output. Do not state a test count that the tool did not emit.

## 3. Release and Production Operations

Treat the following as separate, opt-in actions. Perform them only when the
user explicitly requests or authorizes them:

- Version/changelog bump and release artifact builds.
- Firebase Hosting, Firestore Rules/indexes, or any other production deploy.
- Production data migration or cleanup.
- APK installation, commit, push, tag, or GitHub release creation.

The current repository workflows have side effects: a push to `main` triggers
`.github/workflows/deploy-web.yml`, which deploys Hosting and Firestore
Rules/indexes; a version tag or selected manual run can trigger
`.github/workflows/release.yml`, which builds and deploys release surfaces.
Do not push or dispatch these workflows unless the user has authorized those
effects.

## 4. Final Report

Summarize changed files, exact local checks and results, and what was not run.
Clearly distinguish source changes, emulator verification, deployed production
state, release artifacts, and Git publication. Never describe local-only work
as deployed or release-complete.
