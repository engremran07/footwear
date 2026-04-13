# ShoesERP Local Claude Override

Use this workspace-specific file as a local mirror of root guidance.

Last updated: 2026-04-13

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

## Governance Notes (v3.7.2+50)

- `StateProvider` is BANNED. Use `NotifierProvider<T, S>` only. Grep must return zero.
- All 4 CI workflows now standardised on Flutter 3.41.6.
- Anti-Bypass Enforcement Matrix lives in CLAUDE.md — require quoted tool output for every claim.
- Breakage Chain 6 (StateProvider lifecycle) added to CLAUDE.md.
- Zero Problems tab tolerance: markdown AND Flutter analyze must always be fully clean.
- Markdown governance: load `.claude/skills/markdown-governance/SKILL.md` before creating any `.md` file.
- CI Gates 15-17 active: StateProvider banned; Firestore files valid; no temp artifacts.
- `.gitignore` covers all temp artifacts: logs, debug files, installer flags, dev scripts.
- AGENTS.md §8 is now the 14-step mandatory signoff sequence. All 14 steps non-bypassable.
- `firebase deploy --only firestore:rules,firestore:indexes` is MANDATORY on every signoff — not just on rules change.
- Web build + hosting deploy is MANDATORY on every signoff.
- GitHub commit audit (git log + git status) is MANDATORY before every commit.

## Canonical Audit Doc

See AGENTS.md §10 for latest audit findings.

## Verification Mirror

- flutter analyze lib --no-pub
- dart analyze test/
- flutter test -r expanded
- firebase deploy --only firestore:rules,firestore:indexes
- flutter build web --release ; firebase deploy --only hosting
- flutter build apk --release
- git log --oneline -5 ; git status --short
- git add -A ; git commit ; git push
- adb install -r (if device connected)
