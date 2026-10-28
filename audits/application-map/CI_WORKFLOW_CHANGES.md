# CI Workflow Changes

## Changed automation

### Manual Android artifacts

`.github/workflows/build-apk.yml` now offers `debug`, split release APK, and
signed Play Console AAB modes. The AAB branch invokes `flutter build
appbundle`, verifies the bundle using `jarsigner`, and uploads the AAB as a
separate artifact. APK modes retain split-per-ABI release behavior.

### Firestore Rules workflow

`.github/workflows/firestore-rules-tests.yml` now runs
`node --test tests/maintenance_scripts.test.js` before the emulator suite.
The test asserts that legacy reset, backup, and migration commands exit
non-zero with an explicit `Disabled:` message before initializing Firebase.
This is a preventive guard; it does not validate destructive operations.

## Executed checks

- Maintenance script test: `ℹ tests 10`, `ℹ pass 10`, `ℹ fail 0`.
- `.github/workflows/firestore-rules-tests.yml` and
  `.github/workflows/build-apk.yml`: `YAML parse OK`.
- Rules emulator after the support-context Rules change:
  `180 passing (39s)`.
- Workflow dispatch itself was not executed from GitHub.

## Not covered / blocked

- CI jobs were not dispatched against GitHub.
- Artifact signing and AAB upload workflow branch were not executed.
- The Rules workflow's production deploy step is not run by this test
  workflow; emulator success is local-only.
- No automatic golden-image or real-device RTL visual gate exists.
- No authorized penetration-test job was added; security tests remain local
  emulator and static source checks.

## Security and cost posture

Workflow permissions are read-only for contents in the manual build workflow.
Artifact retention is 14 days. The Rules Emulator uses isolated fixtures and
does not touch production documents. No new paid Firebase service or storage
dependency was introduced.
