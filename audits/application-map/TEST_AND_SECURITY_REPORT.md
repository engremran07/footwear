# Test and Security Report

## Environment and baseline

- Repository: `engremran07/footwear`, branch `main`.
- Inspected baseline: `6e5a4337f506d0713fe0463fb6f0ec0cef259b04`.
- Baseline divergence: `0` ahead, `0` behind `origin/main`.
- Worktree was already dirty from the current audit; no changes were committed.
- Flutter version configured by project workflows: `3.41.6`. Android build
  baseline is recorded in
  [apk-build-signing skill](../../.claude/skills/apk-build-signing/SKILL.md).

## Executed evidence

| Command / check | Result | Scope |
| --- | --- | --- |
| Support-context Rules regression before fix | `64 passing, 1 failing` | Reproduced profile-only selected-workspace update without a same-batch audit event. |
| Firestore Rules Emulator after fix | `180 passing (39s)` | Local emulator only; not production deployment. |
| Localized amount formatter test | `00:00 +4: All tests passed!` | Formatter and canonical parser for supported digit scripts/separators. |
| Full Flutter suite after prior source changes | `02:03 +659: All tests passed!` | Run before the later Node-only maintenance-script tests; not rerun after script stubs. |
| `flutter analyze lib --no-pub` | `No issues found! (ran in 33.0s)` | Prior audit tree before the latest script-only edits. |
| `dart analyze test/` | `No issues found!` | Prior audit tree. |
| `node --test tests/maintenance_scripts.test.js` | `ℹ tests 10`, `ℹ pass 10`, `ℹ fail 0` | Final run; stubs assert exit status 1 and explicit disabled message before Firebase initialization. |
| Version inspection | `version: 3.10.10+1121`; `appVersion = '3.10.10'`; `buildNumber = '1121'` | Local source version synchronized. |
| Repository divergence | `0 0` | Baseline HEAD versus origin/main. |
| Release readiness probe | Free memory `2.14 GiB`; `adb devices` showed only `List of devices attached` | APK/AAB build not started due the workstation being below the previously used 3.2 GiB build-safety threshold; no device was connected. |

The latest script-only change does not alter Dart source or Firestore Rules.
The earlier analyzer and Flutter results are accurately reported as earlier
worktree evidence, not as post-script test runs.

## TDD evidence

The maintenance-script regression test was introduced before disabling the
unsafe scripts. It first failed for the executable development flush and the
default-tenant backfill. After those fixes it passed 9 tests. Adding the
single-tenant bulk backfill produced a new failure; after that script was
disabled the final 10-test run passed. No test connected to Firebase.

The support-context Rules issue also had a pre-fix emulator reproduction and
a post-fix full emulator run. The amount formatter correction had a failing
formatter/parser regression before implementation and a focused passing
rerun.

## Security findings and scope

| Finding | Severity/status | Evidence / retest |
| --- | --- | --- |
| Selected super-admin workspace context could be recorded without a linked start event | High; fixed locally, deployment pending | Same-batch profile/event linkage now enforced by Rules; 180 emulator tests pass. |
| Signing password existed in committed history | High; open rotation action | Removed from worktree only; history unchanged; no credential value is reproduced here. |
| Legacy scripts could bulk-reset shop balances or assign unscoped data to a shared/single tenant | High; fixed locally | Three scripts replaced by fail-closed stubs; 10 process-level regression tests pass. |
| `promote_super_admin.js` performs direct privileged role mutation without the platform access audit event | High review required; not run | Source observation only; owner-approved bootstrap exception/process absent. |

Security validation was limited to source review and local emulator tests. It
was not an authorized penetration test. No production account, data, or
service was probed.

## Blocked or not run

- Full file-by-file repository audit: **BLOCKED**; inspected paths are listed
  in `FULL_REPOSITORY_AUDIT.txt`.
- Separate 33-item checklist: **BLOCKED**; the referenced checklist was not
  attached.
- Current-source split APK/AAB build and signature verification: **NOT RUN**.
  At the readiness check only 2.14 GiB of physical memory was free, below the
  previously used 3.2 GiB local build-safety threshold. Recheck after the
  owner closes unneeded applications; no unrelated process was stopped.
- Current-source device installation: **BLOCKED** pending matching production
  Rules authorization because the client schema now requires the same-batch
  support-log link; additionally, no device was connected at the check.
- Production Rules/indexes and Hosting deployment: **NOT AUTHORIZED / NOT
  RUN**.
- Feature-specific reset integration tests: **BLOCKED** because reset
  operations intentionally fail closed and the recovery/partial-failure
  contract is not approved.
- Complete Arabic/Urdu visual inspection across PDF, print, PNG, XLSX, Web,
  and Android: **NOT RUN**.
