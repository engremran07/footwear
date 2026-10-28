# Regression Ledger — Audit Addendum

This ledger records evidence from the bounded 2026-10-27 audit. Historical
entries remain in [REGRESSION_REGISTRY.md](../../REGRESSION_REGISTRY.md).

| ID | Symptom / defect | Root cause evidence | Fix / rollback decision | Test evidence | Status |
| --- | --- | --- | --- | --- | --- |
| RR-027 | Super-admin selected a workspace without a same-batch start audit event | Pre-fix Rules emulator allowed a profile-only selection; the event did not reciprocally prove profile linkage. | Provider stores the exact log ID; Rules enforce both sides of the same batch. No unrelated mitigation removed. | Pre-fix `64 passing, 1 failing`; post-fix Rules Emulator `180 passing (39s)`. | Fixed locally; production deployment pending. |
| RR-028 | Arabic-Indic/Eastern-Arabic monetary digits disappeared in form input | Shared formatter's ASCII-oriented allow-list removed characters supported by the canonical parser. | Expand allow-list to supported digits/separators; preserve user-entered text without transliteration. | Focused pre-fix failure; post-fix `00:00 +4: All tests passed!`. | Fixed locally. |
| RR-029 | Signing secret value was present in committed history | Historical `AGENTS.md` content contained the value. | Redact working tree only; do not rewrite history. Owner must rotate if active. | Worktree diff review; no credential value copied to the report. | Open owner action. |
| RR-030 | Dev flush could delete ledger documents and directly reset shop balances in separate batches | `flush_dev_data.js` source performs deletes then direct balance writes; process is not atomic across batches. | Replaced the active script with a fail-closed stub. No other workaround retained. | First script test run failed for this path; final Node test suite passes. | Fixed locally. |
| RR-031 | Legacy backfill could assign missing tenant IDs to a shared default | Source used `DEFAULT_TENANT_ID = 'default'` and had no record ownership mapping. | Disabled `tool/backfill_missing_tenant_id.js`; no service account loaded and no migration run. | First script test run failed; final Node suite passes. | Fixed locally. |
| RR-032 | Bulk backfill could place all unscoped records under one selected tenant | Source accepted one tenant target and updated every missing-tenant record in selected collections without per-record ownership proof. | Disabled `tool/backfill_tenant_id.js`; require a future record-mapped, reviewed migration. | Added assertion caused a red 9/10 run; final Node suite passes 10/10. | Fixed locally. |
| RR-033 | Privileged super-admin promotion utility may bypass the platform access audit event | `promote_super_admin.js` directly patches the profile role through Firestore REST; no paired audit event appears in the utility path. | No rollback or edit: bootstrap intent and approved provisioning path are unknown. Do not run pending owner review. | Source review only; not executed. | Review required. |

## Band-Aid loop decision

For RR-027 and RR-028, the failing regressions isolated one root cause each;
the fixes did not add layered workarounds. The maintenance-script cases also
had a direct source-level destructive/tenant-assignment path. The correction
was to disable those legacy entry points, not to add additional confirmations
around operations that remain architecturally unsafe. No Firebase data was
changed.

## Carry-forward

Feature-specific reset functionality, configurable role permissions,
production Rules deployment, secret rotation, the undocumented privileged
promotion tool, complete Urdu/Arabic visual proof, and the unavailable
33-item checklist remain open or blocked.
