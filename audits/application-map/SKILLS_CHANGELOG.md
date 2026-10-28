# Skills Changelog

## Review date: 2026-10-28

No third-party skills or executable skill bundles were downloaded or installed
for this audit. Existing project skills were reviewed and updated in place.

| Skill | Change | Source / provenance | Validation |
| --- | --- | --- | --- |
| `.claude/skills/multi-tenant-saas/SKILL.md` | Added current same-batch support-access audit linkage and tenant-isolation test expectations. | Existing repository skill; project-specific policy and `firestore.rules` contract. | Documentation review; linked Rules suite result is `180 passing (39s)`. |
| `.claude/skills/testing-strategy/SKILL.md` | Added localized amount formatter-to-parser requirements and same-batch platform support-context test contract. | Existing repository skill; app formatter/parser and Rules tests. | Focused amount suite `00:00 +4`; Rules Emulator `180 passing`. |
| `.claude/skills/github-workflows/SKILL.md` | Corrected the hygiene gate count to 18 and documented the manual AAB workflow/signature-verification path. | Existing repository skill and `.github/workflows/build-apk.yml`. | Workflow YAML was previously parsed; current Rules workflow receives the maintenance-script test step. |
| `.claude/skills/apk-build-signing/SKILL.md` | Reviewed for the requested Gradle/build work; no change made because it already documents the current wrapper/plugin baseline, signing safeguards, memory-pressure handling, APK/AAB commands, signature checks, and device delivery steps. | Existing repository skill and checked-in Gradle configuration. | Current workstation probe: Flutter 3.41.6, JDK 21, signing-config file present; no build attempted with 2.14 GiB free. |
| `.claude/skills/performance-optimization/SKILL.md` | Added a requirement to verify that a source map belongs to the exact JavaScript bundle before attributing minified browser frames to Dart source. | The local diagnostic source-map build did not match the deployed JavaScript bundle. | The dashboard regression and source-map attribution limitation are recorded in the session log and performance audit reports. |
| `tests/maintenance_scripts.test.js` and Rules workflow guidance | Added a local Node test requirement for legacy dangerous scripts that must fail before Firebase initialization. | New project-local regression protection, not an external skill. | `node --test tests/maintenance_scripts.test.js`: 10 tests passed. |

## External technical guidance consulted

- Flutter official internationalization documentation:
  [Flutter internationalization](https://docs.flutter.dev/ui/internationalization)
- Firebase official Firestore Rules condition and atomic-batch guidance:
  [Firestore Rules conditions](https://firebase.google.com/docs/firestore/security/rules-conditions)
- Pinned PDF package documentation:
  [pdf package](https://pub.dev/packages/pdf)

These pages were reviewed for technical context only. No external skill
license or agent instructions were adopted. No third-party scripts were run.
