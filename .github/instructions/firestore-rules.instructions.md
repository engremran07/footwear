---
description: "Use when editing Firestore Security Rules or their emulator tests. Covers ShoesERP tenant roles, financial batches, expression limits, and local-only validation."
applyTo: ["firestore.rules", "tests/firestore-rules/**/*.js"]
---

# Firestore Rules Change Instructions

- Read the relevant Rules blocks, matching emulator tests, and provider write
  path before changing authorization.
- Every new or modified business-data path must enforce active profile, role,
  concrete tenant ownership, and active tenant status as appropriate.
- Preserve selected-workspace super-admin controls and the narrowly scoped
  inactive-workspace restoration path.
- Support-context starts, exits, and switches must link the profile transition
  and exact append-only event in one atomic batch. Starts bind
  `active_workspace_access_log_id` to the new event. Exits bind
  `last_workspace_access_end_log_id` to the end event and validate the prior
  actor, workspace, reason, and start-event ID when present. A switch ends the
  prior context and starts the next context in the same batch.
- Firebase Auth is the sign-in mechanism. Do not reintroduce app-managed device
  registration, pairing approval, session slots, or renewal gates.
- Shop creation must start with a zero balance and no fabricated last
  transaction metadata. Route/shop counts and financial ledger/balance changes
  must remain atomic.
- Standalone transaction rows must link to the exact same-batch shop/balance
  update. Invoice batches can contain multiple ledger entries; validate their
  references and aggregate balance behavior instead of assuming one entry per
  balance change.
- Add denied and permitted emulator cases before implementation. Keep valid
  admin/seller CRUD, invoices, stock deductions, and restoration paths passing.
- For support access, test the full profile/log batch. Deny profile-only starts,
  exits, and switches; mismatched event IDs; wrong actor, workspace, reason,
  timestamps, or prior start ID; and edits/deletes of existing audit events.
- Minimize Rules document lookups and expression count. Test representative
  atomic batches against the emulator's limits.
- Run `firebase emulators:exec --only firestore "npm test"` from
  `tests/firestore-rules/` on Windows, or use the equivalent repository test
  workflow on another platform.
- Never claim a production Rules deployment from emulator output. Deploy only
  when the user explicitly authorizes production deployment.
