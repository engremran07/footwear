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

- AGENTS.md §8 is now the 15-step mandatory signoff sequence. All 15 steps non-bypassable.

- `firebase deploy --only firestore:rules,firestore:indexes` is MANDATORY on every signoff — not just on rules change.

- Web build + hosting deploy is MANDATORY on every signoff.

- GitHub commit audit (git log + git status) is MANDATORY before every commit.

- Before every Android release build, check free RAM and require at least 3.2 GB.
  If below threshold, reclaim memory and recheck before starting Gradle.

- For phone delivery, build split-per-ABI, `adb push` the matching APK to the
  device, then run `adb install --streaming -r` with the host-side APK path.

- Flutter CanvasKit and web fonts require `https://www.gstatic.com` and
  `https://fonts.gstatic.com` in Hosting CSP `connect-src`; verify the deployed
  page in a browser after Hosting changes.

- Session enforcement must wait for access registration, choose the latest
  active unexpired session for the installation, and never sign out a different
  UID after an asynchronous check. Keep login failures visible; show a status
  for attempts pending longer than 12 seconds.

## Canonical Audit Doc

See AGENTS.md §10 for latest audit findings.

## Verification Mirror

- Select-String -Path "app\pubspec.yaml","app\lib\core\constants\app_brand.dart" -Pattern '^version:|appVersion|buildNumber'

- flutter analyze lib --no-pub

- dart analyze test/

- flutter test -r expanded

- flutter build web --release ; firebase deploy --only hosting

- Check free RAM (>=3.2 GB) before starting the APK build.

- flutter build apk --release

- firebase deploy --only firestore:rules,firestore:indexes

- git log --oneline -5 ; git status --short ; git diff --stat HEAD

- git add -A ; git commit ; git push

- adb push matching ABI APK, then adb install --streaming -r with host APK path (if connected)
