---
description: "Use when: user asks to build, deploy, install, release, commit, push, sync web and APK, or when user-visible Flutter changes must reach both Firebase Hosting and Android APK together."
applyTo: "app/**,firebase.json,firestore.rules,firestore.indexes.json,AGENTS.md,CLAUDE.md,README.md"
---

# Release Surface Sync Instruction

Treat web and APK as a single release surface.

- If user-visible app behavior, branding, About content, navigation, auth flow, dashboard, inventory, or localization changed, do not assume the previous build artifacts are valid.
- Before building release artifacts, confirm the version in `app/pubspec.yaml` and `app/lib/core/constants/app_brand.dart` matches the intended release. If the shipped artifacts would otherwise reuse an old version, bump the version/build first.
- Never claim web and APK are synced unless all requested surfaces were produced from the same current source tree and version.

Required release order when user asks for release/deploy/sync:

1. Validate current source with `flutter analyze lib --no-pub` and relevant tests.
2. Verify current release diff with `git status --short`.
3. Build web from `app/`.
4. Deploy Firebase Hosting if web changes are part of the request.
5. Deploy Firestore rules/indexes if rules or query behavior changed.
6. Build release APK if Android delivery is part of the request.
7. Install APK to connected device if requested.
8. Commit and push only after build/deploy/install steps succeed.

Release verification requirements:

- Confirm `AppBrand.versionDisplay` matches the built release.
- Confirm web cache settings in `firebase.json` do not leave `index.html`, `flutter.js`, `flutter_bootstrap.js`, `main.dart.js`, `flutter_service_worker.js`, `version.json`, or `manifest.json` cached immutably.
- If web appears older than APK, inspect Hosting cache headers and service worker behavior before assuming source mismatch.
- Keep local workspace-only files like `app/.vscode/tasks.json` out of release commits unless the user explicitly asks for them.
