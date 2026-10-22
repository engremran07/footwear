---
description: "Use when: user asks to build, deploy, install, release, commit, push, sync web and APK, or when user-visible Flutter changes must reach both Firebase Hosting and Android APK together."
applyTo: "app/**,firebase.json,firestore.rules,firestore.indexes.json,AGENTS.md,CLAUDE.md,README.md,.github/workflows/**/*.yml"
---

# Release Surface and Production Authorization Instruction

When a user asks to release or deploy both surfaces, treat web and APK as a
single release surface. A normal code change does not authorize a release,
deployment, install, commit, or push.

- If user-visible app behavior, branding, About content, navigation, auth flow, dashboard, inventory, or localization changed, do not assume the previous build artifacts are valid.

- Before building release artifacts, confirm the version in `app/pubspec.yaml` and `app/lib/core/constants/app_brand.dart` matches the intended release. If the shipped artifacts would otherwise reuse an old version, bump the version/build first.

- Never claim web and APK are synced unless all requested surfaces were produced from the same current source tree and version.

Required release order only when the user explicitly asks for release/deploy/sync:

1. Confirm or bump the release version first so `app/pubspec.yaml` and `app/lib/core/constants/app_brand.dart` match the intended artifact version.

2. Validate current source with `flutter analyze lib --no-pub`, `dart analyze test/`, and the relevant test suite.

3. Build web from `app/`.

4. Deploy Firebase Hosting if web changes are part of the request.

5. Build the release APK if Android delivery is part of the request.

6. Deploy Firestore Rules/indexes only when production deployment is explicitly
   authorized. A successful emulator run is local evidence, not deployment.

7. Review the local git delta with `git log --oneline -5`, `git status --short`,
   and `git diff --stat HEAD`.

8. Install the APK to a connected device if requested.

9. Commit and push only when explicitly authorized. Never use GitHub workflow
   side effects as an implicit substitute for deployment permission.

Repository workflow side effects to disclose before Git publication:

- A push to `main` triggers `.github/workflows/deploy-web.yml`, which deploys
  Firebase Hosting and Firestore Rules/indexes.
- A version tag or an authorized manual run may trigger
  `.github/workflows/release.yml`, which builds and deploys release surfaces.
- `.github/workflows/build-apk.yml` is a manual artifact build and does not
  itself deploy.

For local-only tasks, run the relevant local analysis/tests and state that no
production operation was performed. Never require production deployment to
validate a local-only change.

Release verification requirements:

- Confirm `AppBrand.versionDisplay` matches the built release.

- Confirm web cache settings in `firebase.json` do not leave `index.html`, `flutter.js`, `flutter_bootstrap.js`, `main.dart.js`, `flutter_service_worker.js`, `version.json`, or `manifest.json` cached immutably.

- If web appears older than APK, inspect Hosting cache headers and service worker behavior before assuming source mismatch.

- Keep local workspace-only files like `app/.vscode/tasks.json` out of release commits unless the user explicitly asks for them.
