# ShoesERP Local Claude Override

Use this workspace-specific file as a local mirror of root guidance.

## Runtime First Rule

If this file and root CLAUDE.md ever differ, follow runtime blocks in CLAUDE.md and AGENTS.md.

## Runtime Document Hierarchy

1. AGENTS.md
2. CLAUDE.md
3. .claude/CLAUDE.md
4. .claude/skills/*/SKILL.md

## Fast Triage Order

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

## Canonical Audit Doc

See SYSTEM_DEEP_DIVE_2026-03-27.md for latest findings and remediation map.

## Verification Mirror

- flutter analyze lib --no-pub
- flutter test -r expanded
- flutter build apk --release
